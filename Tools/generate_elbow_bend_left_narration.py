#!/usr/bin/env python3
# generate_elbow_bend_left_narration.py
# Created by Amelia Putri Aftiana on 24/11/2026.
"""Generate the Tekuk Siku Kiri script (2026-11-24) with the existing Marizka renderer.

    python3 Tools/generate_elbow_bend_left_narration.py --dry-run
    python3 Tools/generate_elbow_bend_left_narration.py --only 'narration-id-*'

Set ELEVENLABS_API_KEY in the terminal (or the ignored .env) first. --dry-run makes no API calls.
The keys are the `elbow-bend-left` lines of Tools/narration-registry.json and their words come from the
String Catalog, so this is the same as `generate_narration.py --groups elbow-bend-left`: raw takes stay
in Tools/NarrationRaw/ElbowBendLeft with their cache in Tools/elbow-bend-left-narration-manifest.json.
Lines this script shares with other scripts are already recorded clips (see
Documentation/LeftScriptsNarration.md). Counts and hold seconds are Marizka numbers from
Tools/generate_marizka_counts.py.
"""

import sys

import generate_narration as narrator


def main():
    if not any(arg == "--groups" or arg.startswith("--groups=") for arg in sys.argv[1:]):
        sys.argv.extend(["--groups", "elbow-bend-left"])
    narrator.main()


if __name__ == "__main__":
    main()
