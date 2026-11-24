#!/usr/bin/env python3
# generate_directional_reach_left_narration.py
# Created by Amelia Putri Aftiana on 24/11/2026.
"""Generate the Jangkauan Terarah Kiri script (2026-11-24) with the existing Marizka renderer.

    python3 Tools/generate_directional_reach_left_narration.py --dry-run
    python3 Tools/generate_directional_reach_left_narration.py --only 'narration-id-*'

Set ELEVENLABS_API_KEY in the terminal (or the ignored .env) first. --dry-run makes no API calls.
The keys are the `directional-reach-left` lines of Tools/narration-registry.json and their words come from the
String Catalog, so this is the same as `generate_narration.py --groups directional-reach-left`: raw takes stay
in Tools/NarrationRaw/DirectionalReachLeft with their cache in Tools/directional-reach-left-narration-manifest.json.
Lines this script shares with other scripts are already recorded clips (see
Documentation/LeftScriptsNarration.md). Counts and hold seconds are Marizka numbers from
Tools/generate_marizka_counts.py.
"""

import sys

import generate_narration as narrator


def main():
    if not any(arg == "--groups" or arg.startswith("--groups=") for arg in sys.argv[1:]):
        sys.argv.extend(["--groups", "directional-reach-left"])
    narrator.main()


if __name__ == "__main__":
    main()
