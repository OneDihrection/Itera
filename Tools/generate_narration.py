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
    # Range measurement before forearm rotation (FingerSessionViewModel.instructionKey).
    "range.ready", "range.instruction", "range.resultSpoken",
)
# Format keys with the values the app passes; FingerActivity holds for 2 seconds.
FORMAT_KEYS = {"guide.holdDuration %lld": (2,)}

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
)

# Calm, clear delivery for older patients. `speed` below 1 slows speech slightly.
VOICE_SETTINGS = {
    "stability": 0.55,
    "similarity_boost": 0.8,
    "style": 0.15,
    "use_speaker_boost": True,
    "speed": 0.9,
}


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

    lines = []
    for key, argument in wanted:
        text = indonesian_text(strings.get(key, {}))
        if not text:
            print(f"skip {key}: no Indonesian text", file=sys.stderr)
            continue
        if argument is not None:
            text = text.replace("%lld", str(argument))
        lines.append({"key": key, "argument": argument, "text": text, "name": clip_name(key, argument)})

    return sorted(lines, key=lambda line: line["name"])


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
    payload = json.dumps([line["text"], voice_id, model, VOICE_SETTINGS], sort_keys=True)
    return hashlib.sha256(payload.encode()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--voice-name", default="Marizka")
    parser.add_argument("--voice-id", help="Use this voice ID instead of searching by name.")
    parser.add_argument("--model", default="eleven_multilingual_v2")
    parser.add_argument("--groups", default="finger,body", help="Comma-separated: finger, body.")
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
            body={"text": line["text"], "model_id": args.model, "voice_settings": VOICE_SETTINGS},
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
