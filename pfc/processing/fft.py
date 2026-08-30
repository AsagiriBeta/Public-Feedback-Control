"""FFT 谐波带：第三谐波附近为 SC，基频/2 附近为 IC。"""

from __future__ import annotations

import numpy as np


def _band_indices(fc: float, df: float, nmax: int, bw: float) -> np.ndarray:
    f_lo = fc - bw
    f_hi = fc + bw
    k1 = max(1, int(np.floor(f_lo / df)) + 1)
    k2 = min(nmax, int(np.ceil(f_hi / df)) + 1)
    if k2 < k1:
        kc = min(nmax, max(1, int(round(fc / df)) + 1))
        return np.array([kc], dtype=int)
    return np.arange(k1, k2 + 1, dtype=int)


def harmonic_bands(f0_hz: float, fs: float, nfft: int, bw_hz: float) -> tuple[np.ndarray, np.ndarray]:
    df = fs / nfft
    nmax = nfft // 2 + 1
    sc = _band_indices(3 * f0_hz, df, nmax, bw_hz)
    ic = _band_indices(f0_hz / 2.0, df, nmax, bw_hz)
    return sc, ic


def pulse_spectrum(signal: np.ndarray, nfft: int) -> np.ndarray:
    spec = np.abs(np.fft.fft(signal, n=nfft))
    return spec[: nfft // 2 + 1]
