#!/usr/bin/env python3
# generate_arm_raise_left_narration.py
# Created by Amelia Putri Aftiana on 14/11/2026.
"""Generate the approved Angkat Lengan Kiri script with the existing Marizka renderer.

    python3 Tools/generate_arm_raise_left_narration.py --dry-run
    python3 Tools/generate_arm_raise_left_narration.py
    python3 Tools/generate_arm_raise_left_narration.py --only 'narration-id-armRaise.left.rest.*'

Set ELEVENLABS_API_KEY in the terminal first. --dry-run makes no API calls.
The keys are the `arm-raise-left` lines of Tools/narration-registry.json and their words come from the
String Catalog, so this is the same as `generate_narration.py --groups arm-raise-left`: raw takes stay
in Tools/NarrationRaw/ArmRaiseLeft with their cache in Tools/arm-raise-left-narration-manifest.json.
Repetition counts are Marizka numbers from Tools/generate_marizka_counts.py.
"""

import sys

import generate_narration as narrator


def main():
    if not any(arg == "--groups" or arg.startswith("--groups=") for arg in sys.argv[1:]):
        sys.argv.extend(["--groups", "arm-raise-left"])
    narrator.main()


if __name__ == "__main__":
    main()
