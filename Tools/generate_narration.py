#!/usr/bin/env python3
# generate_narration.py
# Created by Amelia Putri Aftiana on 05/11/2026.
"""Renders Itera's Indonesian narration once with ElevenLabs, for bundling in the app.

Each spoken sentence is a String Catalog key. This script reads the Indonesian text of
those keys and saves one MP3 per key under Tools/NarrationRaw, then runs
Tools/normalize_narration.swift to level their loudness into Itera/Resources/Audio/NarrationID
as AAC. The app
plays a recording when one exists and otherwise uses the iPad voice, so sessions stay
offline and nothing is sent anywhere while a patient exercises.

Usage, from the repository root:
    export ELEVENLABS_API_KEY="..."          # your own key; never commit it
    python3 Tools/generate_narration.py --dry-run
    python3 Tools/generate_narration.py
    xcodegen generate

Only new or changed sentences are rendered on later runs (see Tools/narration-manifest.json).
"""

import argparse
import hashlib
import json
import os
import re
import ssl
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "Itera/Resources/Localization/Localizable.xcstrings"
# Untouched ElevenLabs output, kept outside the app so it can be re-levelled without credits.
RAW = ROOT / "Tools/NarrationRaw"
OUTPUT = ROOT / "Itera/Resources/Audio/NarrationID"
NORMALIZER = ROOT / "Tools/normalize_narration.swift"
# Kept outside the app's sources so it is never bundled.
MANIFEST = ROOT / "Tools/narration-manifest.json"
API = "https://api.elevenlabs.io"

# Finger exercises: FingerSessionViewModel.narrate() speaks these keys in order.
FINGER_PREFIXES = ("baseline.", "move.", "demo.", "return.", "finger.", "recovery.")
FINGER_KEYS = (
    "session.ready", "session.good", "session.restInstruction", "session.complete",
    "reflection.title",
    # Forearm rotation calibrates a comfortable range first (FingerActivity.calibratesRange).
    "range.ready", "range.instruction", "range.resultSpoken",
)
# Format keys with the values the app passes; FingerActivity holds for 2 seconds.
FORMAT_KEYS = {
    "guide.holdDuration %lld": (2,),
    # The long rest between plan exercises counts six breaths down to two (DailyPlanNextView).
    "rest.long.remaining %lld": (2, 3, 4, 5, 6),
}

# Format keys whose number is read as an Indonesian word rather than a digit.
SPELLED_FORMAT_KEYS = {"rest.long.remaining %lld"}

# Arm, reaching, cup and balance sessions: keys spoken through SessionAudioService.
BODY_KEYS = (
    "balance.voice.complete", "balance.voice.leftTarget", "balance.voice.returnAndSwitch",
    "balance.voice.returnSameSide", "balance.voice.rightTarget",
    "cup.cupReturn", "cup.handReturn", "cup.nearFace", "cup.start", "cup.transfer",
    "parity.audioUnavailable", "parity.closingComplete", "parity.closingPartial",
    "parity.cupOpening", "parity.getReady", "parity.moveComfortably", "parity.reachOpening",
    "session.cameraWait", "session.countdown", "session.farther", "session.holdStart",
    "session.holdTarget", "session.moveTarget", "session.reachStart", "session.rest",
    "session.returnStart", "session.timedPractice",
    "session.reachRight", "session.reachLeft", "session.reachUp",
    # Activity instructions announced by SessionEngine (CupActivity, DirectionalReachActivity,
    # FoldTowelActivity, SitToStandActivity) and its stage cards.
    "cup.ambiguous", "cup.evidenceMissing", "cup.trackingLost",
    "session.assistance.cup", "session.assistance.sitToStand", "session.feedback", "session.skipped",
    "session.reachAcross", "session.reachLeftFar", "session.reachRightFar", "session.reachUpFar",
    "session.reachTrackingLost",
    "sts.holdSeated", "sts.holdStanding", "sts.leanFirst", "sts.leanForward", "sts.sitDown",
    "sts.slowDown", "sts.standUp", "sts.trackingLost", "sts.trial",
    "towel.approach", "towel.fold", "towel.recover", "towel.release", "towel.trackingLost",
    # Sit-to-stand in BalanceSessionViewModel speaks the engine's instruction key.
    "sitToStand.tracking",
    # Rotation exercises narrate each calibration step (speakCalibrationGuidanceIfNeeded).
    "rotation.calibration.startHint", "rotation.calibration.endHint",
    "internalRotation.calibration.endHint",
    # Calibration pages announced by SessionEngine and BalanceSessionViewModel's opening cues.
    "calibration.intro", "calibration.try", "calibration.complete", "calibration.countdown",
    # Breathing guidance spoken during Balancing rests (SessionDurationClock breath phases).
    "rest.breath.inhale", "rest.breath.exhale",
    # The fold-towel demonstration card (SessionGuidance).
    "towel.demo",
    # Balancing speaks the engine's reach instruction when its practice countdown ends.
    "balance.reachRight", "balance.reachLeft",
    "rotation.rotateRight", "rotation.rotateLeft",
    "internalRotation.rotateRight", "internalRotation.rotateLeft",
    "shoulderFlexion.rotateRight", "shoulderFlexion.rotateLeft",
    # The long breathing rest between daily-plan exercises (DailyPlanNextView).
    "rest.long.opening", "rest.long.restInvitation", "rest.long.instructions", "rest.long.posture",
    "rest.long.inhaleFirst", "rest.long.inhale", "rest.long.inhaleLast", "rest.long.hold",
    "rest.long.exhaleSlow", "rest.long.exhaleShoulders", "rest.long.exhale", "rest.long.exhaleLast",
    "rest.long.settle", "rest.long.closing", "rest.long.nextExercise",
    # The rest then names the next exercise (DailyPlanViewModel.nextSessionTitleKey).
    "exercise.fullFist", "exercise.hookFist", "exercise.opposition", "exercise.spreading",
    "exercise.extensionSequence", "exercise.forearmRotation",
    "session.armRaise", "session.elbowBend", "session.directionalReach", "session.foldTowel",
    "balance.title", "rotation.title", "internalRotation.title", "shoulderFlexion.title",
    "sitToStand.title",
) + tuple(
    f"session.opening.{kind}.{side}.{part}"
    for kind in ("armRaise", "elbowBend")
    for side in ("left", "right")
    for part in ("positioning", "ready")
) + tuple(
    # BalanceExercise.key("voice.*") for the exercises added after Balancing. Keys an exercise
    # shares with another prefix are absent from the catalog and skipped by collect_lines.
    f"{prefix}.voice.{name}"
    for prefix in ("rotation", "shoulderFlexion", "internalRotation", "sitToStand")
    for name in ("complete", "leftTarget", "rightTarget", "returnAndSwitch", "returnSameSide")
)

# The app speaks `speak.<key>` when the catalog has one (shorter than the displayed text), so the
# recording is rendered from it. Rendering a spoken variant for a key that already has a recording
# replaces that recording on the next run, because the text fingerprint changes.
SPOKEN_PREFIX = "speak."
# Spoken numbers for countdowns and repetition counts, one clip each ("narration-id-count-3").
NUMBER_RANGE = range(1, 101)
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

# Takes that came out rushed with the shared seed (well above the ~10 characters per second of
# the other lines) are re-rendered with their own seed; voice settings stay the same. Add a line
# here, or change its seed, to retake just that line on the next run.
RETAKE_SEEDS = {
    "narration-id-recovery.oneHand": 7102,
    "narration-id-recovery.calibration": 7103,
    "narration-id-towel.fold": 7104,
    "narration-id-session.complete": 7105,
    "narration-id-balance.voice.leftTarget": 7106,
    "narration-id-cup.transfer": 7107,
}


def seed_for(line):
    return RETAKE_SEEDS.get(line["name"], SEED)


# Short commands the model reads in a rush even with another seed (about 13-15 characters per
# second against ~10 for the rest) get a slower speed, so their pace matches the other lines.
# Only `speed` changes; stability, style and the lead-in stay the same, so the voice does not.
# The API accepts speeds from 0.7.
SLOW_LINES = {
    # Close to the normal speed so it keeps the movement-instruction voice; a comma in its
    # speak.* text supplies the rest of the slowing (see LEAD_INS).
    "narration-id-recovery.position": 0.84,
    "narration-id-recovery.oneHand": 0.72,
    "narration-id-recovery.calibration": 0.70,
    "narration-id-towel.fold": 0.70,
    "narration-id-session.complete": 0.76,
    "narration-id-balance.voice.leftTarget": 0.78,
    "narration-id-cup.transfer": 0.72,
    # Long-rest lines measured at 13.1 and 12.5 characters per second at the normal speed.
    "narration-id-rest.long.opening": 0.74,
    "narration-id-rest.long.instructions": 0.76,
}


def settings_for(line):
    settings = dict(VOICE_SETTINGS)
    if line["name"] in SLOW_LINES:
        settings["speed"] = SLOW_LINES[line["name"]]
    return settings


TONE_LEAD_IN = "Dengan suara yang lembut, tenang, dan sabar, ia menjelaskan pelan-pelan:"

# Lines that should sound exactly like a particular instruction are rendered as its next
# sentence: that instruction is added to the unspoken lead-in, so the model carries on in the
# same tone. "Posisikan tangan…" follows "Gunakan tangan kanan." as in a live finger session.
LEAD_INS = {
    "narration-id-recovery.position": TONE_LEAD_IN + " Gunakan tangan kanan.",
}


def lead_in_for(line):
    return LEAD_INS.get(line["name"], TONE_LEAD_IN)


def clip_name(key, argument=None):
    """Must match NarrationClips.resourceName(for:) in the app."""
    name = key.replace(" %lld", "")
    if argument is not None:
        name += f"-{argument}"
    return "narration-id-" + re.sub(r"[^A-Za-z0-9._-]", "_", name)


def indonesian_text(entry):
    unit = entry.get("localizations", {}).get("id", {}).get("stringUnit")
    return unit.get("value") if unit else None


def collect_lines(groups):
    strings = json.loads(CATALOG.read_text(encoding="utf-8"))["strings"]
    wanted = []

    for key, entry in strings.items():
        if "finger" in groups and (key.startswith(FINGER_PREFIXES) or key in FINGER_KEYS):
            wanted.append((key, None))
        elif "body" in groups and key in BODY_KEYS:
            wanted.append((key, None))

    if "finger" in groups:
        for key, values in FORMAT_KEYS.items():
            wanted.extend((key, value) for value in values)

    numbers = []
    if "numbers" in groups:
        for n in NUMBER_RANGE:
            # A full stop gives each number a clean, final ending.
            text = indonesian_number(n).capitalize() + "."
            numbers.append({"key": "count", "argument": n, "text": text, "name": clip_name("count", n)})

    lines = []
    for key, argument in wanted:
        text = indonesian_text(strings.get(SPOKEN_PREFIX + key, {})) or indonesian_text(strings.get(key, {}))
        if not text:
            print(f"skip {key}: no Indonesian text", file=sys.stderr)
            continue
        if argument is not None:
            # Counts the patient hears are spelled out ("enam napas lagi"), as the number clips are.
            spoken = indonesian_number(argument) if key in SPELLED_FORMAT_KEYS else str(argument)
            text = text.replace("%lld", spoken)
        lines.append({"key": key, "argument": argument, "text": text, "name": clip_name(key, argument)})

    return sorted(lines + numbers, key=lambda line: line["name"])


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


def fingerprint(line, voice_id, model):
    payload = json.dumps([line["text"], voice_id, model, settings_for(line), seed_for(line), lead_in_for(line)], sort_keys=True)
    return hashlib.sha256(payload.encode()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--voice-name", default="Marizka")
    parser.add_argument("--voice-id", help="Use this voice ID instead of searching by name.")
    parser.add_argument("--model", default="eleven_multilingual_v2")
    parser.add_argument("--groups", default="finger,body,numbers", help="Comma-separated: finger, body, numbers.")
    parser.add_argument("--dry-run", action="store_true", help="List sentences and characters only.")
    parser.add_argument("--force", action="store_true", help="Re-render every sentence.")
    parser.add_argument("--normalize-only", action="store_true", help="Re-level existing raw clips; no API calls.")
    args = parser.parse_args()

    lines = collect_lines(set(args.groups.split(",")))
    characters = sum(len(line["text"]) for line in lines)

    if args.normalize_only:
        normalize()
        return

    if args.dry_run:
        for line in lines:
            print(f'{line["name"]}: {line["text"]}')
        print(f"\n{len(lines)} sentences, {characters} characters in total.")
        return

    api_key = os.environ.get("ELEVENLABS_API_KEY")
    if not api_key:
        sys.exit("Set ELEVENLABS_API_KEY in this terminal first (it is never stored).")

    voice_id, voice_name = (args.voice_id, args.voice_id) if args.voice_id else find_voice(api_key, args.voice_name)
    print(f"Voice: {voice_name} ({voice_id}), model {args.model}")

    RAW.mkdir(parents=True, exist_ok=True)
    manifest = json.loads(MANIFEST.read_text()) if MANIFEST.exists() else {}
    rendered = 0

    for line in lines:
        target = RAW / (line["name"] + ".mp3")
        stamp = fingerprint(line, voice_id, args.model)
        if not args.force and target.exists() and manifest.get(line["name"]) == stamp:
            continue

        print(f'render {line["name"]}: {line["text"]}')
        audio = request(
            "POST", f"/v1/text-to-speech/{voice_id}", api_key,
            query={"output_format": "mp3_44100_128"},
            body={
                "text": line["text"],
                "model_id": args.model,
                "voice_settings": settings_for(line),
                "seed": seed_for(line),
                "previous_text": lead_in_for(line),
            },
            accept="audio/mpeg",
        )
        target.write_bytes(audio)
        manifest[line["name"]] = stamp
        MANIFEST.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
        rendered += 1

    print(f"\nRendered {rendered} of {len(lines)} sentences into {RAW.relative_to(ROOT)}.")
    normalize()
    print("Next: run `xcodegen generate` so the new clips are bundled.")


def normalize():
    """Levels every raw clip into the app's narration folder (fast, no credits used)."""
    print("Levelling loudness...", flush=True)
    result = subprocess.run(["swift", str(NORMALIZER), str(RAW), str(OUTPUT)])
    if result.returncode != 0:
        sys.exit("Normalizing failed; the raw MP3s are kept in Tools/NarrationRaw.")


if __name__ == "__main__":
    main()
