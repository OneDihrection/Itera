#!/usr/bin/env python3
# generate_opposition_left_narration.py
# Created by Amelia Putri Aftiana on 14/11/2026.
"""Generate the approved left thumb-opposition narration with the existing Marizka renderer.

Run from /Users/ameliaaftiana/Developer/Itera:
    python3 Tools/generate_opposition_left_narration.py --dry-run
    python3 Tools/generate_opposition_left_narration.py

Uses ELEVENLABS_API_KEY from the environment. No API call is made by --dry-run.
The accompanying JSON contains the approved text, independent of this checkout's
older app catalog. This does not change the app's exercise routing or branch.
"""

import json
import sys
from pathlib import Path

import generate_narration as narrator

TOOLS = Path(__file__).resolve().parent
SCRIPT_TEXT = TOOLS / "opposition-left-narration.json"


def collect_approved_lines(groups):
    if groups != {"opposition-left"}:
        sys.exit("This generator only supports --groups opposition-left.")

    lines = json.loads(SCRIPT_TEXT.read_text(encoding="utf-8"))["lines"]
    if not lines:
        sys.exit(f"No narration text found in {SCRIPT_TEXT}.")

    names = set()
    for line in lines:
        expected = narrator.clip_name(line["key"], line.get("argument"))
        if line["name"] != expected or expected in names or not line["text"].strip():
            sys.exit(f"Invalid or duplicate narration entry: {line['key']}")
        names.add(expected)

    return lines


def main():
    # Keep these raw files and their generation cache separate from the older renderer.
    # The normalizer consequently touches only these clips, preserving other recordings.
    narrator.RAW = TOOLS / "NarrationRaw" / "OppositionLeft"
    narrator.MANIFEST = TOOLS / "opposition-left-narration-manifest.json"
    narrator.VOICE_SETTINGS = {
        "stability": 0.70,
        "similarity_boost": 0.8,
        "style": 0.0,
        "use_speaker_boost": True,
        "speed": 0.88,
    }
    narrator.SEED = 20261110
    narrator.collect_lines = collect_approved_lines

    if not any(arg == "--groups" or arg.startswith("--groups=") for arg in sys.argv[1:]):
        sys.argv.extend(["--groups", "opposition-left"])
    narrator.main()


if __name__ == "__main__":
    main()
