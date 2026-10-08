#!/usr/bin/env python3
"""
make_sfx.py -- Apex Abyss's sound pack, synthesized (numpy + scipy).

Everything is made here from oscillators and noise (no samples, nothing licensed,
nothing that can trip moderation) and written back to back into ONE audio file, so
the whole pack is a single upload. The game plays each sound's own stretch of it with
Sound.PlaybackRegion (src/client/Sfx.luau); the three ambience beds loop their region.

  assets/audio/apex_sfx.ogg       the pack (Vorbis, stereo, 44.1 kHz)
  assets/audio/preview_sfx.png    waveform of each sound, for a quick look
  src/shared/Config/Sounds.luau   the regions block between its BEGIN/END markers
                                  is rewritten with each sound's start and length

Beds (seamless loops, AmbienceController crossfades them by depth):
  AmbientShallow   bright water: soft wash, distant bubbles
  AmbientDeep      the deep floor and the Trench: a low drone, far groans
  AmbientHub       the cavern: a quiet hush and drips

One-shots:
  Bubble, Bubbles, Dash, Snap, Bite, Chomp, Hurt, Eaten, Heal, Bank, LevelUp,
  Shell, GoldenShell, Forage, Dig, ChestOpen, Reel, Tick, RollCoral, RollCommon,
  RollRare, RollEpic, RollLegendary, RollMythic, RollAbyssal, RollTrophy, Warning,
  TooBig, Banner, BossWarning, BossRise, BossPhase, BossDefeat, Breach, Grab, Ink,
  UiOpen, UiClick

Usage:  python tools/audio/make_sfx.py          (needs: pip install numpy scipy soundfile)
Then upload assets/audio/apex_sfx.ogg (Creator Hub -> Audio) and paste its id into
Config/Sounds.luau `id`.
"""

import os
import re
import sys

import numpy as np
import soundfile
from scipy import signal

SR = 44100
GAP = 0.35  # silence between sounds, seconds
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
rng = np.random.default_rng(20261008)


def secs(dur):
    return np.arange(int(round(dur * SR))) / SR


def hz(note):
    """'C5' / 'F#4' / 'Bb3' -> frequency."""
    names = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
    m = re.fullmatch(r"([A-G])([#b]?)(-?\d)", note)
    semis = names[m.group(1)] + {"#": 1, "b": -1, "": 0}[m.group(2)] + 12 * (int(m.group(3)) + 1)
    return 440.0 * 2 ** ((semis - 69) / 12)


class Track:
    """A stereo buffer that sounds are mixed into at given times."""

    def __init__(self, dur):
        self.buf = np.zeros((int(round(dur * SR)), 2))

    def add(self, mono, at=0.0, gain=1.0, pan=0.0):
        start = int(round(at * SR))
        end = min(len(self.buf), start + len(mono))
        if end <= start:
            return
        piece = mono[: end - start] * gain
        left = np.cos((pan + 1) * np.pi / 4)
        right = np.sin((pan + 1) * np.pi / 4)
        self.buf[start:end, 0] += piece * left * 1.41
        self.buf[start:end, 1] += piece * right * 1.41

    def add_stereo(self, stereo, at=0.0, gain=1.0):
        start = int(round(at * SR))
        end = min(len(self.buf), start + len(stereo))
        self.buf[start:end] += stereo[: end - start] * gain


# ---------------------------------------------------------------------------
# Instruments
# ---------------------------------------------------------------------------


def envelope(n, attack=0.005, release=0.05):
    env = np.ones(n)
    a = max(1, int(attack * SR))
    r = max(1, int(release * SR))
    env[:a] = np.linspace(0, 1, a)
    env[-r:] *= np.linspace(1, 0, r)
    return env


def marimba(f, dur=1.0):
    t = secs(dur)
    out = np.zeros_like(t)
    for ratio, amp, decay in ((1, 1.0, 0.45), (3.93, 0.35, 0.09), (9.2, 0.12, 0.03)):
        out += amp * np.sin(2 * np.pi * f * ratio * t) * np.exp(-t / decay)
    click = rng.standard_normal(int(0.004 * SR)) * np.linspace(1, 0, int(0.004 * SR)) * 0.15
    out[: len(click)] += click
    return out * envelope(len(t), 0.001, 0.03)


def glock(f, dur=1.6):
    t = secs(dur)
    out = np.zeros_like(t)
    for ratio, amp, decay in ((1, 1.0, 0.9), (2.76, 0.45, 0.35), (5.40, 0.22, 0.14), (8.93, 0.1, 0.06)):
        out += amp * np.sin(2 * np.pi * f * ratio * t) * np.exp(-t / decay)
    return out * envelope(len(t), 0.001, 0.05)


def bell(f, dur=2.5, index=5.0, ratio=3.5, decay=1.1):
    """FM bell: a carrier modulated at an inharmonic ratio, the brightness dying away."""
    t = secs(dur)
    mod_index = index * np.exp(-t / (decay * 0.5))
    mod = np.sin(2 * np.pi * f * ratio * t) * mod_index
    out = np.sin(2 * np.pi * f * t + mod) * np.exp(-t / decay)
    return out * envelope(len(t), 0.002, 0.1)


def saw(f, t, phase=0.0):
    return 2 * ((f * t + phase) % 1.0) - 1


def lowpass(x, cutoff, order=2):
    sos = signal.butter(order, min(cutoff, SR * 0.45), "low", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def highpass(x, cutoff, order=2):
    sos = signal.butter(order, cutoff, "high", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def bandpass(x, lo, hi, order=2):
    sos = signal.butter(order, [lo, min(hi, SR * 0.45)], "band", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def brass(f, dur, attack=0.04, bright=1.0):
    """Three detuned saws; a bright copy fades in on the attack and settles (a filter swell)."""
    t = secs(dur)
    vib = 1 + 0.004 * np.sin(2 * np.pi * 5.5 * t) * np.clip((t - 0.25) / 0.3, 0, 1)
    raw = sum(saw(f * vib * 2 ** (cents / 1200), t, rng.random()) for cents in (-7, 0, 6)) / 3
    dark = lowpass(raw, f * 2.5)
    lit = lowpass(raw, min(f * 9 * bright, 7000))
    swell = np.clip(t / attack, 0, 1) * (0.55 + 0.45 * np.exp(-t / 0.35))
    out = dark * (1 - swell) + lit * swell
    amp = np.clip(t / attack, 0, 1) * (0.8 + 0.2 * np.exp(-t / 0.2))
    return out * amp * envelope(len(t), 0.01, min(0.25, dur * 0.4))


def pad(notes, dur, attack=0.35, cutoff=2200, choir=0.0):
    """Detuned saws per note, soft and wide; `choir` adds an "ah" from two formant bands."""
    t = secs(dur)
    out = np.zeros_like(t)
    for note in notes:
        f = hz(note) if isinstance(note, str) else note
        for cents in (-10, -4, 3, 9):
            out += saw(f * 2 ** (cents / 1200), t, rng.random())
    out /= 4 * len(notes)
    soft = lowpass(out, cutoff)
    if choir > 0:
        ah = bandpass(out, 600, 900) * 2.2 + bandpass(out, 1000, 1300) * 1.4 + bandpass(out, 2400, 2800) * 0.6
        soft = soft * (1 - choir) + ah * choir
    return soft * envelope(len(t), attack, min(0.9, dur * 0.45))


def noise_sweep(dur, f0, f1, width=0.35, curve=1.0):
    """Noise through a band that slides from f0 to f1 (log scale): whooshes and risers."""
    n = int(dur * SR)
    noise = rng.standard_normal(n + 4096)
    f, frames, spec = signal.stft(noise, SR, nperseg=2048, noverlap=1536)
    progress = np.clip(frames / dur, 0, 1) ** curve
    centers = np.exp(np.log(f0) + (np.log(f1) - np.log(f0)) * progress)
    logf = np.log(np.maximum(f, 1))[:, None]
    mask = np.exp(-0.5 * ((logf - np.log(centers)[None, :]) / width) ** 2)
    _, out = signal.istft(spec * mask, SR, nperseg=2048, noverlap=1536)
    out = out[:n]
    return out / (np.abs(out).max() + 1e-9)


def boom(dur=1.6, f0=95, f1=32, drive=2.5):
    t = secs(dur)
    freq = f1 + (f0 - f1) * np.exp(-t / 0.18)
    phase = 2 * np.pi * np.cumsum(freq) / SR
    body = np.tanh(np.sin(phase) * drive) * np.exp(-t / 0.55)
    crack = lowpass(rng.standard_normal(len(t)), 1800) * np.exp(-t / 0.05) * 0.8
    return (body + crack) * envelope(len(t), 0.001, 0.2)


def thump(f=58, dur=0.35):
    t = secs(dur)
    freq = f * (1 + 0.6 * np.exp(-t / 0.03))
    phase = 2 * np.pi * np.cumsum(freq) / SR
    return np.sin(phase) * np.exp(-t / 0.09) * envelope(len(t), 0.002, 0.05)


def bubble(f0=700, dur=0.09, rise=0.6):
    """One bubble: a sine whose pitch rises as it shrinks, gone in a blink."""
    t = secs(dur)
    freq = f0 * (1 + rise * t / dur)
    phase = 2 * np.pi * np.cumsum(freq) / SR
    return np.sin(phase) * np.exp(-t / (dur * 0.35)) * envelope(len(t), 0.002, 0.01)


def bubbles(track, at, dur, count, f_lo=400, f_hi=1600, gain=0.25, spread=0.6):
    """A loose cluster of bubbles over `dur` seconds."""
    for _ in range(count):
        when = at + rng.random() * dur
        f = np.exp(rng.uniform(np.log(f_lo), np.log(f_hi)))
        track.add(bubble(f, rng.uniform(0.05, 0.13), rng.uniform(0.3, 0.9)), when, gain * rng.uniform(0.5, 1), rng.uniform(-spread, spread))


def shimmer(track, at, dur, density=14, low="C6", high="E7", gain=0.12):
    """A scatter of tiny high glock notes from a pentatonic set, spread across the stereo field."""
    scale = [0, 2, 4, 7, 9]
    lo, hi = hz(low), hz(high)
    notes = [f for octave in range(3, 9) for s in scale if lo <= (f := 440 * 2 ** ((octave * 12 + s - 57) / 12)) <= hi]
    for _ in range(int(density * dur)):
        when = at + rng.random() * dur
        fade = 1 - (when - at) / dur
        track.add(glock(rng.choice(notes), 0.6), when, gain * (0.4 + 0.6 * fade), rng.uniform(-0.8, 0.8))


def reverb(stereo, wet=0.25, decay=1.6, predelay=0.012):
    """Convolution with decorrelated, exponentially decaying noise (a soft hall)."""
    n = int(decay * 2.2 * SR)
    t = np.arange(n) / SR
    ir = []
    for _ in range(2):
        tail = rng.standard_normal(n) * np.exp(-t * 6.9 / decay)
        tail = lowpass(tail, 5500) + 0.0
        tail = np.concatenate([np.zeros(int(predelay * SR)), tail])
        ir.append(tail / np.sqrt(np.sum(tail**2)))
    out = stereo.copy()
    for ch in range(2):
        out[:, ch] += wet * signal.fftconvolve(stereo[:, ch], ir[ch])[: len(stereo)]
    return out


def underwater(stereo, cutoff=3200):
    """Everything down here is heard through water: the top end is dulled."""
    out = stereo.copy()
    for ch in range(2):
        out[:, ch] = lowpass(out[:, ch], cutoff, order=1)
    return out


def finish(track, peak=0.89, wet=0.22, decay=1.5, muffle=3200):
    out = underwater(reverb(track.buf, wet, decay), muffle)
    # gentle limiter, then normalize
    out = np.tanh(out * 1.1) / np.tanh(1.1)
    out *= peak / (np.abs(out).max() + 1e-9)
    tail = int(0.03 * SR)
    out[-tail:] *= np.linspace(1, 0, tail)[:, None]
    return out


def loop(stereo, cross=1.5):
    """Makes a bed seamless: its last `cross` seconds fade into its first, then are cut."""
    n = int(cross * SR)
    head, tail = stereo[:n].copy(), stereo[-n:].copy()
    fade = np.linspace(0, 1, n)[:, None]
    stereo[:n] = head * fade + tail * (1 - fade)
    out = stereo[:-n]
    return out


def brown(dur, cutoff=400):
    n = int(dur * SR)
    out = np.cumsum(rng.standard_normal(n))
    out -= np.convolve(out, np.ones(2048) / 2048, mode="same")
    out = lowpass(out, cutoff)
    return out / (np.abs(out).max() + 1e-9)


# ---------------------------------------------------------------------------
# The beds
# ---------------------------------------------------------------------------


def ambient_shallow():
    dur = 16.0
    tr = Track(dur)
    t = secs(dur)
    wash = brown(dur, 900) * (0.55 + 0.45 * np.sin(2 * np.pi * 0.09 * t + 1.0) * np.sin(2 * np.pi * 0.047 * t))
    tr.add(wash, 0, 0.5, -0.3)
    tr.add(brown(dur, 1400) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.071 * t)), 0, 0.3, 0.4)
    # A faint hiss up top, like light on the surface
    hiss = bandpass(rng.standard_normal(len(t)), 2500, 6000) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.13 * t))
    tr.add(hiss, 0, 0.035)
    bubbles(tr, 0, dur, 26, 500, 2200, 0.07, 0.9)
    return loop(finish(tr, 0.7, 0.18, 1.2, 4200))


def ambient_deep():
    dur = 18.0
    tr = Track(dur)
    t = secs(dur)
    drone = np.sin(2 * np.pi * 46 * t) * 0.6 + np.sin(2 * np.pi * 46.6 * t) * 0.4 + np.sin(2 * np.pi * 69 * t) * 0.25
    drone *= 0.6 + 0.4 * np.sin(2 * np.pi * 0.05 * t)
    tr.add(drone, 0, 0.45)
    tr.add(brown(dur, 260) * (0.6 + 0.4 * np.sin(2 * np.pi * 0.035 * t + 2)), 0, 0.5)
    # Far groans: slow sine sweeps, muffled
    for _ in range(4):
        when = rng.uniform(0.5, dur - 3)
        g = secs(2.4)
        f0 = rng.uniform(70, 130)
        freq = f0 * (1 - 0.35 * g / 2.4)
        groan = np.sin(2 * np.pi * np.cumsum(freq) / SR) * envelope(len(g), 0.6, 1.0)
        tr.add(lowpass(groan, 300), when, 0.16, rng.uniform(-0.7, 0.7))
    bubbles(tr, 0, dur, 8, 250, 700, 0.05, 0.8)
    return loop(finish(tr, 0.7, 0.3, 2.4, 1600))


def ambient_hub():
    dur = 14.0
    tr = Track(dur)
    t = secs(dur)
    tr.add(brown(dur, 500) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.06 * t)), 0, 0.32)
    # Drips: little pings with a long tail
    for _ in range(9):
        when = rng.uniform(0.3, dur - 1.2)
        tr.add(bubble(rng.uniform(1400, 2600), 0.08, 0.2), when, 0.12, rng.uniform(-0.9, 0.9))
        tr.add(glock(rng.uniform(1800, 3200), 0.9), when + 0.01, 0.025, rng.uniform(-0.9, 0.9))
    return loop(finish(tr, 0.6, 0.45, 2.8, 3600))


# ---------------------------------------------------------------------------
# The one-shots
# ---------------------------------------------------------------------------


def one_bubble():
    tr = Track(0.3)
    tr.add(bubble(900, 0.1, 0.7), 0.02, 0.8)
    return finish(tr, 0.7, 0.1, 0.6)


def some_bubbles():
    tr = Track(0.9)
    bubbles(tr, 0.02, 0.5, 9, 450, 1800, 0.5, 0.5)
    return finish(tr, 0.8, 0.12, 0.7)


def dash():
    tr = Track(0.9)
    tr.add(noise_sweep(0.42, 300, 2600, 0.4, 0.8) * envelope(int(0.42 * SR), 0.01, 0.2), 0.0, 0.7)
    tr.add(thump(70, 0.25), 0.0, 0.5)
    bubbles(tr, 0.05, 0.35, 10, 500, 2000, 0.3, 0.6)
    return finish(tr, 0.85, 0.12, 0.8)


def snap():
    tr = Track(0.35)
    click = lowpass(rng.standard_normal(int(0.03 * SR)), 2400) * np.exp(-secs(0.03) / 0.006)
    tr.add(click, 0.0, 0.9)
    tr.add(thump(160, 0.18), 0.0, 0.5)
    return finish(tr, 0.8, 0.08, 0.5)


def bite():
    tr = Track(0.7)
    tr.add(thump(110, 0.3), 0.0, 0.9)
    crunch = bandpass(rng.standard_normal(int(0.08 * SR)), 900, 3600) * np.exp(-secs(0.08) / 0.02)
    tr.add(crunch, 0.0, 0.7)
    tr.add(crunch * 0.6, 0.06, 0.5)
    bubbles(tr, 0.04, 0.3, 6, 400, 1400, 0.25, 0.5)
    return finish(tr, 0.88, 0.1, 0.7)


def chomp():
    tr = Track(0.8)
    tr.add(noise_sweep(0.22, 2600, 350, 0.35, 1.2) * envelope(int(0.22 * SR), 0.005, 0.08), 0.0, 0.55)
    g = secs(0.18)
    gulp = np.sin(2 * np.pi * np.cumsum(170 * (1 - 0.5 * g / 0.18)) / SR) * envelope(len(g), 0.01, 0.06)
    tr.add(gulp, 0.16, 0.7)
    bubbles(tr, 0.12, 0.3, 5, 500, 1500, 0.2, 0.5)
    return finish(tr, 0.85, 0.1, 0.7)


def hurt():
    tr = Track(0.8)
    tr.add(thump(80, 0.35), 0.0, 1.0)
    tr.add(lowpass(rng.standard_normal(int(0.12 * SR)), 900) * np.exp(-secs(0.12) / 0.04), 0.0, 0.6)
    bubbles(tr, 0.03, 0.4, 8, 350, 1200, 0.3, 0.6)
    return finish(tr, 0.88, 0.14, 0.9)


def eaten():
    tr = Track(1.6)
    g = secs(0.5)
    gulp = np.tanh(np.sin(2 * np.pi * np.cumsum(130 * (1 - 0.6 * g / 0.5)) / SR) * 2.2) * envelope(len(g), 0.02, 0.15)
    tr.add(lowpass(gulp, 600), 0.05, 0.8)
    tr.add(boom(1.2, 80, 28, 2.0), 0.18, 0.7)
    bubbles(tr, 0.1, 0.7, 16, 300, 1300, 0.3, 0.7)
    return finish(tr, 0.9, 0.2, 1.4, 1600)


def heal():
    tr = Track(1.2)
    tr.add(pad(["G4", "D5", "G5"], 1.0, 0.25, 1800), 0.0, 0.5)
    tr.add(glock(hz("G6"), 0.8), 0.1, 0.12)
    bubbles(tr, 0.05, 0.6, 7, 600, 1800, 0.12, 0.5)
    return finish(tr, 0.8, 0.25, 1.4)


def bank():
    tr = Track(2.0)
    for i, note in enumerate(("C5", "E5", "G5", "C6")):
        tr.add(glock(hz(note), 1.3), i * 0.1, 0.5, (i - 1.5) * 0.3)
    tr.add(bell(hz("C6"), 1.6, 3, 2.0, 0.9), 0.4, 0.3)
    shimmer(tr, 0.4, 1.2, 10, "C6", "C7", 0.08)
    return finish(tr, 0.85, 0.25, 1.6)


def level_up():
    tr = Track(2.2)
    for i, note in enumerate(("G4", "C5", "E5")):
        tr.add(brass(hz(note), 0.5 if i < 2 else 1.2, 0.03, 0.9), i * 0.16, 0.45)
    tr.add(bell(hz("G5"), 1.8, 4, 2.0, 1.0), 0.5, 0.3)
    shimmer(tr, 0.5, 1.5, 12, "C6", "G7", 0.09)
    return finish(tr, 0.88, 0.25, 1.6)


def shell():
    tr = Track(0.5)
    tr.add(glock(hz("G6"), 0.45), 0.0, 0.7)
    tr.add(bubble(1300, 0.06, 0.5), 0.0, 0.3)
    return finish(tr, 0.75, 0.1, 0.6)


def golden_shell():
    tr = Track(0.9)
    for i, note in enumerate(("C6", "E6", "G6")):
        tr.add(glock(hz(note), 0.7), i * 0.07, 0.6, (i - 1) * 0.4)
    shimmer(tr, 0.15, 0.5, 10, "C7", "C8", 0.05)
    return finish(tr, 0.8, 0.15, 0.9)


def forage():
    tr = Track(0.3)
    for i in range(2):
        crunch = bandpass(rng.standard_normal(int(0.03 * SR)), 1200, 4200) * np.exp(-secs(0.03) / 0.008)
        tr.add(crunch, i * 0.06, 0.8)
    tr.add(bubble(1100, 0.06, 0.5), 0.12, 0.25)
    return finish(tr, 0.7, 0.06, 0.4)


def dig():
    tr = Track(0.9)
    t = secs(0.7)
    scrape = bandpass(rng.standard_normal(len(t)), 250, 1600) * (0.5 + 0.5 * np.sin(2 * np.pi * 9 * t)) * envelope(len(t), 0.02, 0.2)
    tr.add(scrape, 0.0, 0.7)
    bubbles(tr, 0.1, 0.5, 6, 300, 900, 0.15, 0.5)
    return finish(tr, 0.8, 0.1, 0.7)


def chest_open():
    tr = Track(1.8)
    t = secs(0.45)
    creak = lowpass(saw(190 + 60 * t / 0.45, t), 900) * envelope(len(t), 0.03, 0.12)
    tr.add(creak, 0.0, 0.35)
    tr.add(thump(90, 0.25), 0.42, 0.5)
    tr.add(bell(hz("C6"), 1.3, 4, 2.0, 0.8), 0.5, 0.4)
    shimmer(tr, 0.55, 1.0, 12, "C6", "C7", 0.08)
    return finish(tr, 0.85, 0.22, 1.4)


def reel():
    tr = Track(0.7)
    tr.add(noise_sweep(0.55, 600, 2400, 0.45, 0.9) * envelope(int(0.55 * SR), 0.01, 0.25), 0.0, 0.6)
    return finish(tr, 0.7, 0.1, 0.6)


def tick():
    tr = Track(0.08)
    click = bandpass(rng.standard_normal(int(0.02 * SR)), 1800, 5200) * np.exp(-secs(0.02) / 0.004)
    tr.add(click, 0.0, 1.0)
    return finish(tr, 0.7, 0.02, 0.2)


def roll_coral():
    tr = Track(0.8)
    tr.add(marimba(hz("E5"), 0.5), 0.0, 0.6)
    tr.add(marimba(hz("G5"), 0.6), 0.1, 0.6)
    return finish(tr, 0.75, 0.12, 0.8)


def roll_common():
    tr = Track(1.0)
    for i, note in enumerate(("C5", "E5", "G5")):
        tr.add(marimba(hz(note), 0.6), i * 0.09, 0.6, (i - 1) * 0.3)
    return finish(tr, 0.78, 0.15, 0.9)


def roll_rare():
    tr = Track(1.6)
    for i, note in enumerate(("D5", "F#5", "A5", "D6")):
        tr.add(glock(hz(note), 1.0), i * 0.08, 0.55, (i - 1.5) * 0.3)
    shimmer(tr, 0.3, 1.0, 12, "D6", "D7", 0.08)
    return finish(tr, 0.82, 0.2, 1.3)


def roll_epic():
    tr = Track(2.2)
    for i, note in enumerate(("E4", "B4", "E5", "G#5")):
        tr.add(bell(hz(note), 1.9, 4, 2.0, 1.0), i * 0.1, 0.4, (i - 1.5) * 0.3)
    tr.add(pad(["E3", "B3"], 1.6, 0.2, 1600), 0.05, 0.35)
    shimmer(tr, 0.4, 1.4, 14, "E6", "E7", 0.09)
    return finish(tr, 0.86, 0.26, 1.8)


def roll_legendary():
    tr = Track(2.9)
    tr.add(boom(1.0, 90, 36, 2.0), 0.0, 0.5)
    for i, note in enumerate(("F4", "A4", "C5")):
        tr.add(brass(hz(note), 1.6, 0.04, 1.0), 0.15 + i * 0.07, 0.4, (i - 1) * 0.4)
    tr.add(brass(hz("F5"), 1.8, 0.03, 1.1), 0.55, 0.45)
    tr.add(bell(hz("F6"), 2.0, 4, 2.0, 1.0), 0.6, 0.3)
    shimmer(tr, 0.6, 1.8, 16, "F6", "F7", 0.1)
    return finish(tr, 0.9, 0.3, 2.0)


def roll_mythic():
    tr = Track(3.4)
    tr.add(pad(["A3", "E4", "A4", "C#5"], 3.0, 0.5, 2600, 0.6), 0.0, 0.55)
    tr.add(boom(1.2, 100, 40, 2.2), 0.3, 0.5)
    for i, note in enumerate(("A5", "C#6", "E6", "A6")):
        tr.add(bell(hz(note), 2.2, 5, 2.5, 1.1), 0.6 + i * 0.12, 0.35, (i - 1.5) * 0.35)
    shimmer(tr, 0.8, 2.2, 18, "A6", "A7", 0.1)
    return finish(tr, 0.9, 0.34, 2.4)


def roll_abyssal():
    tr = Track(3.6)
    tr.add(boom(1.8, 70, 24, 2.6), 0.0, 0.7)
    tr.add(pad(["D3", "A3", "D4"], 3.2, 0.7, 1200, 0.7), 0.1, 0.5)
    tr.add(ambient_tone(52, 2.5), 0.2, 0.3)
    for i, note in enumerate(("D5", "F5", "A5", "D6", "F6")):
        tr.add(bell(hz(note), 2.4, 6, 3.0, 1.2), 0.9 + i * 0.14, 0.3, (i - 2) * 0.3)
    shimmer(tr, 1.2, 2.2, 14, "D6", "D7", 0.08)
    return finish(tr, 0.9, 0.36, 2.6, 2600)


def ambient_tone(f, dur):
    t = secs(dur)
    return (np.sin(2 * np.pi * f * t) + 0.5 * np.sin(2 * np.pi * f * 1.5 * t)) * envelope(len(t), 0.3, 0.8)


def roll_trophy():
    tr = Track(2.8)
    for i, note in enumerate(("C4", "G4", "C5", "E5")):
        tr.add(brass(hz(note), 1.4, 0.04, 1.0), i * 0.08, 0.38, (i - 1.5) * 0.3)
    tr.add(bell(hz("C6"), 1.8, 4, 2.0, 1.0), 0.5, 0.3)
    shimmer(tr, 0.5, 1.8, 14, "C6", "C7", 0.09)
    return finish(tr, 0.88, 0.28, 1.8)


def warning():
    tr = Track(0.8)
    t = secs(0.22)
    tone = lowpass(saw(hz("A3"), t) + saw(hz("A3") * 1.005, t), 1400) * envelope(len(t), 0.01, 0.06)
    tr.add(tone, 0.0, 0.6)
    tr.add(tone, 0.3, 0.6)
    return finish(tr, 0.8, 0.1, 0.6)


def too_big():
    tr = Track(0.6)
    for i, f in enumerate((hz("E5"), hz("G5"), hz("B5"))):
        t = secs(0.09)
        tr.add(lowpass(saw(f, t), 2500) * envelope(len(t), 0.005, 0.03), i * 0.11, 0.5)
    return finish(tr, 0.75, 0.08, 0.5)


def banner():
    tr = Track(0.8)
    tr.add(noise_sweep(0.5, 400, 1600, 0.5, 1.0) * envelope(int(0.5 * SR), 0.05, 0.3), 0.0, 0.45)
    tr.add(glock(hz("E6"), 0.9), 0.08, 0.18)
    return finish(tr, 0.7, 0.2, 1.0)


def boss_warning():
    tr = Track(3.4)
    t = secs(3.0)
    sub = (np.sin(2 * np.pi * 42 * t) + 0.6 * np.sin(2 * np.pi * 63 * t)) * envelope(len(t), 1.2, 1.2)
    tr.add(sub, 0.0, 0.6)
    tr.add(brown(3.0, 320) * envelope(int(3.0 * SR), 1.0, 1.4), 0.0, 0.5)
    for when in (0.9, 1.15, 1.9, 2.15):
        tr.add(thump(52, 0.3), when, 0.6)
    return finish(tr, 0.88, 0.3, 2.4, 1800)


def boss_rise():
    tr = Track(2.6)
    tr.add(boom(1.8, 90, 26, 3.0), 0.0, 0.9)
    t = secs(1.6)
    roar = lowpass(rng.standard_normal(len(t)), 700) * (0.6 + 0.4 * np.abs(saw(38, t))) * envelope(len(t), 0.08, 0.6)
    tr.add(roar, 0.15, 0.7)
    bubbles(tr, 0.1, 1.2, 18, 250, 1100, 0.25, 0.8)
    return finish(tr, 0.92, 0.3, 2.2, 2200)


def boss_phase():
    tr = Track(1.5)
    tr.add(boom(1.3, 100, 34, 2.4), 0.0, 0.9)
    tr.add(lowpass(saw(hz("D2"), secs(0.8)), 400) * envelope(int(0.8 * SR), 0.01, 0.4), 0.05, 0.3)
    return finish(tr, 0.9, 0.25, 1.6, 2200)


def boss_defeat():
    tr = Track(3.6)
    tr.add(boom(1.4, 90, 30, 2.2), 0.0, 0.6)
    for i, note in enumerate(("C4", "G4", "C5", "E5", "G5")):
        tr.add(brass(hz(note), 2.2, 0.05, 1.0), 0.3 + i * 0.08, 0.36, (i - 2) * 0.3)
    for i, note in enumerate(("C6", "E6", "G6")):
        tr.add(bell(hz(note), 2.4, 4, 2.0, 1.1), 0.8 + i * 0.12, 0.3, (i - 1) * 0.4)
    shimmer(tr, 0.9, 2.4, 18, "C6", "C8", 0.1)
    return finish(tr, 0.9, 0.32, 2.4)


def breach():
    tr = Track(1.8)
    tr.add(boom(1.4, 110, 30, 2.8), 0.0, 1.0)
    tr.add(noise_sweep(0.9, 1800, 200, 0.5, 0.8) * envelope(int(0.9 * SR), 0.02, 0.5), 0.05, 0.6)
    bubbles(tr, 0.05, 0.9, 20, 250, 1200, 0.3, 0.9)
    return finish(tr, 0.92, 0.25, 1.8, 2400)


def grab():
    tr = Track(0.9)
    slap = lowpass(rng.standard_normal(int(0.06 * SR)), 1200) * np.exp(-secs(0.06) / 0.015)
    tr.add(slap, 0.0, 0.9)
    tr.add(noise_sweep(0.4, 900, 300, 0.4, 1.0) * envelope(int(0.4 * SR), 0.01, 0.2), 0.04, 0.5)
    bubbles(tr, 0.05, 0.4, 8, 300, 1000, 0.3, 0.5)
    return finish(tr, 0.85, 0.12, 0.9)


def ink():
    tr = Track(1.0)
    g = secs(0.35)
    bloop = np.sin(2 * np.pi * np.cumsum(220 * (1 - 0.55 * g / 0.35)) / SR) * envelope(len(g), 0.01, 0.1)
    tr.add(lowpass(bloop, 700), 0.0, 0.8)
    tr.add(brown(0.6, 500) * envelope(int(0.6 * SR), 0.02, 0.3), 0.1, 0.5)
    bubbles(tr, 0.1, 0.5, 6, 200, 700, 0.25, 0.6)
    return finish(tr, 0.85, 0.15, 1.0, 1800)


def ui_open():
    tr = Track(0.35)
    tr.add(noise_sweep(0.22, 800, 2600, 0.45, 1.0) * envelope(int(0.22 * SR), 0.01, 0.1), 0.0, 0.5)
    tr.add(glock(hz("C6"), 0.3), 0.02, 0.15)
    return finish(tr, 0.6, 0.05, 0.4)


def ui_click():
    tr = Track(0.08)
    t = secs(0.015)
    click = bandpass(rng.standard_normal(len(t)), 1200, 4000) * np.exp(-t / 0.003)
    tr.add(click, 0.0, 1.0)
    tr.add(bubble(1500, 0.03, 0.3), 0.0, 0.3)
    return finish(tr, 0.55, 0.02, 0.2)


# (name, maker, loudness in dB RMS, loops)
SOUNDS = [
    ("AmbientShallow", ambient_shallow, -27, True),
    ("AmbientDeep", ambient_deep, -26, True),
    ("AmbientHub", ambient_hub, -28, True),
    ("Bubble", one_bubble, -24, False),
    ("Bubbles", some_bubbles, -22, False),
    ("Dash", dash, -18, False),
    ("Snap", snap, -19, False),
    ("Bite", bite, -15, False),
    ("Chomp", chomp, -17, False),
    ("Hurt", hurt, -15, False),
    ("Eaten", eaten, -13, False),
    ("Heal", heal, -19, False),
    ("Bank", bank, -16, False),
    ("LevelUp", level_up, -14.5, False),
    ("Shell", shell, -21, False),
    ("GoldenShell", golden_shell, -18, False),
    ("Forage", forage, -22, False),
    ("Dig", dig, -20, False),
    ("ChestOpen", chest_open, -16, False),
    ("Reel", reel, -21, False),
    ("Tick", tick, -24, False),
    ("RollCoral", roll_coral, -18, False),
    ("RollCommon", roll_common, -17.5, False),
    ("RollRare", roll_rare, -16, False),
    ("RollEpic", roll_epic, -15, False),
    ("RollLegendary", roll_legendary, -13.5, False),
    ("RollMythic", roll_mythic, -13, False),
    ("RollAbyssal", roll_abyssal, -12.5, False),
    ("RollTrophy", roll_trophy, -14, False),
    ("Warning", warning, -17, False),
    ("TooBig", too_big, -18, False),
    ("Banner", banner, -22, False),
    ("BossWarning", boss_warning, -16, False),
    ("BossRise", boss_rise, -12.5, False),
    ("BossPhase", boss_phase, -13, False),
    ("BossDefeat", boss_defeat, -12.5, False),
    ("Breach", breach, -12.5, False),
    ("Grab", grab, -15, False),
    ("Ink", ink, -16, False),
    ("UiOpen", ui_open, -24, False),
    ("UiClick", ui_click, -24, False),
]


def loudness(audio, target_db):
    rms = np.sqrt(np.mean(audio**2)) + 1e-9
    audio = audio * (10 ** (target_db / 20) / rms)
    peak = np.abs(audio).max()
    if peak > 0.95:  # a soft knee rather than clipping
        audio = np.tanh(audio / peak * 1.5) / np.tanh(1.5) * 0.95
    return audio


def write_regions(regions):
    path = os.path.join(ROOT, "src/shared/Config/Sounds.luau")
    text = open(path, encoding="utf-8").read()
    lines = [f"\t\t{name} = {{ {start:.3f}, {length:.3f} }}," for name, start, length in regions]
    block = "\n".join(lines)
    new, count = re.subn(
        r"(-- BEGIN REGIONS[^\n]*\n).*?(\t*-- END REGIONS)",
        lambda m: m.group(1) + block + "\n" + m.group(2),
        text,
        flags=re.S,
    )
    if count != 1:
        sys.exit("Config/Sounds.luau: BEGIN/END REGIONS markers not found")
    open(path, "w", encoding="utf-8").write(new)


def preview(pieces, path):
    try:
        from PIL import Image, ImageDraw
    except ImportError:
        return
    rows = len(pieces)
    width, height = 1400, 40
    im = Image.new("RGB", (width, rows * height), (22, 22, 30))
    draw = ImageDraw.Draw(im)
    longest = max(len(p) for _, p in pieces)
    for row, (name, audio) in enumerate(pieces):
        mono = audio.mean(axis=1)
        cols = max(1, int(len(mono) / longest * (width - 140)))
        chunks = np.array_split(np.abs(mono), cols)
        y0 = row * height + height // 2
        for x, chunk in enumerate(chunks):
            h = float(chunk.max()) * (height / 2 - 3)
            draw.line([(140 + x, y0 - h), (140 + x, y0 + h)], fill=(120, 200, 255))
        draw.text((8, y0 - 6), name, fill=(255, 220, 120))
    im.save(path)


def main():
    out_dir = os.path.join(ROOT, "assets/audio")
    os.makedirs(out_dir, exist_ok=True)
    pieces = []
    regions = []
    chunks = [np.zeros((int(0.1 * SR), 2))]
    cursor = 0.1
    for name, make, target, loops in SOUNDS:
        audio = loudness(make(), target)
        pieces.append((name, audio))
        length = len(audio) / SR
        regions.append((name, cursor, length))
        chunks.append(audio)
        gap = 0.05 if loops else GAP  # a loop's region must end exactly where the bed ends
        chunks.append(np.zeros((int(gap * SR), 2)))
        cursor += length + gap
        print(f"{name:15s} {length:5.2f} s  peak {np.abs(audio).max():.2f}{'  (loop)' if loops else ''}")
    # Vorbis overshoots the peaks a little; leave it headroom
    pack = (np.concatenate(chunks) * 0.9).astype(np.float32)
    path = os.path.join(out_dir, "apex_sfx.ogg")
    # libsndfile's Vorbis encoder crashes on one big write; feed it in blocks
    with soundfile.SoundFile(path, "w", SR, 2, format="OGG", subtype="VORBIS") as f:
        for start in range(0, len(pack), 8192):
            f.write(pack[start : start + 8192])
    preview(pieces, os.path.join(out_dir, "preview_sfx.png"))
    write_regions(regions)
    print(f"wrote {path} ({len(pack) / SR:.1f} s, {os.path.getsize(path) // 1024} KB) and Config/Sounds.luau regions")


if __name__ == "__main__":
    main()
