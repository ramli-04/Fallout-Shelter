"""Generate original temporary warning tones; normalize optional local SAPI speech.
Run: .venv/Scripts/python.exe tools/generate_warning_audio.py
The four temporary_* files are overwritten. Licensed replacement files are untouched.
"""
from pathlib import Path
import math
import random
import struct
import wave

FOLDER = Path(__file__).resolve().parents[1] / "assets/audio/warnings"
RATE = 22050

def generate(name, duration):
    values = []
    phase = noise = 0.0
    rng = random.Random(97)
    for index in range(int(RATE * duration)):
        time = index / RATE
        if "explosion" in name:
            noise = noise * .96 + rng.uniform(-1, 1) * .04
            sample = (noise * 1.4 + math.sin(math.tau * 48 * time) * .16) * math.exp(-time) * min(1, time * 70)
        else:
            final = "final" in name
            frequency = 360 + 310 * (.5 - .5 * math.cos(math.tau * time / (1.5 if final else 12)))
            phase += math.tau * frequency / RATE
            envelope = .5 + .5 * math.sin(math.tau * time / .6) if final else 1
            sample = (.20 * math.sin(phase) + .045 * math.sin(phase * 2) + .025 * math.sin(phase * 3)) * envelope * min(1, time * 3) * min(1, (duration - time) * 3)
        values.append(int(max(-.35, min(.35, sample)) * 32767))
    with wave.open(str(FOLDER / (name + ".wav")), "wb") as output:
        output.setparams((1, 2, RATE, len(values), "NONE", "not compressed"))
        output.writeframes(struct.pack("<" + "h" * len(values), *values))

def normalize_speech():
    path = FOLDER / "temporary_emergency_broadcast.wav"
    if not path.exists():
        print("No local speech file; run tools/generate_warning_voice.ps1 on Windows.")
        return
    with wave.open(str(path), "rb") as source:
        params = source.getparams()
        if params.sampwidth != 2:
            raise ValueError("Speech must be 16-bit PCM WAV")
        raw = source.readframes(params.nframes)
    values = list(struct.unpack("<" + "h" * (len(raw) // 2), raw))
    peak = max((abs(value) for value in values), default=1) or 1
    values = [int(math.tanh(value / peak * 1.2) * .30 * 32767) for value in values]
    with wave.open(str(path), "wb") as output:
        output.setparams(params)
        output.writeframes(struct.pack("<" + "h" * len(values), *values))

if __name__ == "__main__":
    FOLDER.mkdir(parents=True, exist_ok=True)
    for name, duration in [("temporary_civil_defense_wail", 24), ("temporary_final_warning", 8), ("temporary_explosion", 4)]:
        generate(name, duration)
    normalize_speech()
