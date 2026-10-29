#!/usr/bin/env python3
# generate_english_counts.py
# Created by dimaswisodewo on 28/10/2026.
"""English counterpart of VisionPoc/scripts/generate_therapy_counts.py.

Uses the installed Samantha voice; rate, PCM format, trimming threshold, and
padding are identical to the original Indonesian generation process.
"""
import array
from pathlib import Path
import subprocess
import sys
import tempfile
import wave

OUTPUT = Path(__file__).resolve().parents[1] / 'Itera/Resources/Audio/CountsEN'


def english_number(number):
    small = ['zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven',
             'eight', 'nine', 'ten', 'eleven', 'twelve', 'thirteen', 'fourteen',
             'fifteen', 'sixteen', 'seventeen', 'eighteen', 'nineteen']
    if number < 20:
        return small[number]
    if number == 100:
        return 'one hundred'
    tens = ['', '', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy', 'eighty', 'ninety']
    quotient, remainder = divmod(number, 10)
    return tens[quotient] + (' ' + small[remainder] if remainder else '')


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='itera-counts-') as temporary:
        for number in range(1, 101):
            source = Path(temporary) / 'count.wav'
            subprocess.run([
                '/usr/bin/say', '-v', 'Samantha', '-r', '180',
                '--file-format=WAVE', '--data-format=LEI16@22050',
                '-o', str(source), english_number(number),
            ], check=True, timeout=30)
            with wave.open(str(source), 'rb') as audio:
                assert audio.getnchannels() == 1 and audio.getsampwidth() == 2
                rate = audio.getframerate()
                samples = array.array('h', audio.readframes(audio.getnframes()))
            if sys.byteorder != 'little':
                samples.byteswap()
            audible = [index for index, sample in enumerate(samples) if abs(sample) >= 32]
            if not audible:
                raise RuntimeError(f'Count {number} contains no speech')
            padding = int(rate * 0.02)
            trimmed = samples[max(0, audible[0] - padding):audible[-1] + padding + 1]
            if sys.byteorder != 'little':
                trimmed.byteswap()
            with wave.open(str(OUTPUT / f'count-en-{number}.wav'), 'wb') as audio:
                audio.setnchannels(1)
                audio.setsampwidth(2)
                audio.setframerate(rate)
                audio.writeframes(trimmed.tobytes())
    print('Generated 100 English count clips.')


if __name__ == '__main__':
    main()
