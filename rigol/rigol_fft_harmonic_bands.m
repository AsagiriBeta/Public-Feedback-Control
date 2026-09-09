function [SC_range, IC_range] = rigol_fft_harmonic_bands(f0_hz, Fs, NFFT, bw_hz)
%RIGOL_FFT_HARMONIC_BANDS 本实验室：SC=2 f0（3.0 MHz），IC=2.2 f0（3.3 MHz）。
%  Chien 2022 用 3f=4.5 MHz 因 PCD~4.7 MHz；此处 PCD~3 MHz，故 SC 用 2f。
df = Fs / NFFT;
nmax = floor(NFFT / 2) + 1;
SC_range = fft_band_indices(2 * f0_hz, df, nmax, bw_hz);
IC_range = fft_band_indices(2.2 * f0_hz, df, nmax, bw_hz);
end

function r = fft_band_indices(fc, df, nmax, bw)
f_lo = fc - bw;
f_hi = fc + bw;
k1 = max(1, floor(f_lo / df) + 1);
k2 = min(nmax, ceil(f_hi / df) + 1);
if k2 < k1
    kc = min(nmax, max(1, round(fc / df) + 1));
    r = kc;
else
    r = k1:k2;
end
end
