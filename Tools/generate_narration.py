#!/usr/bin/env python3
# generate_narration.py
# Created by Amelia Putri Aftiana on 05/11/2026.
"""Renders Tuntun's narration once with ElevenLabs, for bundling in the app.

Each spoken sentence is a String Catalog key. Tools/narration-registry.json lists every
narrated key with its group, languages, on-screen role and voice tuning; the words live only in
the catalog (the key's text, or `speak.<key>` when the spoken wording differs from the screen).
This script reads the text of those keys in
one language and saves one MP3 per key under Tools/NarrationRaw (Indonesian) or
Tools/NarrationRaw/EN (English), then runs Tools/normalize_narration.swift to level their
loudness into Tuntun/Resources/Audio/NarrationID or NarrationEN as AAC. The app plays a
recording when one exists and otherwise uses the iPad voice, so sessions stay offline and
nothing is sent anywhere while a patient exercises.

Usage, from the repository root:
    export ELEVENLABS_API_KEY="..."          # your own key; never commit it
    python3 Tools/generate_narration.py --dry-run
    python3 Tools/generate_narration.py
    python3 Tools/generate_narration.py --language en
    python3 Tools/generate_narration.py --language en --check
    xcodegen generate

Record and level only some lines; every other bundled clip is left untouched:
    python3 Tools/generate_narration.py --only 'narration-id-session.switchArm.*'

An approved Indonesian script is recorded on its own, into its own raw folder and cache:
    python3 Tools/generate_narration.py --groups opposition-left --only 'narration-id-opposition.left.rest.*'

Refresh the review sheet (every line, where it shows, what it says, whether it is bundled):
    python3 Tools/generate_narration.py --report

A plain run re-records every sentence whose cached raw take is missing or whose fingerprint
changed, then re-levels the whole raw folder into the app. Use --only to fill gaps without
touching approved recordings. Only new or changed sentences are rendered on later runs (see Tools/narration-manifest.json
and Tools/narration-en-manifest.json). Indonesian is spoken by Marizka and English by
Katherine, a native American-English voice (VOICE_NAMES). English sentences are recorded the
way the counts are: every line must sound as low, stable and calm as the Indonesian
instructions, so each is recorded with several seeds and Tools/measure_pitch.swift keeps the
calmest take.
Numbers are not rendered here; Tools/generate_marizka_counts.py owns them.
"""

import argparse
import fnmatch
import hashlib
import json
import math
import os
import re
import ssl
import subprocess
import shutil
import socket
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "Tuntun/Resources/Localization/Localizable.xcstrings"
# Untouched ElevenLabs output, kept outside the app so it can be re-levelled without credits.
RAW = ROOT / "Tools/NarrationRaw"
OUTPUT = ROOT / "Tuntun/Resources/Audio/NarrationID"
NORMALIZER = ROOT / "Tools/normalize_narration.swift"
# Kept outside the app's sources so it is never bundled.
MANIFEST = ROOT / "Tools/narration-manifest.json"
# English recordings: same pipeline, separate folders, so the Indonesian caches stay untouched.
RAW_EN = ROOT / "Tools/NarrationRaw/EN"
OUTPUT_EN = ROOT / "Tuntun/Resources/Audio/NarrationEN"
MANIFEST_EN = ROOT / "Tools/narration-en-manifest.json"
# The language being rendered; main() switches RAW, OUTPUT and MANIFEST for English.
LANGUAGE = "id"
LANGUAGES = ("id", "en")
API = "https://api.elevenlabs.io"
# The ElevenLabs "My Voices" name that speaks each language. Katherine ("Katherine - Warm &
# Calm", Voice Library) was chosen by ear on 2026-11-19 from calm middle-aged American voices
# that passed the calm gate; Marizka's English carried an Indonesian accent.
VOICE_NAMES = {
    "id": "Marizka",
    "en": "Tuntun EN Katherine",
}
# Every narrated catalog key, its recording group, languages, on-screen role and voice tuning.
# The words themselves live only in the String Catalog.
REGISTRY = ROOT / "Tools/narration-registry.json"
DISPLAY_KINDS = {"screen", "voice", "partly"}
# Instruction groups share the default folders. Each approved Indonesian script keeps its own raw
# takes and cache, so levelling one never re-encodes another's approved clips.
GROUP_STORAGE = {
    "opposition-left": ("OppositionLeft", "opposition-left-narration-manifest.json"),
    "opposition-right": ("OppositionRight", "opposition-right-narration-manifest.json"),
    "arm-raise-left": ("ArmRaiseLeft", "arm-raise-left-narration-manifest.json"),
    "arm-raise-right": ("ArmRaiseRight", "arm-raise-right-narration-manifest.json"),
    # The 2026-11-23 left scripts. Lines every script says the same way (intro notes, praise,
    # summaries, the short rest) are recorded once in scripted-common, or scripted-left when they
    # name the left hand, so the exercises sound identical where their scripts are.
    "scripted-common": ("ScriptedCommon", "scripted-common-narration-manifest.json"),
    "scripted-left": ("ScriptedLeft", "scripted-left-narration-manifest.json"),
    "full-fist-left": ("FullFistLeft", "full-fist-left-narration-manifest.json"),
    "hook-fist-left": ("HookFistLeft", "hook-fist-left-narration-manifest.json"),
    "spreading-left": ("SpreadingLeft", "spreading-left-narration-manifest.json"),
    "extension-sequence-left": ("ExtensionSequenceLeft", "extension-sequence-left-narration-manifest.json"),
    # The second 2026-11-23 batch: body exercises and forearm rotation. Internal and external
    # rotation share one group, as their scripts differ only in "dalam" and "luar".
    "sit-to-stand": ("SitToStand", "sit-to-stand-narration-manifest.json"),
    "shoulder-flexion-left": ("ShoulderFlexionLeft", "shoulder-flexion-left-narration-manifest.json"),
    "cross-midline-left": ("CrossMidlineLeft", "cross-midline-left-narration-manifest.json"),
    "shoulder-rotation-left": ("ShoulderRotationLeft", "shoulder-rotation-left-narration-manifest.json"),
    "forearm-rotation-left": ("ForearmRotationLeft", "forearm-rotation-left-narration-manifest.json"),
}
DEFAULT_GROUPS = ("finger", "body")


def load_registry():
    return json.loads(REGISTRY.read_text(encoding="utf-8"))["lines"]


# The app speaks `speak.<key>` when the catalog has one (different from the displayed text), so
# the recording is rendered from it. Rendering a spoken variant for a key that already has a
# recording replaces that recording on the next run, because the text fingerprint changes.
SPOKEN_PREFIX = "speak."
UNITS = ["", "satu", "dua", "tiga", "empat", "lima", "enam", "tujuh", "delapan", "sembilan"]


def indonesian_number(n):
    """Indonesian words for 1-100: sebelas, dua belas, dua puluh satu, seratus."""
    if n == 100:
        return "seratus"
    if n == 10:
        return "sepuluh"
    if n == 11:
        return "sebelas"
    if n < 10:
        return UNITS[n]
    if n < 20:
        return f"{UNITS[n - 10]} belas"
    tens, unit = divmod(n, 10)
    return f"{UNITS[tens]} puluh" + (f" {UNITS[unit]}" if unit else "")


def english_number(number):
    """English words for 1-100: eleven, twenty one, one hundred."""
    small = (
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight",
        "nine", "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen",
        "sixteen", "seventeen", "eighteen", "nineteen",
    )
    if number < 20:
        return small[number]
    if number == 100:
        return "one hundred"

    tens = ("", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety")
    quotient, remainder = divmod(number, 10)
    return tens[quotient] + (" " + small[remainder] if remainder else "")


# Calm, clear delivery for older patients. `speed` below 1 slows speech slightly.
VOICE_SETTINGS = {
    # Higher stability keeps the delivery the same from one line to the next (ElevenLabs: lower
    # values add randomness between generations); 0.70 stays clear of a monotone voice.
    "stability": 0.70,
    "similarity_boost": 0.8,
    # Style exaggeration makes the model less stable; a soft, explaining tone needs none.
    "style": 0.0,
    "use_speaker_boost": True,
    "speed": 0.88,
}

# Every line uses the same seed, so sampling is as repeatable as the API allows
# ("best effort", not guaranteed), and the same unspoken lead-in, which steers each line
# toward one soft, patient, explaining delivery instead of each clip finding its own tone.
SEED = 20261110

# Per-line tuning lives in the registry's `tuning.<language>`:
# - `seed`: takes that came out rushed with the shared seed (well above the ~10 characters per
#   second of the other lines) are re-rendered with their own seed. Change it to retake a line.
# - `speed`: short commands the model reads in a rush even with another seed get a slower speed
#   (the API accepts speeds from 0.7), so their pace matches the other lines. Only `speed`
#   changes; stability, style and the lead-in stay the same, so the voice does not.
# - `leadIn`: an instruction added to the unspoken lead-in, so the line is rendered as its next
#   sentence and carries on in the same tone ("Posisikan tangan…" follows "Gunakan tangan kanan.").


def seed_for(line):
    # English takes set their own `seed` while recording the calmest of several.
    return line.get("seed") or line.get("tuning", {}).get("seed", SEED)


def settings_for(line):
    settings = dict(VOICE_SETTINGS)
    speed = line.get("tuning", {}).get("speed")
    if speed is not None:
        settings["speed"] = speed
    return settings


TONE_LEAD_IN = "Dengan suara yang lembut, tenang, dan sabar, ia menjelaskan pelan-pelan:"
# The same "explaining slowly" direction for English, which measured as calm as Indonesian.
TONE_LEAD_IN_EN = "In a soft, calm and patient voice, she explains slowly:"


def lead_in_for(line):
    base = TONE_LEAD_IN_EN if LANGUAGE == "en" else TONE_LEAD_IN
    extra = line.get("tuning", {}).get("leadIn")
    return f"{base} {extra}" if extra else base


def clip_name(key, argument=None):
    """Must match NarrationClips.resourceName(for:language:) in the app."""
    name = key.replace(" %lld", "")
    if argument is not None:
        name += f"-{argument}"
    return f"narration-{LANGUAGE}-" + re.sub(r"[^A-Za-z0-9._-]", "_", name)


def localized_text(entry, language):
    unit = entry.get("localizations", {}).get(language, {}).get("stringUnit")
    return unit.get("value") if unit else None


def indonesian_text(entry):
    return localized_text(entry, "id")


def spoken_number(argument, spelled):
    """Counts the patient hears are spelled out ("enam napas lagi", "six breaths left")."""
    if not spelled:
        return str(argument)
    return indonesian_number(argument) if LANGUAGE == "id" else english_number(argument)


def spoken_text(strings, key, language):
    """The words a key speaks: its `speak.<key>` variant, otherwise its displayed text."""
    return (
        localized_text(strings.get(SPOKEN_PREFIX + key, {}), language)
        or localized_text(strings.get(key, {}), language)
    )


def collect_lines(groups):
    """Every registry line in `groups` for the current language, with its spoken text."""
    strings = json.loads(CATALOG.read_text(encoding="utf-8"))["strings"]
    lines = []

    for entry in load_registry():
        if entry["group"] not in groups or LANGUAGE not in entry["languages"]:
            continue

        text = spoken_text(strings, entry["key"], LANGUAGE)
        if not text:
            sys.exit(f"{entry['key']}: no {LANGUAGE} text in the String Catalog.")

        tuning = entry.get("tuning", {}).get(LANGUAGE, {})
        for argument in entry.get("arguments") or (None,):
            spoken = text
            if argument is not None:
                spoken = text.replace("%lld", spoken_number(argument, entry.get("spellNumber", False)))

            lines.append({
                "key": entry["key"],
                "argument": argument,
                "text": spoken,
                "name": clip_name(entry["key"], argument),
                "tuning": tuning,
            })

    return sorted(lines, key=lambda line: line["name"])


# MARK: - Registry checks


def registry_problems():
    """Registry errors that would record the wrong text or overwrite another clip."""
    strings = json.loads(CATALOG.read_text(encoding="utf-8"))["strings"]
    problems = []
    seen = set()

    for entry in load_registry():
        key = entry["key"]
        if key in seen:
            problems.append(f"{key}: listed twice")
        seen.add(key)

        if entry.get("group") not in DEFAULT_GROUPS and entry.get("group") not in GROUP_STORAGE:
            problems.append(f"{key}: unknown group {entry.get('group')!r}")
        if entry.get("display") not in DISPLAY_KINDS:
            problems.append(f"{key}: display must be one of {sorted(DISPLAY_KINDS)}")
        if key.endswith(" %lld") != bool(entry.get("arguments")):
            problems.append(f"{key}: format keys, and only they, list `arguments`")
        for language in entry.get("languages", []):
            if language not in LANGUAGES:
                problems.append(f"{key}: unknown language {language!r}")
            elif not spoken_text(strings, key, language):
                problems.append(f"{key}: no {language} text in the String Catalog")

    return problems


def unregistered_spoken_keys():
    """`speak.<key>` variants whose key no registry line records."""
    strings = json.loads(CATALOG.read_text(encoding="utf-8"))["strings"]
    registered = {entry["key"] for entry in load_registry()}
    return sorted(
        key[len(SPOKEN_PREFIX):] for key in strings
        if key.startswith(SPOKEN_PREFIX) and key[len(SPOKEN_PREFIX):] not in registered
    )


def verify_registry():
    problems = registry_problems()
    for problem in problems:
        print(f"registry: {problem}", file=sys.stderr)
    for key in unregistered_spoken_keys():
        print(f"registry: warning: speak.{key} has no registry line, so it is never recorded", file=sys.stderr)
    if problems:
        sys.exit(f"Fix {len(problems)} problem(s) in {REGISTRY.relative_to(ROOT)}.")


def tls_context():
    """HTTPS verification that also works with python.org installs on macOS.

    Those builds ship without certificates; macOS keeps its trusted roots in
    /etc/ssl/cert.pem, so load them as well as Python's defaults.
    """
    context = ssl.create_default_context()
    system_bundle = Path("/etc/ssl/cert.pem")
    if system_bundle.exists():
        context.load_verify_locations(cafile=str(system_bundle))
    return context


TLS = tls_context()


def request(method, path, api_key, query=None, body=None, accept="application/json"):
    url = API + path + ("?" + urllib.parse.urlencode(query) if query else "")
    data = json.dumps(body).encode() if body is not None else None
    headers = {"xi-api-key": api_key, "Accept": accept}
    if data is not None:
        headers["Content-Type"] = "application/json"

    for attempt in range(5):
        req = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=120, context=TLS) as response:
                return response.read()
        except urllib.error.HTTPError as error:
            detail = error.read().decode(errors="replace")[:300]
            if error.code == 429 or error.code >= 500:
                wait = 2 ** attempt
                print(f"  {error.code}, retrying in {wait}s", file=sys.stderr)
                time.sleep(wait)
                continue
            sys.exit(f"ElevenLabs error {error.code} on {path}: {detail}")
        except (TimeoutError, socket.timeout):
            # A slow render or a stalled connection; recorded takes are cached, so retrying is safe.
            wait = 2 ** attempt
            print(f"  timed out, retrying in {wait}s", file=sys.stderr)
            time.sleep(wait)
            continue
        except urllib.error.URLError as error:
            if "CERTIFICATE_VERIFY_FAILED" in str(error.reason):
                sys.exit(
                    "This Python cannot verify HTTPS certificates (common with python.org installs).\n"
                    "Run the script with Apple's Python instead:  /usr/bin/python3 Tools/generate_narration.py\n"
                    'or install certificates once:  open "/Applications/Python 3.14/Install Certificates.command"'
                )
            sys.exit(f"Could not reach ElevenLabs: {error.reason}")
    sys.exit(f"ElevenLabs kept failing on {path}; try again later.")


def find_voice(api_key, name):
    """The voice_id of a voice named `name` in your ElevenLabs "My Voices"."""
    found = json.loads(request("GET", "/v2/voices", api_key, {"search": name, "page_size": 100}))
    for voice in found.get("voices", []):
        if voice.get("name", "").strip().lower().startswith(name.lower()):
            return voice["voice_id"], voice["name"]

    sys.exit(
        f'No voice named "{name}" in your ElevenLabs voices.\n'
        f'Open ElevenLabs > Voices > Voice Library, search "{name}", add it to My Voices, '
        "then run this again. Or pass --voice-id with its ID."
    )


# MARK: - Calm takes

PITCH_SOURCE = ROOT / "Tools/measure_pitch.swift"
# Compiled once per change: the interpreted script is too slow for hundreds of takes.
PITCH_TOOL = Path(tempfile.gettempdir()) / "itera-measure-pitch"
# Median pitch of the 548 Indonesian instruction clips in NarrationID, measured with
# Tools/measure_pitch.swift on 2026-11-16 (90th percentile 184 Hz, about 2 semitones above).
REFERENCE_PITCH_HZ = 163.0
MAX_SEMITONES_ABOVE_REFERENCE = 2.0
# The instructions' 90th-percentile ending rise; anything higher sounds upbeat or unfinished.
MAX_ENDING_RISE_SEMITONES = 1.6
# English sentences are recorded with these seeds, one more at a time up to MAX_TAKES while
# none passes the calm gate; recorded takes are cached by fingerprint.
TAKE_SEEDS = (SEED, SEED + 1, SEED + 2)
MAX_TAKES = 10


def pitch_tool():
    """Path of the compiled measure_pitch.swift, rebuilt when the source changes."""
    if PITCH_TOOL.exists() and PITCH_TOOL.stat().st_mtime >= PITCH_SOURCE.stat().st_mtime:
        return PITCH_TOOL

    print("Compiling Tools/measure_pitch.swift...", flush=True)
    subprocess.run(["swiftc", "-O", "-o", str(PITCH_TOOL), str(PITCH_SOURCE)], check=True)
    return PITCH_TOOL


def measure(paths):
    """{file stem: (median Hz, ending rise in semitones, trimmed seconds, longest pause)}."""
    if not paths:
        return {}

    result = subprocess.run(
        [str(pitch_tool()), *map(str, paths)],
        check=True,
        capture_output=True,
        text=True,
    )
    measurements = {}
    for row in result.stdout.splitlines():
        name, *values = row.split("\t")
        measurements[name] = tuple(float(value) for value in values)
    return measurements


def semitones_above_reference(hertz):
    return 12 * math.log2(hertz / REFERENCE_PITCH_HZ)


def sentence_problems(measurement):
    """Why a sentence take is not calm, or an empty list. Commas pause naturally, so
    sentences skip the count clips' inner-pause and length checks."""
    if measurement is None:
        return ["no measurable voice"]

    hertz, rise = measurement[0], measurement[1]
    problems = []
    if semitones_above_reference(hertz) > MAX_SEMITONES_ABOVE_REFERENCE:
        problems.append(f"{hertz:.0f} Hz")
    if rise > MAX_ENDING_RISE_SEMITONES:
        problems.append(f"ending rises {rise:+.1f} st")
    return problems


def sentence_score(measurement):
    """Lower is calmer: semitones above the instructions' pitch plus any rising ending."""
    if measurement is None:
        return math.inf

    hertz, rise = measurement[0], measurement[1]
    return max(0.0, semitones_above_reference(hertz)) + max(0.0, rise)


def fingerprint(line, voice_id, model):
    payload = json.dumps([line["text"], voice_id, model, settings_for(line), seed_for(line), lead_in_for(line)], sort_keys=True)
    return hashlib.sha256(payload.encode()).hexdigest()


def main():
    global LANGUAGE, RAW, OUTPUT, MANIFEST

    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--voice-name", help="Override the language's voice in VOICE_NAMES.")
    parser.add_argument("--voice-id", help="Use this voice ID instead of searching by name.")
    parser.add_argument("--model", default="eleven_multilingual_v2")
    parser.add_argument("--language", choices=LANGUAGES, default="id", help="Catalog language to record.")
    parser.add_argument(
        "--groups",
        help=(
            "Comma-separated registry groups (default: finger,body). A script group "
            "(any group in GROUP_STORAGE) is recorded on its own."
        ),
    )
    parser.add_argument(
        "--only",
        help="Comma-separated clip names or globs to render and level, e.g. 'narration-id-demo.step.*'.",
    )
    parser.add_argument("--dry-run", action="store_true", help="List sentences and characters only.")
    parser.add_argument("--force", action="store_true", help="Re-render every sentence.")
    parser.add_argument("--normalize-only", action="store_true", help="Re-level existing raw clips; no API calls.")
    parser.add_argument("--check", action="store_true", help="English: report missing and not-calm clips.")
    parser.add_argument("--report", action="store_true", help=f"Write {REPORT.relative_to(ROOT)} and stop.")
    args = parser.parse_args()

    verify_registry()
    if args.report:
        write_report()
        return

    LANGUAGE = args.language
    if LANGUAGE == "en":
        RAW, OUTPUT, MANIFEST = RAW_EN, OUTPUT_EN, MANIFEST_EN

    allowed = {entry["group"] for entry in load_registry() if LANGUAGE in entry["languages"]}
    groups = {group.strip() for group in (args.groups or ",".join(DEFAULT_GROUPS)).split(",")}
    unknown = groups - allowed
    if unknown:
        parser.error("Unknown groups for this language: " + ", ".join(sorted(unknown)))

    scripts = groups & GROUP_STORAGE.keys()
    if scripts and len(groups) > 1:
        parser.error("Record an approved script on its own: " + ", ".join(sorted(scripts)))
    if scripts:
        folder, manifest_name = GROUP_STORAGE[next(iter(scripts))]
        RAW, MANIFEST = RAW / folder, ROOT / "Tools" / manifest_name

    all_lines = collect_lines(groups)
    patterns = [pattern.strip() for pattern in (args.only or "").split(",") if pattern.strip()]
    lines = [
        line for line in all_lines
        if not patterns or any(fnmatch.fnmatchcase(line["name"], pattern) for pattern in patterns)
    ]
    if not lines:
        parser.error(f"--only matched no sentences: {args.only}")
    characters = sum(len(line["text"]) for line in lines)

    if args.check:
        if LANGUAGE != "en":
            parser.error("--check measures English recordings; use --language en.")
        sys.exit(0 if check_calm(all_lines) else 1)

    if args.normalize_only:
        normalize(lines if patterns else None)
        return

    if args.dry_run:
        for line in lines:
            print(f'{line["name"]}: {line["text"]}')
        takes = len(TAKE_SEEDS) if LANGUAGE == "en" else 1
        print(f"\n{len(lines)} sentences, {characters} characters in total ({takes} take(s) each).")
        return

    api_key = os.environ.get("ELEVENLABS_API_KEY") or local_api_key()
    if not api_key:
        sys.exit("Set ELEVENLABS_API_KEY in this terminal or the ignored .env file (it is never stored).")

    voice_id, voice_name = (args.voice_id, args.voice_id) if args.voice_id else find_voice(api_key, args.voice_name or VOICE_NAMES[LANGUAGE])
    print(f"Voice: {voice_name} ({voice_id}), model {args.model}")

    RAW.mkdir(parents=True, exist_ok=True)
    manifest = json.loads(MANIFEST.read_text()) if MANIFEST.exists() else {}
    rendered = 0

    for line in lines:
        if LANGUAGE == "en":
            rendered += record_calmest(line, voice_id, args.model, api_key, manifest, args.force)
            continue

        target = RAW / (line["name"] + ".mp3")
        stamp = fingerprint(line, voice_id, args.model)
        if not args.force and target.exists() and manifest.get(line["name"]) == stamp:
            continue

        print(f'render {line["name"]}: {line["text"]}')
        target.write_bytes(render_take(line, voice_id, args.model, api_key))
        manifest[line["name"]] = stamp
        MANIFEST.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
        rendered += 1

    print(f"\nRendered {rendered} takes for {len(lines)} sentences into {RAW.relative_to(ROOT)}.")
    normalize(lines if patterns else None)
    if LANGUAGE == "en" and not check_calm(all_lines):
        sys.exit(1)
    print("Next: run `xcodegen generate` so the new clips are bundled.")


# MARK: - Review sheet

REPORT = ROOT / "Documentation/NarrationScript.md"
REPORT_GROUPS = (
    ("finger", "Finger exercises"),
    ("body", "Body exercises, Balancing and rests"),
    ("opposition-left", "Thumb opposition script, left"),
    ("opposition-right", "Thumb opposition script, right"),
    ("arm-raise-left", "Arm raise script, left"),
    ("arm-raise-right", "Arm raise script, right"),
    ("scripted-common", "Shared lines of the left scripts (2026-11-23)"),
    ("scripted-left", "Shared left-hand lines of the left scripts (2026-11-23)"),
    ("full-fist-left", "Full fist script, left"),
    ("hook-fist-left", "Hook fist script, left"),
    ("spreading-left", "Finger spreading script, left"),
    ("extension-sequence-left", "Finger extension sequence script, left"),
    ("sit-to-stand", "Sit to stand script"),
    ("shoulder-flexion-left", "Shoulder flexion script, left"),
    ("cross-midline-left", "Cross midline (Keseimbangan) script, left"),
    ("shoulder-rotation-left", "Internal and external shoulder rotation scripts, left"),
    ("forearm-rotation-left", "Forearm rotation script, left"),
)
CLIP_FOLDERS = {"id": OUTPUT, "en": OUTPUT_EN}


def report_cell(text):
    return (text or "–").replace("|", "\\|").replace("\n", " ")


def report_wording(strings, entry, language):
    """The screen and spoken wording of a key in one language, for the review table."""
    if language not in entry["languages"]:
        return "–"

    screen = localized_text(strings.get(entry["key"], {}), language)
    spoken = localized_text(strings.get(SPOKEN_PREFIX + entry["key"], {}), language)
    if not spoken or spoken == screen:
        return report_cell(screen)
    if entry["display"] == "voice":
        return report_cell(spoken)
    return f"**Screen:** {report_cell(screen)}<br>**Spoken:** {report_cell(spoken)}"


def report_clips(entry):
    """Which recorded languages have every clip of a key bundled."""
    global LANGUAGE
    marks = []

    for language in entry["languages"]:
        LANGUAGE = language
        names = [clip_name(entry["key"], argument) for argument in entry.get("arguments") or (None,)]
        bundled = all((CLIP_FOLDERS[language] / (name + ".m4a")).is_file() for name in names)
        marks.append(f"{language} {'✓' if bundled else '✗'}")

    LANGUAGE = "id"
    return " · ".join(marks)


def write_report():
    """Writes the review sheet: every narrated line, where it shows and what it says."""
    strings = json.loads(CATALOG.read_text(encoding="utf-8"))["strings"]
    registry = load_registry()
    rows = [
        "<!-- NarrationScript.md — Created by dimaswisodewo on 19/11/2026. -->",
        "<!-- Generated by `python3 Tools/generate_narration.py --report`; do not edit by hand. -->",
        "",
        "# Narration script",
        "",
        "Every narrated line, from `Tools/narration-registry.json` and the String Catalog. Change "
        "wording in `Localizable.xcstrings` (the key for the screen, `speak.<key>` for spoken "
        "wording that differs), then re-record the line with `--only` and refresh this sheet.",
        "",
        "**Display:** *screen*: the text is shown while it is spoken. *partly*: shown in some "
        "screens only (see the note). *voice*: heard, never shown. **Clip:** ✓ when every "
        "recording of the key is bundled.",
    ]

    for group, title in REPORT_GROUPS:
        entries = [entry for entry in registry if entry["group"] == group]
        if not entries:
            continue

        rows += [
            "",
            f"## {title} (`{group}`)",
            "",
            "| Key | Display | Indonesian | English | Clip |",
            "| --- | --- | --- | --- | --- |",
        ]
        for entry in entries:
            display = entry["display"]
            if entry.get("shownOn"):
                display += f"<br><sub>{report_cell(entry['shownOn'])}</sub>"
            rows.append(
                f"| `{entry['key']}` | {display} | {report_wording(strings, entry, 'id')} "
                f"| {report_wording(strings, entry, 'en')} | {report_clips(entry)} |"
            )

    REPORT.write_text("\n".join(rows) + "\n", encoding="utf-8")
    print(f"Wrote {REPORT.relative_to(ROOT)} ({len(registry)} keys).")


def local_api_key():
    """Read only the named key from the repo's ignored .env, without executing it."""
    local_env = ROOT / ".env"
    if not local_env.is_file():
        return None

    for row in local_env.read_text(encoding="utf-8").splitlines():
        name, separator, value = row.partition("=")
        if separator and name.strip() == "ELEVENLABS_API_KEY":
            return value.strip().strip('"\'')
    return None


def render_take(line, voice_id, model, api_key):
    return request(
        "POST", f"/v1/text-to-speech/{voice_id}", api_key,
        query={"output_format": "mp3_44100_128"},
        body={
            "text": line["text"],
            "model_id": model,
            "voice_settings": settings_for(line),
            "seed": seed_for(line),
            "previous_text": lead_in_for(line),
        },
        accept="audio/mpeg",
    )


def record_calmest(line, voice_id, model, api_key, manifest, force):
    """Records seeded takes of one sentence and keeps the calmest as its raw clip.

    Returns how many takes were rendered; cached takes with an unchanged fingerprint are reused.
    """
    candidates = RAW / "candidates"
    candidates.mkdir(parents=True, exist_ok=True)
    rendered = 0
    paths = []
    measurements = {}

    def record(seed):
        nonlocal rendered
        take = {**line, "seed": seed}
        path = candidates / f'{line["name"]}-{seed}.mp3'
        key = f'{line["name"]}@{seed}'
        stamp = fingerprint(take, voice_id, model)
        if force or not path.exists() or manifest.get(key) != stamp:
            print(f'render {line["name"]} seed {seed}: {line["text"]}', flush=True)
            path.write_bytes(render_take(take, voice_id, model, api_key))
            manifest[key] = stamp
            MANIFEST.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
            rendered += 1
        paths.append(path)

    for seed in TAKE_SEEDS:
        record(seed)
    measurements.update(measure(paths))

    def calmest():
        return min(paths, key=lambda path: sentence_score(measurements.get(path.stem)))

    next_seed = TAKE_SEEDS[-1] + 1
    while sentence_problems(measurements.get(calmest().stem)) and len(paths) < MAX_TAKES:
        record(next_seed)
        measurements.update(measure(paths[-1:]))
        next_seed += 1

    chosen = calmest()
    shutil.copyfile(chosen, RAW / (line["name"] + ".mp3"))
    manifest[line["name"]] = int(chosen.stem.rsplit("-", 1)[1])
    MANIFEST.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    return rendered


def check_calm(lines):
    """Reports missing English clips and chosen takes that fail the calm gate."""
    missing = [line["name"] for line in lines if not (OUTPUT / (line["name"] + ".m4a")).is_file()]
    takes = [RAW / (line["name"] + ".mp3") for line in lines]
    measurements = measure([path for path in takes if path.is_file()])
    not_calm = [
        (line["name"], sentence_problems(measurements.get(line["name"])))
        for line, path in zip(lines, takes)
        if path.is_file() and sentence_problems(measurements.get(line["name"]))
    ]
    stray = sorted(
        path.name for path in OUTPUT.glob("*.m4a")
        if path.stem not in {line["name"] for line in lines}
    ) if OUTPUT.exists() else []

    pitches = sorted(value[0] for value in measurements.values())
    if pitches:
        print(
            f"English pitch: median {pitches[len(pitches) // 2]:.0f} Hz, "
            f"90th percentile {pitches[int(len(pitches) * 0.9)]:.0f} Hz "
            f"(Indonesian instructions: {REFERENCE_PITCH_HZ:.0f} Hz)"
        )
    print(f"Missing clips: {len(missing)}; stray clips: {len(stray)}; not calm: {len(not_calm)}")
    for name in missing[:10]:
        print(f"  missing {name}")
    for name in stray[:10]:
        print(f"  stray {name}")
    for name, problems in not_calm:
        print(f"  not calm {name}: {', '.join(problems)}")
    return not missing and not stray and not not_calm


def normalize(lines=None):
    """Levels raw clips into the app's narration folder (fast, no credits used).

    With `lines`, only their raw takes are levelled, from a temporary folder, because the
    normalizer reads a whole folder and re-encoding would rewrite every other bundled clip.
    """
    print("Levelling loudness...", flush=True)
    if lines is None:
        result = subprocess.run(["swift", str(NORMALIZER), str(RAW), str(OUTPUT)])
    else:
        with tempfile.TemporaryDirectory() as selected:
            for line in lines:
                source = RAW / (line["name"] + ".mp3")
                if source.is_file():
                    shutil.copyfile(source, Path(selected) / source.name)
            result = subprocess.run(["swift", str(NORMALIZER), selected, str(OUTPUT)])

    if result.returncode != 0:
        sys.exit("Normalizing failed; the raw MP3s are kept in Tools/NarrationRaw.")


if __name__ == "__main__":
    main()
