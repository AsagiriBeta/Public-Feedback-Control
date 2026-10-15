function B = pcd_cav_bands(f0_hz, sc_harm)
%PCD_CAV_BANDS  稳定 / 惯性空化频带（相对本次 f0）。
%
% SC 中心 = sc_harm × f0，窗 ±20 kHz。缺省 2f（本实验室 PCD ~3 MHz）。
% 换中心频率不同的 PCD 时在界面选 3f / 1.5f 等，不要改采集 WORD/RAW。
% IC 监测仍是 (2f+80 kHz)…(2.5f−80 kHz)。参考底约 3.4–3.87 f0。
if nargin < 1 || ~(isscalar(f0_hz) && isfinite(f0_hz) && f0_hz > 0)
    f0_hz = 1.5e6;
end
if nargin < 2
    sc_harm = '2f';
end
[n_sc, tag] = pcd_sc_harm(sc_harm);
B.f0_hz = f0_hz;
B.sc_n = n_sc;
B.sc_harm = tag;
B.sc_hz = n_sc * f0_hz;
B.bw_hz = 20e3;
B.ic_hz = 2.2 * f0_hz;
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
