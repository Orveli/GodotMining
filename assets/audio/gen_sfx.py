"""
Proseduraaliset SFX:t GodotMining-demoon — sama eetos kuin assets/ui/gen_ui_assets.py.

Kaikki aanet syntetisoidaan koodista (numpy) — reprodusoituva, ei lisenssiongelmia.
Aja projektin juuresta:

    python assets/audio/gen_sfx.py

Ulostulo: 44.1 kHz / 16-bit / mono WAV:t kansioon assets/audio/:
  - mine_chunk.wav   (~0.15 s) suodatettua kohinaa + matala thunk (kiven murskaus)
  - cash.wav         (~0.2 s)  kirkas kilahdus (koliseva kolikko)
  - milestone.wav    (~0.6 s)  nouseva kolmisointu-arpeggio (8-bit kanttiaalto)
  - ui_click.wav     (~0.05 s) lyhyt naksahdus
  - ambient_hum.wav  (~4 s)    matala pehmea humina + kaiku, SAUMATON looppi

Tyyli: teollinen/maanalainen, lampin matala pohja. Kaikki envelopet lahtevat
nollasta ja vaimenevat nollaan -> ei klik-artefakteja saumoissa. Ambient kayttaa
kokonaislukusykleja loopin pituudella -> paatepisteet tasmaavat (saumaton).
"""

import os
import wave
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
SR = 44100                      # naytteenottotaajuus (Hz)

# Deterministinen kohina -> sama tulos joka ajolla (reprodusoituva).
RNG = np.random.default_rng(1234)


# ---------------------------------------------------------------------------
# Apurit
# ---------------------------------------------------------------------------

def t_axis(dur: float) -> np.ndarray:
    """Aika-akseli sekunteina, n naytetta."""
    n = int(round(dur * SR))
    return np.arange(n, dtype=np.float64) / SR


def sine(freq: float, t: np.ndarray, phase: float = 0.0) -> np.ndarray:
    return np.sin(2.0 * np.pi * freq * t + phase)


def square(freq: float, t: np.ndarray, duty: float = 0.5) -> np.ndarray:
    """8-bit-henkinen kanttiaalto (duty-suhde saadettavissa)."""
    frac = (freq * t) % 1.0
    return np.where(frac < duty, 1.0, -1.0)


def exp_env(t: np.ndarray, attack: float, decay: float) -> np.ndarray:
    """Nopea nousu + eksponentiaalinen vaimennus. Alkaa ja paattyy ~nollaan."""
    env = np.ones_like(t)
    if attack > 0.0:
        a = np.clip(t / attack, 0.0, 1.0)
        env = np.minimum(env, a)
    env = env * np.exp(-t / max(decay, 1e-6))
    return env


def one_pole_lowpass(x: np.ndarray, cutoff: float) -> np.ndarray:
    """Yksinapainen alipaastosuodatin (pehmentaa kohinaa)."""
    dt = 1.0 / SR
    rc = 1.0 / (2.0 * np.pi * max(cutoff, 1.0))
    alpha = dt / (rc + dt)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(x.size):
        acc += alpha * (x[i] - acc)
        y[i] = acc
    return y


def fade_edges(x: np.ndarray, ms: float = 3.0) -> np.ndarray:
    """Lyhyt nousu/lasku reunoihin -> ei napsausta one-shot-alussa/lopussa."""
    n = int(SR * ms / 1000.0)
    if n <= 0 or 2 * n >= x.size:
        return x
    ramp = np.linspace(0.0, 1.0, n)
    x[:n] *= ramp
    x[-n:] *= ramp[::-1]
    return x


def normalize(x: np.ndarray, peak: float = 0.9) -> np.ndarray:
    m = np.max(np.abs(x))
    if m < 1e-9:
        return x
    return x * (peak / m)


def write_wav(name: str, x: np.ndarray) -> None:
    """Kirjoita mono 16-bit PCM WAV."""
    x = np.clip(x, -1.0, 1.0)
    pcm = (x * 32767.0).astype(np.int16)
    path = os.path.join(HERE, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print("  kirjoitettu %-16s %6d naytetta  (%.3f s)" % (name, x.size, x.size / SR))


# ---------------------------------------------------------------------------
# 1) mine_chunk.wav — kiven murskaus (kohina + matala thunk)
# ---------------------------------------------------------------------------

def gen_mine_chunk() -> np.ndarray:
    t = t_axis(0.15)

    # Matala "thunk": taajuus laskee nopeasti (kivi natisee).
    f = 95.0 * np.exp(-t * 22.0) + 45.0
    phase = 2.0 * np.pi * np.cumsum(f) / SR
    thunk = np.sin(phase) * exp_env(t, 0.002, 0.045)

    # Murskauskohina: suodatettu (alipaasto) valko-kohina, terava vaimennus.
    noise = RNG.uniform(-1.0, 1.0, t.size)
    noise = one_pole_lowpass(noise, 1800.0)
    noise *= exp_env(t, 0.001, 0.03)

    x = 0.85 * thunk + 0.5 * noise
    x = fade_edges(x, 2.0)
    return normalize(x, 0.85)


# ---------------------------------------------------------------------------
# 2) cash.wav — kirkas kilahdus (koliseva kolikko)
# ---------------------------------------------------------------------------

def gen_cash() -> np.ndarray:
    t = t_axis(0.2)

    # Kolme kirkasta osasavelta (hieman epaharmonisia -> metallinen kilahdus).
    env = exp_env(t, 0.001, 0.09)
    x = (
        1.00 * sine(1200.0, t) +
        0.70 * sine(1810.0, t) +
        0.45 * sine(2630.0, t)
    ) * env

    # Toinen, pehmeampi "kilahdus" hieman myohemmin -> kolikon pomppu.
    t2 = t_axis(0.2)
    env2 = np.concatenate([np.zeros(int(0.04 * SR)),
                           exp_env(t2, 0.001, 0.06)])[:t.size]
    x += 0.5 * (sine(1580.0, t) + 0.6 * sine(2370.0, t)) * env2

    x = fade_edges(x, 2.0)
    return normalize(x, 0.85)


# ---------------------------------------------------------------------------
# 3) milestone.wav — nouseva kolmisointu-arpeggio (8-bit)
# ---------------------------------------------------------------------------

def gen_milestone() -> np.ndarray:
    # C5, E5, G5, C6 -> nouseva duuri-arpeggio.
    notes = [523.25, 659.25, 783.99, 1046.50]
    note_dur = 0.15
    total = t_axis(0.6)
    x = np.zeros_like(total)

    for i, freq in enumerate(notes):
        start = int(i * note_dur * SR)
        tn = t_axis(note_dur + 0.12)          # hantaa yli seuraavan alkuun
        env = exp_env(tn, 0.004, 0.10)
        # Kokonaisvaimennus arpeggion yli (hiljenee loppua kohti).
        amp = 0.9 - 0.12 * i
        tone = square(freq, tn, duty=0.5) * env * amp
        end = min(start + tn.size, x.size)
        x[start:end] += tone[:end - start]

    x = fade_edges(x, 3.0)
    return normalize(x, 0.8)


# ---------------------------------------------------------------------------
# 4) ui_click.wav — lyhyt naksahdus
# ---------------------------------------------------------------------------

def gen_ui_click() -> np.ndarray:
    t = t_axis(0.05)

    # Terava kohinanaksu + korkea lyhyt sini -> "tik".
    noise = RNG.uniform(-1.0, 1.0, t.size)
    noise = one_pole_lowpass(noise, 6000.0)
    noise *= exp_env(t, 0.0005, 0.008)

    tick = sine(2200.0, t) * exp_env(t, 0.0005, 0.006)

    x = 0.7 * noise + 0.5 * tick
    x = fade_edges(x, 1.0)
    return normalize(x, 0.7)


# ---------------------------------------------------------------------------
# 5) ambient_hum.wav — matala humina + kaiku, SAUMATON looppi
# ---------------------------------------------------------------------------

def gen_ambient_hum() -> np.ndarray:
    dur = 4.0
    t = t_axis(dur)

    # Saumattomuus: kaikki taajuudet = kokonaisluku sykleja loopin pituudella
    # (dur=4 s -> monikerta 0.25 Hz). Nain paatepiste tasmaa alkuun (ei klik).
    def snap(freq: float) -> float:
        return round(freq * dur) / dur

    f_lo = snap(56.0)      # matala pohja
    f_mid = snap(84.0)     # kvintti-henkinen sivusavel
    f_air = snap(112.0)    # oktaavi, ohut

    # Hidas tremolo (myos kokonaissykleja -> saumaton).
    lfo = 0.85 + 0.15 * sine(snap(0.5), t)
    lfo2 = 0.9 + 0.1 * sine(snap(0.25), t)

    tone = (
        1.00 * sine(f_lo, t) +
        0.45 * sine(f_mid, t) +
        0.22 * sine(f_air, t)
    ) * lfo * lfo2

    # Hienovarainen kaiku: kaksi kiertavaa (np.roll) delay-tappia. Koska looppi on
    # jo saumaton, myos kiertava viive pysyy saumattomana.
    d1 = int(0.17 * SR)
    d2 = int(0.33 * SR)
    echo = 0.28 * np.roll(tone, d1) + 0.15 * np.roll(tone, d2)

    x = tone + echo
    # EI fade_edges — se rikkoisi saumattomuuden. Kokonaissyklit hoitavat sauman.
    return normalize(x, 0.6)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    os.makedirs(HERE, exist_ok=True)
    print("Generoidaan SFX -> %s" % HERE)
    write_wav("mine_chunk.wav", gen_mine_chunk())
    write_wav("cash.wav", gen_cash())
    write_wav("milestone.wav", gen_milestone())
    write_wav("ui_click.wav", gen_ui_click())
    write_wav("ambient_hum.wav", gen_ambient_hum())
    print("Valmis.")


if __name__ == "__main__":
    main()
