# generate_kampung_art.py
# Created by Amelia Putri Aftiana on 04/11/2026.
#
# Original flat artwork for the Indonesian "kampung" exercise games.
# One shared style: flat fills, no outlines, one darker shade on the lower-right,
# one soft white highlight on the upper-left, warm village palette.
# Writes SVG image sets into Itera/Assets.xcassets (vector representation preserved).
# No downloaded or licensed artwork is used.
import json
import math
import sys
from pathlib import Path

ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / 'Itera/Assets.xcassets'

# MARK: - Shared palette

LEAF = '#4E9A5B'
LEAF_SHADE = '#3A7A46'
STEM = '#7A5230'
WOOD = '#8A5A36'
WOOD_SHADE = '#6E4529'
ROPE = '#C9A46B'
HIGHLIGHT = 'fill="#FFFFFF" fill-opacity="0.35"'


def svg(body, width=128, height=128):
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" '
        f'width="{width}" height="{height}">\n{body}\n</svg>\n'
    )


def highlight(cx, cy, rx, ry, angle=-35):
    return f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" transform="rotate({angle} {cx} {cy})" {HIGHLIGHT}/>'


def crescent(cx, cy, r, dx, dy, color):
    """Lower-right shade of a circle: the part not covered by the same circle moved up-left."""
    ox, oy = cx - dx, cy - dy
    d = math.hypot(dx, dy)
    a = d / 2
    h = math.sqrt(r * r - a * a)
    mx, my = (cx + ox) / 2, (cy + oy) / 2
    ux, uy = (ox - cx) / d, (oy - cy) / d
    p1 = (mx + h * -uy, my + h * ux)
    p2 = (mx - h * -uy, my - h * ux)
    return (
        f'<path d="M{p1[0]:.2f} {p1[1]:.2f} A{r} {r} 0 0 1 {p2[0]:.2f} {p2[1]:.2f} '
        f'A{r} {r} 0 0 0 {p1[0]:.2f} {p1[1]:.2f} Z" fill="{color}"/>'
    )


def leaf(x, y, length, angle, color=LEAF, shade=LEAF_SHADE):
    half = length / 2
    return (
        f'<g transform="translate({x} {y}) rotate({angle})">'
        f'<path d="M0 0 Q{half} {-length * 0.42} {length} 0 Q{half} {length * 0.42} 0 0 Z" fill="{color}"/>'
        f'<path d="M0 0 Q{half} {length * 0.42} {length} 0 Q{half} {length * 0.16} 0 0 Z" fill="{shade}"/>'
        f'</g>'
    )


def drop(color, shade):
    return svg(
        f'<path d="M64 10 C64 10 26 58 26 82 A38 38 0 0 0 102 82 C102 58 64 10 64 10 Z" fill="{color}"/>'
        f'<path d="M64 10 C64 10 102 58 102 82 A38 38 0 0 1 64 120 Q90 108 90 82 Q90 56 64 10 Z" fill="{shade}"/>'
        f'{highlight(48, 76, 7, 14, 20)}'
    )


# MARK: - Fist: jeruk and juice glass

def jeruk():
    dots = ''.join(
        f'<circle cx="{x}" cy="{y}" r="1.8" fill="#E28A17"/>'
        for x, y in [(52, 62), (76, 58), (88, 80), (60, 92), (40, 78), (72, 100), (94, 64), (46, 100)]
    )
    return svg(
        f'<circle cx="64" cy="72" r="46" fill="#F4A021"/>'
        f'{crescent(64, 72, 46, 12, 12, "#DB851B")}'
        f'{dots}'
        f'{highlight(46, 52, 12, 18)}'
        f'<rect x="61" y="18" width="7" height="14" rx="3" fill="{STEM}"/>'
        f'{leaf(66, 24, 34, -28)}'
    )


GLASS = 'M30 20 L98 20 L88 112 Q87 120 79 120 L49 120 Q41 120 40 112 Z'
LIQUID = 'M36 36 L92 36 L84 110 Q83 114 78 114 L50 114 Q45 114 44 110 Z'


def glass(full):
    liquid = ''
    if full:
        liquid = (
            f'<path d="{LIQUID}" fill="#F7B23B"/>'
            f'<path d="M78 36 L92 36 L84 110 Q83 114 78 114 L70 114 Z" fill="#E59A22"/>'
            f'<ellipse cx="64" cy="36" rx="28" ry="5" fill="#FBCB63"/>'
            f'<circle cx="54" cy="70" r="2.4" fill="#FFFFFF" fill-opacity="0.45"/>'
            f'<circle cx="62" cy="88" r="1.8" fill="#FFFFFF" fill-opacity="0.45"/>'
            f'<circle cx="70" cy="58" r="1.6" fill="#FFFFFF" fill-opacity="0.45"/>'
        )
    return svg(
        f'<path d="{GLASS}" fill="#DCEFF0" fill-opacity="0.55"/>'
        f'{liquid}'
        f'<path d="M86 20 L98 20 L88 112 Q87 120 79 120 L76 120 Q82 116 83 108 Z" fill="#B9D7D9" fill-opacity="0.7"/>'
        f'<path d="M38 28 L44 28 L50 108 L46 108 Z" fill="#FFFFFF" fill-opacity="0.55"/>'
        f'<ellipse cx="64" cy="20" rx="34" ry="5" fill="#FFFFFF" fill-opacity="0.65"/>'
        f'<rect x="42" y="112" width="44" height="8" rx="4" fill="#B9D7D9" fill-opacity="0.8"/>'
    )


# MARK: - Hook fist: sumur, ember, pot and sprout

def sumur():
    bricks = ''
    for row, y in enumerate([74, 88, 102]):
        offset = 0 if row % 2 == 0 else 11
        for column in range(4):
            x = 22 + offset + column * 22
            if x + 18 > 108:
                continue
            color = '#B3A493' if (row + column) % 2 == 0 else '#A69585'
            bricks += f'<rect x="{x}" y="{y}" width="18" height="10" rx="3" fill="{color}"/>'
    return svg(
        # Genteng roof on wooden posts.
        f'<rect x="24" y="22" width="7" height="50" rx="3" fill="{WOOD}"/>'
        f'<rect x="97" y="22" width="7" height="50" rx="3" fill="{WOOD_SHADE}"/>'
        f'<path d="M10 28 L40 6 L88 6 L118 28 Z" fill="#B5532F"/>'
        f'<path d="M64 6 L88 6 L118 28 L64 28 Z" fill="#963F22"/>'
        f'<path d="M24 22 L104 22" stroke="#7A3218" stroke-width="3" stroke-linecap="round" stroke-opacity="0.5"/>'
        f'<rect x="22" y="36" width="84" height="6" rx="3" fill="{WOOD}"/>'
        f'<circle cx="104" cy="39" r="5" fill="{WOOD_SHADE}"/>'
        f'<path d="M64 42 L64 60" stroke="{ROPE}" stroke-width="3" stroke-linecap="round"/>'
        # Stone well body.
        f'<path d="M18 68 L110 68 L110 110 Q110 118 102 118 L26 118 Q18 118 18 110 Z" fill="#C2B4A4"/>'
        f'{bricks}'
        f'<path d="M86 68 L110 68 L110 110 Q110 118 102 118 L86 118 Z" fill="#9C8B7B" fill-opacity="0.55"/>'
        f'<ellipse cx="64" cy="68" rx="48" ry="11" fill="#D6CABC"/>'
        f'<ellipse cx="64" cy="68" rx="38" ry="7" fill="#2F5F6B"/>'
        f'<ellipse cx="56" cy="67" rx="12" ry="2" fill="#FFFFFF" fill-opacity="0.25"/>'
    )


def ember(with_water=True):
    water = '<ellipse cx="64" cy="44" rx="34" ry="8" fill="#5FB3C6"/><ellipse cx="56" cy="43" rx="12" ry="2.2" fill="#FFFFFF" fill-opacity="0.45"/>' if with_water else ''
    return svg(
        f'<path d="M24 44 Q64 -6 104 44" fill="none" stroke="#5A5F63" stroke-width="5" stroke-linecap="round"/>'
        f'<path d="M26 44 L102 44 L92 114 Q91 120 84 120 L44 120 Q37 120 36 114 Z" fill="#A86B3C"/>'
        f'<path d="M80 44 L102 44 L92 114 Q91 120 84 120 L74 120 Z" fill="#8C5530"/>'
        f'<rect x="28" y="62" width="72" height="7" fill="{WOOD_SHADE}"/>'
        f'<rect x="33" y="96" width="62" height="7" fill="{WOOD_SHADE}"/>'
        f'<path d="M40 50 L46 50 L50 110 L45 110 Z" fill="#FFFFFF" fill-opacity="0.25"/>'
        f'<ellipse cx="64" cy="44" rx="38" ry="9" fill="#8C5530"/>'
        f'{water}'
    )


def pot():
    return svg(
        f'<path d="M30 58 L98 58 L88 116 Q87 122 80 122 L48 122 Q41 122 40 116 Z" fill="#C8643B"/>'
        f'<path d="M78 58 L98 58 L88 116 Q87 122 80 122 L70 122 Z" fill="#A54E2D"/>'
        f'<rect x="22" y="46" width="84" height="16" rx="5" fill="#D9774C"/>'
        f'<rect x="80" y="46" width="26" height="16" rx="5" fill="#B85A34"/>'
        f'<ellipse cx="64" cy="47" rx="38" ry="5" fill="#5B3A29"/>'
        f'<path d="M38 66 L44 66 L48 112 L44 112 Z" fill="#FFFFFF" fill-opacity="0.25"/>'
    )


def tunas():
    return svg(
        f'<path d="M64 124 Q62 90 66 58" fill="none" stroke="{LEAF_SHADE}" stroke-width="6" stroke-linecap="round"/>'
        f'{leaf(65, 84, 46, -150)}'
        f'{leaf(65, 70, 50, -30)}'
        f'{leaf(66, 58, 30, -95)}'
    )


# MARK: - Opposition: melati

def melati():
    petals = ''
    for index in range(6):
        angle = index * 60
        color = '#FFFFFF' if index in (0, 1, 5) else '#EEF2E8'
        petals += (
            f'<ellipse cx="64" cy="36" rx="17" ry="27" fill="{color}" '
            f'transform="rotate({angle} 64 64)"/>'
        )
    inner = ''
    for index in range(5):
        angle = index * 72 + 36
        inner += (
            f'<ellipse cx="64" cy="48" rx="9" ry="15" fill="#F7F9F3" '
            f'transform="rotate({angle} 64 64)"/>'
        )
    return svg(
        f'{petals}{inner}'
        f'<path d="M80 92 Q88 78 86 64" fill="none" stroke="#DCE3D3" stroke-width="5" stroke-linecap="round"/>'
        f'<circle cx="64" cy="64" r="9" fill="#F1D27A"/>'
        f'<circle cx="61" cy="61" r="3" fill="#FFFFFF" fill-opacity="0.6"/>'
    )


# MARK: - Spreading: kembang sepatu and kupu-kupu

def sepatu():
    petals = ''
    for index in range(5):
        angle = index * 72 - 90
        color = '#E2483D' if index % 2 == 0 else '#D63E34'
        petals += (
            f'<path d="M64 64 Q34 40 44 18 Q64 4 84 18 Q94 40 64 64 Z" fill="{color}" '
            f'transform="rotate({angle + 90} 64 64)"/>'
        )
    veins = ''.join(
        f'<path d="M64 64 L64 30" stroke="#B9332D" stroke-width="2.5" stroke-linecap="round" '
        f'stroke-opacity="0.55" transform="rotate({index * 72} 64 64)"/>'
        for index in range(5)
    )
    return svg(
        f'{petals}'
        f'{crescent(64, 64, 26, 8, 8, "#B9332D")}'
        f'<circle cx="64" cy="64" r="16" fill="#9E2A25"/>'
        f'{veins}'
        f'{highlight(46, 36, 8, 14)}'
        f'<path d="M64 64 Q84 50 98 28" fill="none" stroke="#F3D7C2" stroke-width="4" stroke-linecap="round"/>'
        f'<circle cx="98" cy="28" r="6" fill="#F6C343"/>'
        f'<circle cx="92" cy="34" r="3" fill="#F6C343"/>'
        f'<circle cx="102" cy="36" r="3" fill="#F6C343"/>'
    )


def sepatu_kuncup():
    return svg(
        f'<path d="M64 124 Q60 104 64 86" fill="none" stroke="{LEAF_SHADE}" stroke-width="6" stroke-linecap="round"/>'
        f'{leaf(63, 108, 34, -160)}'
        f'<path d="M64 20 Q40 50 50 80 L78 80 Q88 50 64 20 Z" fill="#E2483D"/>'
        f'<path d="M64 20 Q80 44 78 80 L66 80 Q74 50 64 20 Z" fill="#B9332D"/>'
        f'{highlight(54, 52, 5, 14, 10)}'
        f'<path d="M44 76 Q64 70 84 76 L78 96 Q64 102 50 96 Z" fill="{LEAF}"/>'
        f'<path d="M64 72 Q76 72 84 76 L78 96 Q72 99 64 100 Z" fill="{LEAF_SHADE}"/>'
    )


def kupu():
    def wing_pair(mirror):
        scale = -1 if mirror else 1
        return (
            f'<g transform="translate(64 0) scale({scale} 1) translate(-64 0)">'
            f'<path d="M62 58 Q30 10 12 34 Q4 58 30 66 Q46 68 62 62 Z" fill="#F29E4C"/>'
            f'<path d="M62 64 Q36 70 26 90 Q30 112 50 100 Q62 88 62 70 Z" fill="#F6C343"/>'
            f'<path d="M12 34 Q4 58 30 66 Q20 56 22 40 Z" fill="#D9792E"/>'
            f'<circle cx="28" cy="40" r="5" fill="#FFF4DA"/>'
            f'<circle cx="40" cy="88" r="4" fill="#FFF4DA"/>'
            f'</g>'
        )
    return svg(
        f'{wing_pair(False)}{wing_pair(True)}'
        f'<ellipse cx="64" cy="66" rx="5" ry="28" fill="#5B3A29"/>'
        f'<circle cx="64" cy="38" r="6" fill="#5B3A29"/>'
        f'<path d="M62 34 Q56 20 50 16 M66 34 Q72 20 78 16" fill="none" stroke="#5B3A29" stroke-width="2.5" stroke-linecap="round"/>'
        f'{highlight(30, 30, 5, 9)}'
    )


# MARK: - Sequential extension: bamboo chimes

def bambu():
    return svg(
        f'<rect x="6" y="10" width="28" height="114" rx="6" fill="#CDB85A"/>'
        f'<rect x="24" y="10" width="10" height="114" rx="5" fill="#AE9A42"/>'
        f'<rect x="4" y="44" width="32" height="6" rx="3" fill="#8E7B33"/>'
        f'<rect x="4" y="90" width="32" height="6" rx="3" fill="#8E7B33"/>'
        f'<path d="M6 16 L34 8 L34 14 L6 22 Z" fill="#6E5E25"/>'
        f'<circle cx="20" cy="26" r="2.5" fill="#6E5E25"/>'
        f'<rect x="10" y="30" width="4" height="58" rx="2" fill="#FFFFFF" fill-opacity="0.35"/>',
        width=40,
    )


def gantungan():
    return svg(
        f'<path d="M80 4 L40 26 M80 4 L120 26" stroke="{ROPE}" stroke-width="3" stroke-linecap="round"/>'
        f'<rect x="8" y="24" width="144" height="12" rx="6" fill="{WOOD}"/>'
        f'<rect x="8" y="31" width="144" height="5" rx="2.5" fill="{WOOD_SHADE}"/>'
        f'<circle cx="80" cy="4" r="3" fill="{ROPE}"/>',
        width=160,
        height=40,
    )


# MARK: - Balancing: mangga and tas anyaman

def mangga():
    body = 'M70 30 Q108 28 112 66 Q114 104 74 116 Q30 124 20 92 Q12 62 40 40 Q54 30 70 30 Z'
    return svg(
        f'<path d="{body}" fill="#F2B536"/>'
        f'<path d="M70 30 Q108 28 112 66 Q100 46 72 44 Q56 42 44 50 Q50 34 70 30 Z" fill="#E9773A"/>'
        f'<path d="M112 66 Q114 104 74 116 Q30 124 20 92 Q50 112 84 100 Q106 90 112 66 Z" fill="#D99A22"/>'
        f'{highlight(44, 66, 8, 18, 30)}'
        f'<path d="M68 32 Q66 20 72 12" fill="none" stroke="{STEM}" stroke-width="5" stroke-linecap="round"/>'
        f'{leaf(72, 16, 40, -10)}'
    )


def tas():
    weave = ''
    for row in range(5):
        for column in range(7):
            x = 26 + column * 11
            y = 66 + row * 10
            color = '#D8AE70' if (row + column) % 2 == 0 else '#B98A4E'
            weave += f'<rect x="{x}" y="{y}" width="9" height="8" rx="2" fill="{color}"/>'
    kawung = ''.join(
        f'<circle cx="{x}" cy="56" r="3.2" fill="#F3E2C4"/>'
        for x in range(32, 104, 12)
    )
    return svg(
        f'<path d="M30 54 Q22 8 64 6 Q106 8 98 54" fill="none" stroke="{STEM}" stroke-width="7" stroke-linecap="round"/>'
        f'<path d="M20 50 L108 50 L102 114 Q101 122 92 122 L36 122 Q27 122 26 114 Z" fill="#C99A5B"/>'
        f'{weave}'
        f'<path d="M84 50 L108 50 L102 114 Q101 122 92 122 L82 122 Z" fill="#8F6534" fill-opacity="0.45"/>'
        f'<rect x="18" y="48" width="92" height="16" rx="5" fill="#9E3B26"/>'
        f'{kawung}'
        f'<rect x="84" y="48" width="26" height="16" rx="5" fill="#7E2C1C" fill-opacity="0.6"/>'
        f'<rect x="28" y="68" width="5" height="44" rx="2.5" fill="#FFFFFF" fill-opacity="0.25"/>'
    )


ASSETS = {
    'kampung-jeruk': jeruk(),
    'kampung-tetes-jus': drop('#F7A928', '#DB851B'),
    'kampung-gelas-kosong': glass(False),
    'kampung-gelas-penuh': glass(True),
    'kampung-sumur': sumur(),
    'kampung-ember': ember(),
    'kampung-tetes-air': drop('#6EC1D6', '#4BA3BB'),
    'kampung-pot': pot(),
    'kampung-tunas': tunas(),
    'kampung-melati': melati(),
    'kampung-sepatu': sepatu(),
    'kampung-sepatu-kuncup': sepatu_kuncup(),
    'kampung-kupu': kupu(),
    'kampung-bambu': bambu(),
    'kampung-gantungan': gantungan(),
    'kampung-mangga': mangga(),
    'kampung-tas': tas(),
}


def main():
    for name, content in ASSETS.items():
        folder = ROOT / f'{name}.imageset'
        folder.mkdir(parents=True, exist_ok=True)
        (folder / f'{name}.svg').write_text(content)
        contents = {
            'images': [{'filename': f'{name}.svg', 'idiom': 'universal'}],
            'info': {'author': 'xcode', 'version': 1},
            'properties': {'preserves-vector-representation': True},
        }
        (folder / 'Contents.json').write_text(json.dumps(contents, indent=2) + '\n')
    print(f'Wrote {len(ASSETS)} image sets to {ROOT}')


if __name__ == '__main__':
    main()
