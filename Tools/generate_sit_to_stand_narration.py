#!/usr/bin/env python3
# generate_sit_to_stand_narration.py
# Created by Amelia Putri Aftiana on 23/11/2026.
"""Generate the Berdiri dari Posisi Duduk script (2026-11-23) with the existing Marizka renderer.

    python3 Tools/generate_sit_to_stand_narration.py --dry-run
    python3 Tools/generate_sit_to_stand_narration.py --only 'narration-id-*'

Set ELEVENLABS_API_KEY in the terminal (or the ignored .env) first. --dry-run makes no API calls.
The keys are the `sit-to-stand` lines of Tools/narration-registry.json and their words come from the
String Catalog, so this is the same as `generate_narration.py --groups sit-to-stand`: raw takes stay
in Tools/NarrationRaw/SitToStand with their cache in Tools/sit-to-stand-narration-manifest.json.
Lines this script shares with other scripts are already recorded clips (see
Documentation/LeftScriptsNarration.md). Counts and hold seconds are Marizka numbers from
Tools/generate_marizka_counts.py.
"""

import sys

import generate_narration as narrator


def main():
    if not any(arg == "--groups" or arg.startswith("--groups=") for arg in sys.argv[1:]):
        sys.argv.extend(["--groups", "sit-to-stand"])
    narrator.main()


if __name__ == "__main__":
    main()
