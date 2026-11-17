# generate_feedback_sounds.py
# Created by Amelia Putri Aftiana on 29/10/2026.
# Original, quiet nonverbal cues. No downloaded or licensed recordings.
import math
import struct
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / 'Tuntun/Resources/Audio'
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


def render_pop(name, start_frequency=1100, end_frequency=380, duration=0.09):
    """A soft bubble pop: a sine whose pitch falls fast, with a quick click at its start.

    The pitch glides exponentially from `start_frequency` to `end_frequency` while the level
    decays, so it reads as a pop rather than a beep. The click is seeded noise, so every run
    renders the same file.
    """
    import random

    noise = random.Random(20261117)
    frames = []
    phase = 0.0
    total = int(RATE * (duration + 0.02))
    for sample in range(total):
        time = sample / RATE
        if time < duration:
            fraction = time / duration
            frequency = start_frequency * (end_frequency / start_frequency) ** fraction
            phase += math.tau * frequency / RATE
            envelope = min(1, time / 0.003) * (1 - fraction) ** 3
            value = 0.30 * math.sin(phase) * envelope
        else:
            value = 0
        if time < 0.006:
            value += 0.08 * (noise.random() * 2 - 1) * (1 - time / 0.006)
        frames.append(struct.pack('<h', int(max(-1, min(1, value)) * 32767)))
    with wave.open(str(ROOT / (name + '.wav')), 'wb') as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(b''.join(frames))


render_pop('hold-pop')
