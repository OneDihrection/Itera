#!/usr/bin/env python3
# generate_arm_raise_right_narration.py
# Created by Amelia Putri Aftiana on 14/11/2026.
"""Generate the approved Angkat Lengan Kanan script with the existing Marizka renderer.

    python3 Tools/generate_arm_raise_right_narration.py --dry-run
    python3 Tools/generate_arm_raise_right_narration.py
    python3 Tools/generate_arm_raise_right_narration.py --only 'narration-id-armRaise.right.rest.*'

Set ELEVENLABS_API_KEY in the terminal first. --dry-run makes no API calls.
The keys are the `arm-raise-right` lines of Tools/narration-registry.json and their words come from the
String Catalog, so this is the same as `generate_narration.py --groups arm-raise-right`: raw takes stay
in Tools/NarrationRaw/ArmRaiseRight with their cache in Tools/arm-raise-right-narration-manifest.json.
Repetition counts are Marizka numbers from Tools/generate_marizka_counts.py.
"""

import sys

import generate_narration as narrator


def main():
    if not any(arg == "--groups" or arg.startswith("--groups=") for arg in sys.argv[1:]):
        sys.argv.extend(["--groups", "arm-raise-right"])
    narrator.main()


if __name__ == "__main__":
    main()
