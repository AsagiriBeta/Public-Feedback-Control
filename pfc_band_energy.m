function [sc, ic, harm] = pfc_band_energy(Y, F, f0_hz, bw_hz)
%PFC_BAND_ENERGY  Chien et al., CMMM 2022 (9867230) 频带；SC 频点按本实验室 PCD 改写。
%  SC：二次谐波 2*f0 ±bw（1.5 MHz FUS → 3.0 MHz）。原文用 3f=4.5 MHz，只因
%      他们的 PCD（I5P10）中心约 4.7 MHz，4.5 MHz 最近。本实验室 PCD ~3 MHz，故用 2f。
%  IC：避开谐波/超谐波的宽带，仍为 2.2*f0（1.5 MHz → 3.3 MHz）。3.3 距 2f=3.0
%      为 300 kHz，±20 kHz 不重叠，可保留。默认 bw 与原文相同（±20 kHz）。
if nargin < 4 || isempty(bw_hz)
    bw_hz = 20e3;
end
sc = band_sum(Y, F, 2 * f0_hz, bw_hz);
ic = band_sum(Y, F, 2.2 * f0_hz, bw_hz);  % 2.2*1.5e6 = 3.3 MHz；距 2f 300 kHz
if nargout >= 3
    harm.f0   = band_max(Y, F, 1.0 * f0_hz, max(bw_hz, 50e3));
    harm.h2   = band_max(Y, F, 2.0 * f0_hz, max(bw_hz, 50e3));
    harm.h3   = band_max(Y, F, 3.0 * f0_hz, max(bw_hz, 50e3));
    harm.uh   = band_max(Y, F, 1.5 * f0_hz, max(bw_hz, 50e3));
    harm.uh25 = band_max(Y, F, 2.5 * f0_hz, max(bw_hz, 50e3));
    harm.sub  = band_max(Y, F, 0.5 * f0_hz, max(bw_hz, 50e3));
    harm.icbb = band_max(Y, F, 2.2 * f0_hz, bw_hz);
end
end

function s = band_sum(Y, F, fc, bw)
m = (F >= fc - bw) & (F <= fc + bw);
if ~any(m)
    [~, k] = min(abs(F - fc));
    m = false(size(F));
    m(k) = true;
end
s = sum(Y(m));
end

function s = band_max(Y, F, fc, bw)
m = (F >= fc - bw) & (F <= fc + bw);
if ~any(m)
    [~, k] = min(abs(F - fc));
    s = Y(k);
else
    s = max(Y(m));
end
end
