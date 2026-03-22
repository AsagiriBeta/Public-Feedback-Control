function [SC_range, IC_range] = rigol_fft_harmonic_bands(f0_hz, Fs, NFFT, bw_hz)
%RIGOL_FFT_HARMONIC_BANDS 由基频估计第三谐波(SC)与 f0/2 附近(IC)的 FFT 索引范围。
% 对应 Chien et al. 2022 中在固定 Picoscope 配置下使用的频带思想；此处随实际 Fs/NFFT 自适应。

df = Fs / NFFT;
nmax = floor(NFFT / 2) + 1;
SC_range = fft_band_indices(3 * f0_hz, df, nmax, bw_hz);
IC_range = fft_band_indices(f0_hz / 2, df, nmax, bw_hz);
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
