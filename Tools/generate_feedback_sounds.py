# generate_feedback_sounds.py
# Created by Amelia Putri Aftiana on 29/10/2026.
# Original, quiet nonverbal cues. No downloaded or licensed recordings.
import math
import struct
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / 'Itera/Resources/Audio'
ROOT.mkdir(parents=True, exist_ok=True)
RATE = 22050

def render(name, notes, duration):
    frames = []
    for sample in range(int(RATE * duration)):
        time = sample / RATE
        value = 0
        for start, frequency, length in notes:
            local = time - start
            if 0 <= local < length:
                envelope = min(1, local / 0.015) * (1 - local / length) ** 2
                value += 0.22 * math.sin(math.tau * frequency * local) * envelope
        frames.append(struct.pack('<h', int(max(-1, min(1, value)) * 32767)))
    with wave.open(str(ROOT / (name + '.wav')), 'wb') as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(b''.join(frames))

render('countdown', [(0, 660, 0.14)], 0.16)
render('set-complete', [(0, 523.25, 0.35), (0.15, 659.25, 0.35), (0.30, 783.99, 0.60)], 0.95)

render('button-click', [(0, 920, 0.045), (0, 1380, 0.025)], 0.06)

# Bamboo chimes for sequential finger extension (added 04/11/2026).
# One tube per finger, index to little, on a major pentatonic (G5 A5 C6 D6).
# A soft third partial gives a hollow bamboo colour; the little-finger tube
# resolves back to G so a full sequence ends like a short tune.
def render_bamboo(name, notes, duration):
    frames = []
    for sample in range(int(RATE * duration)):
        time = sample / RATE
        value = 0
        for start, frequency, length in notes:
            local = time - start
            if 0 <= local < length:
                envelope = min(1, local / 0.004) * math.exp(-local * 6.5)
                tone = math.sin(math.tau * frequency * local) + 0.28 * math.sin(math.tau * frequency * 2.76 * local) * math.exp(-local * 14)
                value += 0.2 * tone * envelope
        frames.append(struct.pack('<h', int(max(-1, min(1, value)) * 32767)))
    with wave.open(str(ROOT / (name + '.wav')), 'wb') as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(b''.join(frames))

render_bamboo('bamboo-chime-1', [(0, 783.99, 0.9)], 0.9)
render_bamboo('bamboo-chime-2', [(0, 880.00, 0.9)], 0.9)
render_bamboo('bamboo-chime-3', [(0, 1046.50, 0.9)], 0.9)
render_bamboo('bamboo-chime-4', [(0, 1174.66, 0.7), (0.28, 783.99, 1.0)], 1.3)
