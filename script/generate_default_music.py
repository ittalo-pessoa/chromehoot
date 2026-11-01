"""Original ChromeHoot quiz loop. Standard-library synthesis, no samples or downloads."""
import math
import struct
import wave
from pathlib import Path

RATE = 16000
DURATION = 16
samples = [0.0] * (RATE * DURATION)

def note(midi, start, duration, gain, bass=False):
    frequency = 440 * 2 ** ((midi - 69) / 12)
    first = int(start * RATE)
    length = int(duration * RATE)
    for offset in range(length):
        if first + offset >= len(samples):
            break
        t = offset / RATE
        attack = min(1, t / 0.012)
        release = min(1, (duration - t) / 0.045)
        envelope = attack * release * math.exp(-t * (3 if bass else 9))
        tone = math.sin(2 * math.pi * frequency * t)
        tone += (0.18 if bass else 0.26) * math.sin(4 * math.pi * frequency * t)
        samples[first + offset] += tone * envelope * gain

# A newly composed eight-bar melody with a soft bass and offbeat bell accents.
melody = [
    76, 0, 79, 74, 0, 72, 76, 0,
    74, 77, 0, 81, 77, 0, 76, 72,
    72, 0, 76, 79, 0, 77, 74, 0,
    71, 74, 0, 79, 76, 0, 74, 0,
    76, 79, 0, 83, 0, 79, 77, 76,
    81, 0, 77, 74, 0, 76, 72, 0,
    77, 0, 81, 79, 0, 76, 74, 72,
    74, 0, 71, 74, 79, 0, 72, 0,
]
roots = [48, 45, 53, 55, 48, 45, 53, 55]
for i, pitch in enumerate(melody):
    if pitch:
        note(pitch, i * .25, .23, .17)
for bar, root in enumerate(roots):
    for beat in range(4):
        note(root + (7 if beat % 2 else 0), bar * 2 + beat * .5, .38, .22, bass=True)
        if beat % 2:
            note(root + 24, bar * 2 + beat * .5 + .25, .13, .06)

peak = max(abs(value) for value in samples)
path = Path(__file__).resolve().parents[1] / 'app/assets/audio/chromehoot-playful.wav'
with wave.open(str(path), 'wb') as output:
    output.setnchannels(1)
    output.setsampwidth(2)
    output.setframerate(RATE)
    output.writeframes(b''.join(struct.pack('<h', int(value / peak * 15000)) for value in samples))
print(f'Original quiz loop: {path.name} ({DURATION}s)')
