function [F, Y, db, NFFT] = pcd_spectrum(chA, realFs)
%PCD_SPECTRUM 单边幅度谱与 dB（供界面与存盘共用）。
%
% 与 Chien 2022 源码同一套：
%   X = abs(fft(chA, NFFT));  Y = X(1:NFFT/2+1);
% Y 是幅度 |X(f)|，不是 |X|^2，也不是 PSD。闭环不要把 sum(Y) 叫「能量」；
% 功率型指标若要用，在 pcd_band_energy 里对 Y.^2 再积，不改这里。
%
% 不要在这里除样点数（曾经试过 Y = Y/n，已撤回）。
% 除 n 之后 Y ≈ 幅度/2，物理上更好看，但会把整条谱按 20log10(n) 平移
% （n=40000 就是 -92 dB），而下游有**绝对** dB 判据：
%   pcd_fft_peak_mhz 的 `db_pk > -120` 门限 → 正常峰被判成「无峰」；
%   html_waveform 的谱纵轴、存盘的 harm_db 绝对值也一起变形。
% 「SC 随帧长漂移」那个真问题不靠这里解决：acq_n 现在由采集几何定死、
% crop_fixed 每帧取满同样的点数，所以同一套几何下长度本来就是常数。
% 要跨几何比较绝对值，本来就是另一件事，不该偷偷改谱的标度。
n = numel(chA);
NFFT = 2^nextpow2(max(n, 2));
X = abs(fft(chA, NFFT));
Y = X(1:floor(NFFT/2)+1);
F = realFs .* (0:(NFFT/2)) / NFFT;
db = 20*log10(max(Y, 1e-18));
end
