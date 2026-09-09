function [F, Y, db, NFFT] = pfc_spectrum(chA, realFs)
%PFC_SPECTRUM 单边幅度谱与 dB（供界面与存盘共用）。
n = numel(chA);
NFFT = 2^nextpow2(max(n, 2));
X = abs(fft(chA, NFFT));
Y = X(1:floor(NFFT/2)+1);
F = realFs .* (0:(NFFT/2)) / NFFT;
db = 20*log10(max(Y, 1e-18));
end
