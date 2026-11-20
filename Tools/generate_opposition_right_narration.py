#!/usr/bin/env python3
# generate_opposition_right_narration.py
# Created by Amelia Putri Aftiana on 14/11/2026.
"""Generate the approved right thumb-opposition narration with the existing Marizka renderer.

    python3 Tools/generate_opposition_right_narration.py --dry-run
    python3 Tools/generate_opposition_right_narration.py
    python3 Tools/generate_opposition_right_narration.py --only 'narration-id-opposition.right.rest.*'

Set ELEVENLABS_API_KEY in the terminal first. --dry-run makes no API calls.
The keys are the `opposition-right` lines of Tools/narration-registry.json and their words come from the
String Catalog, so this is the same as `generate_narration.py --groups opposition-right`: raw takes stay
in Tools/NarrationRaw/OppositionRight with their cache in Tools/opposition-right-narration-manifest.json.
Repetition counts are Marizka numbers from Tools/generate_marizka_counts.py.
"""

import sys

import generate_narration as narrator


def main():
    if not any(arg == "--groups" or arg.startswith("--groups=") for arg in sys.argv[1:]):
        sys.argv.extend(["--groups", "opposition-right"])
    narrator.main()


if __name__ == "__main__":
    main()
