from __future__ import annotations

import numpy as np

from pfc.processing.fft import harmonic_bands, pulse_spectrum


def test_band_around_third_harmonic():
    fs = 40e6
    nfft = 65536
    f0 = 1.5e6
    sc, ic = harmonic_bands(f0, fs, nfft, 200e3)
    df = fs / nfft
    sc_hz = (sc - 1) * df
    ic_hz = (ic - 1) * df
    assert abs(sc_hz.mean() - 4.5e6) < 2e5
    assert abs(ic_hz.mean() - 0.75e6) < 2e5


def test_spectrum_peak():
    fs = 40e6
    n = 4096
    t = np.arange(n) / fs
    x = np.sin(2 * np.pi * 1e6 * t)
    y = pulse_spectrum(x, n)
    freqs = fs * np.arange(n // 2 + 1) / n
    peak = freqs[int(np.argmax(y))]
    assert abs(peak - 1e6) < 50e3
