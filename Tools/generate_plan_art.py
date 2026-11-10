#!/usr/bin/env python3
# generate_plan_art.py
# Created by Amelia Putri Aftiana on 09/11/2026.
"""Draws the Beranda plan illustrations in the style of the existing plan-*.svg figures.

Usage, from the repository root:
    python3 Tools/generate_plan_art.py Itera/Assets.xcassets
    xcodegen generate
Writes one imageset per pose. Shapes and colours copy the existing figures exactly.
"""
import json
import sys
from pathlib import Path

SKIN, HAIR, MOUTH = "#E7B48F", "#3A2A24", "#B5715A"
TOP, SLEEVE = "#F08A3C", "#E2772C"
TROUSERS, SHOE = "#E2B33C", "#7A4A2B"
ACCENT = "#C9BBAA"  # motion arrows, muted so they never compete with the figure


def stroke(d, color, width):
    return (f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{width}" '
            f'stroke-linecap="round" stroke-linejoin="round"/>')


def legs_and_torso():
    return "".join([
        stroke("M52,140 L51,264", TROUSERS, 15),
        stroke("M68,140 L69,264", TROUSERS, 15),
        f'<rect x="43" y="126" width="34" height="24" rx="7" fill="{TROUSERS}"/>',
        f'<ellipse cx="48" cy="271" rx="10" ry="5" fill="{SHOE}"/>',
        f'<ellipse cx="72" cy="271" rx="10" ry="5" fill="{SHOE}"/>',
        f'<rect x="41" y="60" width="38" height="78" rx="13" fill="{TOP}"/>',
    ])


def head():
    return "".join([
        f'<rect x="55" y="50" width="10" height="14" fill="{SKIN}"/>',
        f'<circle cx="60" cy="21" r="8" fill="{HAIR}"/>',
        f'<circle cx="60" cy="40" r="14" fill="{SKIN}"/>',
        f'<path d="M45,44 C43,16 77,16 75,44 C73,36 66,31 60,31 C54,31 47,36 45,44 Z" fill="{HAIR}"/>',
        f'<circle cx="55" cy="42" r="1.6" fill="{HAIR}"/>',
        f'<circle cx="65" cy="42" r="1.6" fill="{HAIR}"/>',
        stroke("M56,48 Q60,51 64,48", MOUTH, 1.4).replace('stroke-linejoin="round"', ""),
    ])


def arm(points, hand=None):
    """A sleeve through the points, with a round hand at `hand` (default: past the last point)."""
    d = "M" + " L".join(f"{x},{y}" for x, y in points)
    parts = [stroke(d, SLEEVE, 11)]
    if hand is not False:
        hx, hy = hand or points[-1]
        parts.append(f'<circle cx="{hx}" cy="{hy}" r="5.5" fill="{SKIN}"/>')
    return "".join(parts)


def resting_left_arm():
    return arm([(46, 68), (41, 102), (41, 128)], (41.0, 133.0))


# Finger poses share one raised right arm, ending in an enlarged palm at (94, 54).
RAISED_RIGHT = [(74, 68), (92, 98), (94, 66)]


def finger(d):
    return stroke(d, SKIN, 4)


def palm(rx=8, ry=8.5, cx=94, cy=54):
    return f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="{SKIN}"/>'


def hand_open_together():
    """Straight fingers held together, the start pose of most finger movements."""
    return "".join([finger("M85,51 L82,45"), finger("M90,47 L89,35"), finger("M94,46 L94,33"),
                    finger("M98,47 L99,35"), finger("M102,49 L103,38"), palm()])


def hand_spread():
    return "".join([finger("M85,51 L79,44"), finger("M89,47 L86,35"), finger("M94,46 L94,32"),
                    finger("M99,47 L102,35"), finger("M102,52 L108,46"), palm()])


def hand_fist():
    return "".join([
        f'<rect x="84" y="42" width="21" height="20" rx="8" fill="{SKIN}"/>',
        stroke("M88,45 L88,51", MOUTH, 1.2), stroke("M93,44 L93,50", MOUTH, 1.2),
        stroke("M98,44 L98,50", MOUTH, 1.2), stroke("M103,45 L103,51", MOUTH, 1.2),
        finger("M85,53 L80,49"),
    ])


def hand_hook():
    """Knuckles straight, middle and end joints bent: fingers curl over at the top."""
    return "".join([finger("M85,51 L81,46"),
                    finger("M90,47 L89,38 L93,40"), finger("M94,46 L94,36 L98,39"),
                    finger("M98,47 L99,38 L102,41"), finger("M102,49 L103,41 L106,44"), palm()])


def hand_opposition():
    """Thumb tip meets the index tip in a small ring; the other fingers stay straight."""
    return "".join([finger("M94,46 L94,33"), finger("M98,47 L99,35"), finger("M102,49 L103,38"),
                    finger("M90,47 L86,39 L83,42"), finger("M85,52 L80,46 L83,42"), palm(),
                    f'<circle cx="83" cy="42" r="2.6" fill="none" stroke="{MOUTH}" stroke-width="1"/>'])


def hand_extension():
    """One finger straightened, the rest gently bent."""
    return "".join([finger("M85,51 L81,46"), finger("M90,47 L89,41 L92,43"),
                    finger("M94,46 L94,30"), finger("M98,47 L99,41 L102,43"),
                    finger("M102,49 L103,44 L105,46"), palm()])


def hand_turning():
    """Palm seen edge-on, with a curved arrow for turning the forearm."""
    return "".join([hand_open_together(), rotation_arrow(94, 54, 17)])


def rotation_arrow(cx, cy, r, clockwise=True):
    sweep = 1 if clockwise else 0
    sx, sy = cx - r, cy + 4
    ex, ey = cx + r, cy + 4
    head_x = ex + (2 if clockwise else -2)
    return "".join([
        f'<path d="M{sx},{sy} A{r},{r * 0.55} 0 0 {sweep} {ex},{ey}" fill="none" stroke="{ACCENT}" '
        f'stroke-width="3" stroke-linecap="round"/>',
        f'<path d="M{ex - 5},{ey - 4} L{head_x},{ey} L{ex - 6},{ey + 4}" fill="none" stroke="{ACCENT}" '
        f'stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>',
    ])


def arrow(x1, y1, x2, y2):
    """A short straight motion arrow."""
    import math
    angle = math.atan2(y2 - y1, x2 - x1)
    left = (x2 - 6 * math.cos(angle - 0.6), y2 - 6 * math.sin(angle - 0.6))
    right = (x2 - 6 * math.cos(angle + 0.6), y2 - 6 * math.sin(angle + 0.6))
    return "".join([
        stroke(f"M{x1},{y1} L{x2},{y2}", ACCENT, 3),
        stroke(f"M{left[0]:.1f},{left[1]:.1f} L{x2},{y2} L{right[0]:.1f},{right[1]:.1f}", ACCENT, 3),
    ])


def finger_pose(hand):
    return legs_and_torso() + resting_left_arm() + arm(RAISED_RIGHT, False) + hand + head()


POSES = {
    "fullFist": finger_pose(hand_fist()),
    "hookFist": finger_pose(hand_hook()),
    "opposition": finger_pose(hand_opposition()),
    "spreading": finger_pose(hand_spread()),
    "extensionSequence": finger_pose(hand_extension()),
    "forearmRotation": finger_pose(hand_turning()),
    # Elbow bent so the hand comes up toward the shoulder.
    "elbowBend": legs_and_torso() + resting_left_arm()
        + arm([(74, 68), (82, 104), (90, 74)], (90.5, 68.5)) + arrow(100, 98, 100, 80) + head(),
    # Arm reaching straight out to the side, with arrows for the directions.
    "directionalReach": legs_and_torso() + resting_left_arm()
        + arm([(74, 68), (93, 70), (110, 71)], (114.5, 71)) + arrow(104, 58, 112, 46)
        + arrow(104, 84, 112, 96) + head(),
    # Elbow at the side, forearm turned in across the belly.
    "internalRotation": legs_and_torso() + resting_left_arm()
        + arm([(74, 68), (80, 104), (56, 108)], (51.5, 108)) + rotation_arrow(66, 118, 14, False) + head(),
    # Arm lifted forward and up, palm up.
    "shoulderFlexion": legs_and_torso() + resting_left_arm()
        + arm([(74, 68), (76, 40), (77, 15)], (77, 9.5)) + arrow(92, 70, 92, 44) + head(),
}

HEADER = """<!-- plan-{name}.svg -->
<!-- Itera -->
<!-- Created by Amelia Putri Aftiana on 9/11/26. -->
"""


def write(assets: Path, name: str, body: str):
    folder = assets / f"plan-{name}.imageset"
    folder.mkdir(exist_ok=True)
    svg = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 300" width="120" height="300">\n'
           + HEADER.format(name=name) + body + "\n</svg>\n")
    (folder / f"plan-{name}.svg").write_text(svg)
    contents = {
        "images": [{"filename": f"plan-{name}.svg", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
        "properties": {"preserves-vector-representation": True},
    }
    (folder / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")


if __name__ == "__main__":
    assets = Path(sys.argv[1])
    for name, body in POSES.items():
        write(assets, name, body)
    print(len(POSES), "imagesets written")
