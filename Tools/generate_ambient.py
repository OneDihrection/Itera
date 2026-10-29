# generate_ambient.py
# Created by Amelia Putri Aftiana on 29/10/2026.
# Original low-amplitude, loopable tonal background; no sampled third-party audio.
from pathlib import Path
import math
import struct
import wave

folder = Path(__file__).resolve().parents[1] / 'Itera/Resources/Audio'
folder.mkdir(parents=True, exist_ok=True)
rate = 22050
duration = 8
with wave.open(str(folder / 'calm.wav'), 'wb') as audio:
    audio.setparams((1, 2, rate, rate * duration, 'NONE', 'not compressed'))
    frames = []
    for sample in range(rate * duration):
        envelope = math.sin(math.pi * sample / (rate * duration)) ** 2
        tone = math.sin(2 * math.pi * 220 * sample / rate)
        overtone = 0.4 * math.sin(2 * math.pi * 330 * sample / rate)
        frames.append(struct.pack('<h', int(1200 * (tone + overtone) * envelope)))
    audio.writeframes(b''.join(frames))
