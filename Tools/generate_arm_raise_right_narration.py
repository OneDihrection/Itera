#!/usr/bin/env python3
# generate_arm_raise_right_narration.py
# Created by Amelia Putri Aftiana on 14/11/2026.
"""Generate the approved Angkat Lengan Kanan script with the existing Marizka renderer.

    python3 Tools/generate_arm_raise_right_narration.py --dry-run
    python3 Tools/generate_arm_raise_right_narration.py

Set ELEVENLABS_API_KEY in the terminal first. --dry-run makes no API calls.
The String Catalog is the single source for both playback keys and spoken text.
"""

import json
import sys
from pathlib import Path

import generate_narration as narrator

TOOLS = Path(__file__).resolve().parent
PREFIX = "armRaise.right."


def collect_approved_lines(groups):
    if groups != {"arm-raise-right"}:
        sys.exit("This generator only supports --groups arm-raise-right.")

    strings = json.loads(narrator.CATALOG.read_text(encoding="utf-8"))["strings"]
    lines = []
    for key, entry in strings.items():
        if not key.startswith(PREFIX) or key in {PREFIX + "title", PREFIX + "calibration.title"}:
            continue
        text = narrator.indonesian_text(strings.get("speak." + key, {})) or narrator.indonesian_text(entry)
        if not text:
            sys.exit(f"Missing Indonesian narration: {key}")
        # The brief omits the first spoken "six breaths left" announcement.
        arguments = range(1, 6) if key.endswith(" %lld") else (None,)
        for argument in arguments:
            spoken = text if argument is None else text.replace("%lld", narrator.indonesian_number(argument))
            lines.append({
                "key": key,
                "argument": argument,
                "text": spoken,
                "name": narrator.clip_name(key, argument),
            })

    for number in range(1, 7):
        lines.append({
            "key": "count",
            "argument": number,
            "text": narrator.indonesian_number(number).capitalize() + ".",
            "name": narrator.clip_name("count", number),
        })

    if len(lines) <= 6:
        sys.exit(f"No armRaise.left narration found in {narrator.CATALOG}.")
    if len({line["name"] for line in lines}) != len(lines):
        sys.exit("Duplicate narration filenames; generation stopped.")
    return sorted(lines, key=lambda line: line["name"])


def main():
    narrator.RAW = TOOLS / "NarrationRaw" / "ArmRaiseRight"
    narrator.MANIFEST = TOOLS / "arm-raise-right-narration-manifest.json"
    narrator.VOICE_SETTINGS = {
        "stability": 0.70,
        "similarity_boost": 0.8,
        "style": 0.0,
        "use_speaker_boost": True,
        "speed": 0.88,
    }
    narrator.SEED = 20261110
    narrator.collect_lines = collect_approved_lines
    narrator.SUPPORTED_GROUPS.add("arm-raise-right")
    if not any(arg == "--groups" or arg.startswith("--groups=") for arg in sys.argv[1:]):
        sys.argv.extend(["--groups", "arm-raise-right"])
    narrator.main()


if __name__ == "__main__":
    main()
