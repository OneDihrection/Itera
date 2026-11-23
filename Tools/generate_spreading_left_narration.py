#!/usr/bin/env python3
# generate_spreading_left_narration.py
# Created by Amelia Putri Aftiana on 23/11/2026.
"""Generate the Renggangkan Jari Kiri script (2026-11-23) with the existing Marizka renderer.

    python3 Tools/generate_spreading_left_narration.py --dry-run
    python3 Tools/generate_spreading_left_narration.py --only 'narration-id-spreading.left.*'

Set ELEVENLABS_API_KEY in the terminal (or the ignored .env) first. --dry-run makes no API calls.
The keys are the `spreading-left` lines of Tools/narration-registry.json and their words come from the
String Catalog, so this is the same as `generate_narration.py --groups spreading-left`: raw takes stay
in Tools/NarrationRaw/SpreadingLeft with their cache in Tools/spreading-left-narration-manifest.json.
Lines this script shares with the other left scripts are the `scripted-common` and
`scripted-left` groups, recorded with `generate_narration.py --groups <group>`.
Repetition counts and hold seconds are Marizka numbers from Tools/generate_marizka_counts.py.
"""

import sys

import generate_narration as narrator


def main():
    if not any(arg == "--groups" or arg.startswith("--groups=") for arg in sys.argv[1:]):
        sys.argv.extend(["--groups", "spreading-left"])
    narrator.main()


if __name__ == "__main__":
    main()
