function B = pfc_cav_bands(f0_hz)
%PFC_CAV_BANDS  稳定 / 惯性空化频带（相对本次 f0）。
%
% 本实验室 FUS 1.5 MHz、PCD ~3 MHz：
%   SC 中心 = 2*f0 = 3.0 MHz，窗 ±20 kHz（二次谐波）。原文 SC 用 3f=4.5 MHz，
%   只因他们 PCD 中心约 4.7 MHz；不要改回 3f。
%   IC 监测 = (2f + 80 kHz) … (2.5f − 80 kHz)，即夹在谐波之间的一段宽带，
%   不再用 3.3 MHz ±20 kHz 窄窗（那只是频谱底的 proxy）。
% 参考底：约 3.4 f0–3.87 f0（1.5 MHz → 5.1–5.8 MHz），躲开 2.85 / 4.18 EMI。
if nargin < 1 || ~(isscalar(f0_hz) && isfinite(f0_hz) && f0_hz > 0)
    f0_hz = 1.5e6;
end
B.f0_hz = f0_hz;
B.sc_hz = 2.0 * f0_hz;
B.bw_hz = 20e3;
B.ic_hz = 2.2 * f0_hz;                 % 旧窄窗中心，只给存档对照
B.ic_lo_hz = 2.0 * f0_hz + 80e3;
B.ic_hi_hz = 2.5 * f0_hz - 80e3;
if B.ic_hi_hz <= B.ic_lo_hz
    B.ic_lo_hz = 2.0 * f0_hz + B.bw_hz;
    B.ic_hi_hz = 2.5 * f0_hz - B.bw_hz;
end
B.floor_lo_hz = 3.40 * f0_hz;
B.floor_hi_hz = 3.87 * f0_hz;
B.notch_hz = [2.85e6, 4.18e6];
B.notch_hw_hz = 30e3;
B.sc_mhz = B.sc_hz / 1e6;
B.ic_mhz = B.ic_hz / 1e6;
B.ic_bb_mhz = [B.ic_lo_hz, B.ic_hi_hz] / 1e6;
B.floor_mhz = [B.floor_lo_hz, B.floor_hi_hz] / 1e6;
end
