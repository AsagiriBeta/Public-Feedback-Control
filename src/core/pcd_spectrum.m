function [F, Y, db, NFFT] = pcd_spectrum(chA, realFs)
%PCD_SPECTRUM 单边幅度谱与 dB（供界面与存盘共用）。
%
% 与 Chien 2022 源码同一套：
%   X = abs(fft(chA, NFFT));  Y = X(1:NFFT/2+1);
% Y 是幅度 |X(f)|，不是 |X|^2，也不是 PSD。闭环不要把 sum(Y) 叫「能量」；
% 功率型指标若要用，在 pcd_band_energy 里对 Y.^2 再积，不改这里。
n = numel(chA);
NFFT = 2^nextpow2(max(n, 2));
X = abs(fft(chA, NFFT));
Y = X(1:floor(NFFT/2)+1);
F = realFs .* (0:(NFFT/2)) / NFFT;
db = 20*log10(max(Y, 1e-18));
end
