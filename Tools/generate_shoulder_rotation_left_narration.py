#!/usr/bin/env python3
# generate_shoulder_rotation_left_narration.py
# Created by Amelia Putri Aftiana on 23/11/2026.
"""Generate the Putar Bahu ke Arah Dalam and Luar Kiri script (2026-11-23) with the existing Marizka renderer.

    python3 Tools/generate_shoulder_rotation_left_narration.py --dry-run
    python3 Tools/generate_shoulder_rotation_left_narration.py --only 'narration-id-*'

Set ELEVENLABS_API_KEY in the terminal (or the ignored .env) first. --dry-run makes no API calls.
The keys are the `shoulder-rotation-left` lines of Tools/narration-registry.json and their words come from the
String Catalog, so this is the same as `generate_narration.py --groups shoulder-rotation-left`: raw takes stay
in Tools/NarrationRaw/ShoulderRotationLeft with their cache in Tools/shoulder-rotation-left-narration-manifest.json.
Lines this script shares with other scripts are already recorded clips (see
Documentation/LeftScriptsNarration.md). Counts and hold seconds are Marizka numbers from
Tools/generate_marizka_counts.py.
"""

import sys

import generate_narration as narrator


def main():
    if not any(arg == "--groups" or arg.startswith("--groups=") for arg in sys.argv[1:]):
        sys.argv.extend(["--groups", "shoulder-rotation-left"])
    narrator.main()


if __name__ == "__main__":
    main()
