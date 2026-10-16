function [F, Y, db, NFFT] = pcd_spectrum(chA, realFs)
%PCD_SPECTRUM 单边幅度谱与 dB（供界面与存盘共用）。
%
% 与 Chien 2022 源码同一套：
%   X = abs(fft(chA, NFFT));  Y = X(1:NFFT/2+1);
% Y 是幅度 |X(f)|，不是 |X|^2，也不是 PSD。闭环不要把 sum(Y) 叫「能量」；
% 功率型指标若要用，在 pcd_band_energy 里对 Y.^2 再积，不改这里。
%
% 但要多除一个 n（见下面）：矩形窗下 |X[k]| 正比于窗内样点数，原始 abs(fft)
% 的长度量纲没有被除掉。改之前同一物理信号只要 n_cycle 变了（→ acq_n 变），
% SC/IC 就整体平移几 dB，跨轮次、跨参数的 dB 纵轴没有意义。
% 除 n 之后：闭环完全不受影响（sc0/sc_tgt 取自同一轮，比值不变；
% pcd_band_energy 的 sc_ctrl = 峰值/底也是比值），pcd_2f_quality 用帧内差也不受影响。
% 变的只有存盘里的绝对 dB —— 那些本来就只在「同一套几何」内可比，现在可比范围扩大了。
n = numel(chA);
NFFT = 2^nextpow2(max(n, 2));
X = abs(fft(chA, NFFT));
Y = X(1:floor(NFFT/2)+1);
Y = Y / max(n, 1);        % 去掉长度量纲：Y ≈ 幅度的 1/2（相干 bin 上）
F = realFs .* (0:(NFFT/2)) / NFFT;
db = 20*log10(max(Y, 1e-18));
end
