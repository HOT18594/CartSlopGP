"""Generate seamless, original vehicle loops for Cart Slop GP.

Each engine is an additive harmonic stack with a periodic exhaust "chug" and
optional turbo whine; the shopping cart gets a metallic wheel rattle instead.
All frequencies are whole Hz, so every 2-second file loops without a click.

Run from godot_project/:  python tools/gen_vehicle_loops.py
Output: assets/audio/sfx/engines/*.wav (mono, 44.1 kHz, 16-bit)
"""

from __future__ import annotations

import math
import os
import wave

import numpy as np

SR = 44100
DUR = 2.0
N = int(SR * DUR)
T = np.arange(N) / SR
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "sfx", "engines")


def engine(f0: int, harmonics: int, rolloff: float, chug: float, drive: float,
           whine: float, detune: int, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    signal = np.zeros(N)
    for k in range(1, harmonics + 1):
        phase = float(rng.uniform(0.0, math.tau))
        freq = f0 * k + (detune if k % 2 == 0 else 0)
        signal += (1.0 / (k ** rolloff)) * np.sin(math.tau * freq * T + phase)
    # Sub-octave and exhaust pulse.
    signal += 0.30 * np.sin(math.tau * (f0 / 2) * T)
    pulse = 1.0 - chug * 0.5 * (1.0 - np.cos(math.tau * (f0 / 2) * T))
    signal *= pulse
    signal = np.tanh(drive * signal)
    if whine > 0.0:
        signal += whine * np.sin(math.tau * (f0 * 10) * T) * (0.6 + 0.4 * np.sin(math.tau * 3 * T))
    signal /= max(np.max(np.abs(signal)), 1e-6)
    return signal * 0.82


def cart_rattle() -> np.ndarray:
    rng = np.random.default_rng(45)
    wheel_hz = 7
    # A periodic "noise" bed: many whole-Hz sines with random phases.
    noise = np.zeros(N)
    freq = 180
    while freq < 3800:
        noise += rng.uniform(0.5, 1.0) / math.sqrt(freq / 180.0) * np.sin(
            math.tau * freq * T + rng.uniform(0, math.tau))
        freq += 13
    noise /= max(np.max(np.abs(noise)), 1e-6)

    pulse = 0.35 + 0.65 * (0.5 + 0.5 * np.cos(math.tau * wheel_hz * T))
    squeak_phase = math.tau * 2100.0 * T + 0.06 * np.sin(math.tau * 5 * T)
    squeak = np.sin(squeak_phase) * (0.35 + 0.65 * (0.5 + 0.5 * np.cos(math.tau * wheel_hz * T + 1.1)))
    squeak += 0.35 * np.sin(math.tau * 3170.0 * T + 0.8)
    clank = np.exp(-((T % (1.0 / wheel_hz)) / 0.018)) * np.sin(math.tau * 1650.0 * T)

    signal = 0.42 * noise * pulse + 0.16 * squeak + 0.22 * clank
    signal = np.tanh(1.4 * signal)
    signal /= max(np.max(np.abs(signal)), 1e-6)
    return signal * 0.66


def write_wav(name: str, signal: np.ndarray) -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, name)
    pcm = np.clip(signal, -1.0, 1.0)
    pcm = (pcm * 32767.0).astype("<i2")
    with wave.open(path, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(SR)
        handle.writeframes(pcm.tobytes())
    print(f"wrote {os.path.relpath(path)} ({os.path.getsize(path)} bytes)")


PROFILES = {
    "sedan_loop.wav": dict(f0=84, harmonics=9, rolloff=1.20, chug=0.12, drive=1.3, whine=0.020, detune=1, seed=1),
    "sports_loop.wav": dict(f0=120, harmonics=11, rolloff=1.05, chug=0.10, drive=2.0, whine=0.045, detune=1, seed=2),
    "taxi_loop.wav": dict(f0=72, harmonics=12, rolloff=1.00, chug=0.22, drive=2.2, whine=0.000, detune=2, seed=3),
    "van_loop.wav": dict(f0=96, harmonics=8, rolloff=1.25, chug=0.15, drive=1.5, whine=0.015, detune=1, seed=4),
    "truck_loop.wav": dict(f0=48, harmonics=14, rolloff=0.95, chug=0.38, drive=2.6, whine=0.030, detune=2, seed=5),
    "police_loop.wav": dict(f0=90, harmonics=10, rolloff=1.10, chug=0.18, drive=1.9, whine=0.055, detune=1, seed=6),
}


if __name__ == "__main__":
    write_wav("cart_rattle.wav", cart_rattle())
    for filename, params in PROFILES.items():
        write_wav(filename, engine(**params))
