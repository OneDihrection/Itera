#!/usr/bin/env python3
# generate_marizka_counts.py
# Created by dimaswisodewo on 16/11/2026.
"""Generate offline number clips for both app languages.

Indonesian numbers are spoken by Marizka and English numbers by Katherine, the voices of each
language's instructions (generate_narration.VOICE_NAMES). The script and the marizka-<language>-…
filenames keep their names because NarrationClips.countResourceName depends on them.

From the repository root, set ELEVENLABS_API_KEY in the environment, then run:

    python3 Tools/generate_marizka_counts.py --dry-run
    python3 Tools/generate_marizka_counts.py
    python3 Tools/generate_marizka_counts.py --check
    xcodegen generate

Retake only some clips (other takes keep their fingerprint and cost no credits):

    python3 Tools/generate_marizka_counts.py --only 'marizka-id-countdown-5,marizka-en-countdown-*'

Re-level existing raw takes, or listen at the app's timing, without API calls:

    python3 Tools/generate_marizka_counts.py --normalize-only
    python3 Tools/generate_marizka_counts.py --audition countdown --language id

Every number must sound equally low, stable and calm, like the bundled Indonesian
instructions in Tuntun/Resources/Audio/NarrationID. Takes therefore use the same unspoken
"explaining slowly" lead-in as Tools/generate_narration.py, each clip is recorded with
several seeds, and Tools/measure_pitch.swift keeps the take closest to the instructions'
pitch without a rising ending. --check fails any chosen take that still sounds higher or
more upbeat than the instructions.

Repetition takes are deliberately slow and follow the number said before them, so counts
sound like one series. Countdown takes are separate, shorter recordings so the app's
one-second countdown does not cut off a long number. Only new or changed takes use
ElevenLabs credits. The app bundles normalized AAC; it does not connect to ElevenLabs while
a patient exercises.
"""

import argparse
import fnmatch
import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import generate_narration as narration

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "Tools/NarrationRaw/MarizkaCounts"
# Every seeded take, kept out of the bundle and out of git; RAW holds only the chosen ones.
CANDIDATES = RAW / "candidates"
OUTPUT = ROOT / "Tuntun/Resources/Audio/MarizkaCounts"
MANIFEST = ROOT / "Tools/marizka-counts-manifest.json"
MODEL = "eleven_multilingual_v2"
LANGUAGES = ("id", "en")
REPETITION_RANGE = range(1, 101)
COUNTDOWN_RANGE = range(1, 11)
# Narration is the calmest delivery that stays clear: the slowest pace each timing bound
# allows, with stability, similarity and speaker boost kept for clear words and no style.
# Stability 0.70 matches the NarrationID instructions; 0.95 measured higher and less even.
REPETITION_SETTINGS = {
    "stability": 0.70,
    "similarity_boost": 0.80,
    "style": 0.0,
    "use_speaker_boost": True,
    "speed": 0.78,
}
# One pace per language, so every number in a countdown sounds equally calm. Each is the
# slowest speed whose takes fit MAX_COUNTDOWN_SECONDS. Indonesian numbers are longer
# ("sembilan", "sepuluh"), so they need a quicker take to fit the clock.
COUNTDOWN_SPEED = {
    "id": 1.00,
    "en": 0.90,
}
SEED = 20261116
# Each clip is recorded once per seed and the calmest take is kept. A clip whose takes all
# fail the calm gate gets one more seed at a time, up to MAX_TAKES; recorded takes are cached,
# so rerunning a clip only pays for seeds it has not tried yet.
TAKE_SEEDS = (SEED, SEED + 1, SEED + 2)
MAX_TAKES = 10
# Repetitions whose takes all came out energetic (about 190-330 Hz) or with an odd pause
# after the previous number in context, even with MAX_TAKES seeds (2026-11-16). With the lead-in alone they
# measured close to the instructions' pitch, so they are recorded without it.
PLAIN_CONTEXT_CLIPS = {
    "marizka-id-repetition-47",
    "marizka-id-repetition-58",
    "marizka-id-repetition-68",
    "marizka-id-repetition-83",
    "marizka-id-repetition-85",
    "marizka-id-repetition-88",
}
MAX_COUNTDOWN_SECONDS = 0.90
# measure_pitch predicts the trimmed length without the normalizer's padding (about 0.04 s).
MAX_COUNTDOWN_SPAN_SECONDS = 0.84
# Longer silences inside a number are odd mid-word pauses or extra sounds, not calm pacing.
MAX_INNER_PAUSE_SECONDS = 0.45
AUDITION_COUNTDOWN = (5, 4, 3, 2, 1)
AUDITION_REPETITIONS = range(1, 11)


def spoken_text(language, kind, number):
    """The exact words of one take: repetitions end with a full stop, countdowns do not."""
    word = narration.indonesian_number(number) if language == "id" else narration.english_number(number)
    return word.capitalize() + ("." if kind == "repetition" else "")


def clip_name(language, kind, number):
    """Must match NarrationClips.countResourceName(_:language:countdown:) in the app."""
    return f"marizka-{language}-{kind}-{number}"


def lines():
    for language in LANGUAGES:
        for kind, numbers in (("repetition", REPETITION_RANGE), ("countdown", COUNTDOWN_RANGE)):
            for number in numbers:
                yield {
                    "name": clip_name(language, kind, number),
                    "text": spoken_text(language, kind, number),
                    "language": language,
                    "kind": kind,
                    "number": number,
                }


def settings_for(line):
    if line["kind"] != "countdown":
        return REPETITION_SETTINGS

    return {**REPETITION_SETTINGS, "speed": COUNTDOWN_SPEED[line["language"]]}


def lead_in_for(line):
    """The instructions' lead-in: "explaining slowly" measured lower and calmer than "counting"."""
    if line["language"] == "id":
        return narration.TONE_LEAD_IN
    return "In a soft, calm and patient voice, she explains slowly:"


def context_for(line):
    """Unspoken previous_text: the calm lead-in, then the previous repetition number.

    The preceding number makes a repetition take sound like the next count in a series.
    Countdown takes get the lead-in only: with a number before them the model spoke them
    more slowly, so Indonesian countdowns fitted the one-second clock only at the maximum
    speed. next_text is deliberately not sent: with eleven_multilingual_v2 it made many
    takes speak the following number too (2026-11-16 render, e.g. "Satu. Dua.").
    """
    previous_text = lead_in_for(line)
    if line["name"] in PLAIN_CONTEXT_CLIPS:
        return previous_text

    before = line["number"] - 1
    if line["kind"] == "repetition" and before in REPETITION_RANGE:
        previous_text += " " + spoken_text(line["language"], line["kind"], before)

    return previous_text


def fingerprint(line, voice_id, seed):
    payload = [line["text"], voice_id, MODEL, settings_for(line), seed, context_for(line)]
    return hashlib.sha256(json.dumps(payload, sort_keys=True).encode()).hexdigest()


def candidate_path(line, seed):
    return CANDIDATES / f'{line["name"]}-{seed}.mp3'


def duration(path):
    result = subprocess.run(
        ["/usr/bin/afinfo", str(path)],
        check=True,
        capture_output=True,
        text=True,
    )
    match = re.search(r"estimated duration:\s*([\d.]+) sec", result.stdout)
    if match is None:
        raise RuntimeError(f"Could not read duration of {path}")
    return float(match.group(1))


# MARK: - Calm gate


def calm_problems(line, measurement):
    """Why a take is not calm enough, or an empty list when it passes the calm gate."""
    if measurement is None:
        return ["no measurable voice"]

    hertz, rise, span, pause = measurement
    problems = []
    if narration.semitones_above_reference(hertz) > narration.MAX_SEMITONES_ABOVE_REFERENCE:
        problems.append(f"{hertz:.0f} Hz")
    if rise > narration.MAX_ENDING_RISE_SEMITONES:
        problems.append(f"ending rises {rise:+.1f} st")
    if line["kind"] == "countdown" and span > MAX_COUNTDOWN_SPAN_SECONDS:
        problems.append(f"{span:.2f} s span")
    if pause > MAX_INNER_PAUSE_SECONDS:
        problems.append(f"{pause:.2f} s pause inside")
    return problems


def calm_score(line, measurement):
    """Lower is calmer: semitones above the instructions' pitch plus any rising ending."""
    if measurement is None:
        return math.inf

    hertz, rise, span, pause = measurement
    score = max(0.0, narration.semitones_above_reference(hertz)) + max(0.0, rise)
    if line["kind"] == "countdown" and span > MAX_COUNTDOWN_SPAN_SECONDS:
        # A take that cannot fit the one-second clock only wins when none can.
        score += 100
    if pause > MAX_INNER_PAUSE_SECONDS:
        score += 100
    return score


# MARK: - Checks


def check_outputs():
    """Reports missing, stray, overlong and energetic clips; True when the bundle is usable."""
    planned = list(lines())
    names = {line["name"] for line in planned}
    manifest = json.loads(MANIFEST.read_text()) if MANIFEST.exists() else {}

    missing = []
    missing_raw = []
    long_countdowns = []
    longest_repetition = {}

    for line in planned:
        name = line["name"]
        if not (RAW / (name + ".mp3")).is_file() or name not in manifest:
            missing_raw.append(name)

        path = OUTPUT / (name + ".m4a")
        if not path.is_file():
            missing.append(name)
            continue

        seconds = duration(path)
        if line["kind"] == "countdown":
            if seconds > MAX_COUNTDOWN_SECONDS:
                long_countdowns.append((name, seconds))
            continue

        current = longest_repetition.get(line["language"])
        if current is None or seconds > current[1]:
            longest_repetition[line["language"]] = (name, seconds)

    stray = sorted(
        path.name for path in OUTPUT.glob("*")
        if path.is_file() and path.stem not in names
    )
    energetic = energetic_takes(planned)

    print(
        f"Missing clips: {len(missing)}; stray files: {len(stray)}; "
        f"raw takes missing or unrecorded: {len(missing_raw)}; "
        f"countdowns over {MAX_COUNTDOWN_SECONDS:.2f} s: {len(long_countdowns)}; "
        f"not calm: {len(energetic)}"
    )
    print_limited("missing", missing)
    print_limited("stray", stray)
    print_limited("no raw take", missing_raw)
    for name, seconds in long_countdowns:
        print(f"  long {name}: {seconds:.2f} s")
    for name, problems in energetic:
        print(f"  not calm {name}: {', '.join(problems)}")
    for language, (name, seconds) in sorted(longest_repetition.items()):
        print(f"  longest {language} repetition: {name} ({seconds:.2f} s)")

    retake = [name for name, _ in long_countdowns] + [name for name, _ in energetic]
    if retake:
        print(
            f"Try more seeds for just these (up to {MAX_TAKES} takes each):\n"
            f"  python3 Tools/generate_marizka_counts.py --only '{','.join(sorted(set(retake)))}'",
            file=sys.stderr,
        )

    return not missing and not stray and not missing_raw and not long_countdowns and not energetic


def energetic_takes(planned):
    """Chosen raw takes that fail the calm gate, after printing each language's pitch."""
    takes = [RAW / (line["name"] + ".mp3") for line in planned]
    measurements = narration.measure([path for path in takes if path.is_file()])

    for language in LANGUAGES:
        pitches = sorted(
            measurements[line["name"]][0] for line in planned
            if line["language"] == language and line["name"] in measurements
        )
        if pitches:
            print(
                f"  {language} pitch: median {pitches[len(pitches) // 2]:.0f} Hz, "
                f"90th percentile {pitches[int(len(pitches) * 0.9)]:.0f} Hz "
                f"(instructions: {narration.REFERENCE_PITCH_HZ:.0f} Hz)"
            )

    energetic = []
    for line, path in zip(planned, takes):
        if not path.is_file():
            continue
        problems = calm_problems(line, measurements.get(line["name"]))
        if problems:
            energetic.append((line["name"], problems))
    return energetic


def print_limited(label, names, limit=10):
    for name in names[:limit]:
        print(f"  {label} {name}")
    if len(names) > limit:
        print(f"  ... and {len(names) - limit} more {label}")


# MARK: - Audition


def audition(kind, language):
    """Plays bundled clips locally the way a session schedules them."""
    if kind == "countdown":
        # The app starts each countdown number on its own one-second tick.
        start = time.monotonic()
        players = []
        for tick, number in enumerate(AUDITION_COUNTDOWN):
            time.sleep(max(0, start + tick - time.monotonic()))
            path = OUTPUT / (clip_name(language, "countdown", number) + ".m4a")
            print(f"{tick} s  {path.name}", flush=True)
            players.append(subprocess.Popen(["/usr/bin/afplay", str(path)]))

        for player in players:
            player.wait()
        return

    # Repetition counts play back to back, as queued accepted repetitions do.
    for number in AUDITION_REPETITIONS:
        path = OUTPUT / (clip_name(language, "repetition", number) + ".m4a")
        print(path.name, flush=True)
        subprocess.run(["/usr/bin/afplay", str(path)], check=True)


# MARK: - Rendering


def api_key_from_local_env():
    """Read only the named key from the repo's ignored .env, without executing it."""
    local_env = ROOT / ".env"
    if not local_env.is_file():
        return None

    for row in local_env.read_text(encoding="utf-8").splitlines():
        name, separator, value = row.partition("=")
        if separator and name.strip() == "ELEVENLABS_API_KEY":
            return value.strip().strip('"\'')
    return None


def find_voice(api_key, name):
    response = narration.request(
        "GET", "/v2/voices", api_key, query={"search": name, "page_size": 100}
    )
    voices = json.loads(response).get("voices", [])
    exact = [voice for voice in voices if voice.get("name", "").strip().casefold() == name.casefold()]
    matches = exact or [
        voice for voice in voices if voice.get("name", "").strip().casefold().startswith(name.casefold())
    ]
    if len(matches) != 1:
        raise SystemExit(
            f'Expected one voice named "{name}" in My Voices, found {len(matches)}. '
            "Add it in ElevenLabs or pass --voice-id explicitly."
        )
    return matches[0]["voice_id"], matches[0]["name"]


def selected(line, patterns):
    return not patterns or any(fnmatch.fnmatchcase(line["name"], pattern) for pattern in patterns)


def render(line, seed, voice_id, api_key):
    body = {
        "text": line["text"],
        "model_id": MODEL,
        "voice_settings": settings_for(line),
        "seed": seed,
        "previous_text": context_for(line),
    }
    return narration.request(
        "POST",
        f"/v1/text-to-speech/{voice_id}",
        api_key,
        query={"output_format": "mp3_44100_128"},
        body=body,
        accept="audio/mpeg",
    )


class Recorder:
    """Records seeded candidate takes, skipping those whose fingerprint is unchanged."""

    def __init__(self, voice_ids, api_key, manifest, force):
        # One voice per language, so a run records each number in its language's voice.
        self.voice_ids = voice_ids
        self.api_key = api_key
        self.manifest = manifest
        self.force = force
        self.rendered = 0

    def takes(self, line, seeds):
        voice_id = self.voice_ids[line["language"]]
        paths = []
        for seed in seeds:
            path = candidate_path(line, seed)
            key = f'{line["name"]}@{seed}'
            stamp = fingerprint(line, voice_id, seed)
            if self.force or not path.exists() or self.manifest.get(key) != stamp:
                print(f'render {line["name"]} seed {seed}: {line["text"]}', flush=True)
                path.write_bytes(render(line, seed, voice_id, self.api_key))
                self.manifest[key] = stamp
                self.save()
                self.rendered += 1
            paths.append(path)
        return paths

    def save(self):
        MANIFEST.write_text(json.dumps(self.manifest, indent=2, sort_keys=True) + "\n")


def choose_take(line, recorder):
    """Keeps the calmest seeded take as the clip's raw take; returns its remaining problems."""
    paths = recorder.takes(line, TAKE_SEEDS)
    measurements = narration.measure(paths)

    def best(candidates):
        return min(candidates, key=lambda path: calm_score(line, measurements.get(path.stem)))

    chosen = best(paths)
    next_seed = TAKE_SEEDS[-1] + 1
    while calm_problems(line, measurements.get(chosen.stem)) and len(paths) < MAX_TAKES:
        extra = recorder.takes(line, (next_seed,))
        measurements.update(narration.measure(extra))
        paths += extra
        chosen = best(paths)
        next_seed += 1

    shutil.copyfile(chosen, RAW / (line["name"] + ".mp3"))
    recorder.manifest[line["name"]] = int(chosen.stem.rsplit("-", 1)[1])
    recorder.save()
    return calm_problems(line, measurements.get(chosen.stem))


def normalize(planned=None):
    """Levels raw takes into the bundle folder; with `planned`, only those clips.

    The normalizer reads a whole folder, so selected takes are levelled from a temporary copy;
    otherwise re-encoding would rewrite every other bundled number.
    """
    print(f"Normalizing into {OUTPUT.relative_to(ROOT)}.", flush=True)
    if planned is None:
        result = subprocess.run(["swift", str(narration.NORMALIZER), str(RAW), str(OUTPUT)])
        return result.returncode == 0

    with tempfile.TemporaryDirectory() as selected:
        for line in planned:
            source = RAW / (line["name"] + ".mp3")
            if source.is_file():
                shutil.copyfile(source, Path(selected) / source.name)
        result = subprocess.run(["swift", str(narration.NORMALIZER), selected, str(OUTPUT)])
    return result.returncode == 0


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument(
        "--voice-name",
        help="Use this voice for every selected clip instead of each language's VOICE_NAMES voice.",
    )
    parser.add_argument("--voice-id", help="Use this voice ID for every selected clip.")
    parser.add_argument(
        "--only",
        help="Comma-separated clip names or globs to render, e.g. 'marizka-id-countdown-*'.",
    )
    parser.add_argument("--dry-run", action="store_true", help="List planned clips without API calls.")
    parser.add_argument(
        "--check",
        action="store_true",
        help="Check bundled clips, countdown durations and that every chosen take is calm.",
    )
    parser.add_argument("--normalize-only", action="store_true", help="Re-level existing raw takes; no API calls.")
    parser.add_argument(
        "--audition",
        choices=("countdown", "repetition"),
        help="Play bundled clips at session timing: countdown 5-1 on one-second ticks, or repetitions 1-10.",
    )
    parser.add_argument("--language", choices=LANGUAGES, default="id", help="Language for --audition.")
    parser.add_argument("--force", action="store_true", help="Re-record every take of the selected numbers.")
    args = parser.parse_args()

    if args.check:
        return 0 if check_outputs() else 1

    if args.audition:
        audition(args.audition, args.language)
        return 0

    if args.normalize_only:
        if not normalize():
            return 1
        return 0 if check_outputs() else 1

    patterns = [pattern.strip() for pattern in (args.only or "").split(",") if pattern.strip()]
    planned = [line for line in lines() if selected(line, patterns)]
    if not planned:
        parser.error(f"--only matched no clips: {args.only}")

    if args.dry_run:
        for line in planned:
            print(f'{line["name"]}: {line["text"]}  [{context_for(line)}]')
        characters = sum(len(line["text"]) for line in planned)
        print(f"{len(planned)} clips, {characters * len(TAKE_SEEDS)} characters for {len(TAKE_SEEDS)} takes each")
        return 0

    api_key = os.environ.get("ELEVENLABS_API_KEY") or api_key_from_local_env()
    if not api_key:
        parser.error("Set ELEVENLABS_API_KEY in the environment or ignored .env file.")

    voice_ids = {}
    for language in sorted({line["language"] for line in planned}):
        voice_id, voice_name = (
            (args.voice_id, args.voice_id) if args.voice_id
            else find_voice(api_key, args.voice_name or narration.VOICE_NAMES[language])
        )
        voice_ids[language] = voice_id
        print(f"Voice ({language}): {voice_name} ({voice_id}), model: {MODEL}")

    CANDIDATES.mkdir(parents=True, exist_ok=True)
    manifest = json.loads(MANIFEST.read_text()) if MANIFEST.exists() else {}
    recorder = Recorder(voice_ids, api_key, manifest, args.force)
    still_energetic = []

    for line in planned:
        problems = choose_take(line, recorder)
        if problems:
            still_energetic.append((line["name"], problems))

    print(f"Rendered {recorder.rendered} takes for {len(planned)} selected clips.")
    for name, problems in still_energetic:
        print(f"  best take still not calm {name}: {', '.join(problems)}", file=sys.stderr)

    if not normalize(planned if patterns else None):
        parser.error("Normalization failed; raw MP3 files are still available for retry.")

    if not check_outputs():
        return 1

    print("Next: run xcodegen generate, then build and listen on the baseline iPad.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
