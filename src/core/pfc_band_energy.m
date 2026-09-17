function [sc, ic, harm, sc_peak, M] = pfc_band_energy(Y, F, f0_hz, bw_hz, sc_harm)
%PFC_BAND_ENERGY  由单边幅度谱 Y=|FFT| 算 SC / IC。
%
% SC 窗中心 = sc_harm × f0（缺省 2f）。换 PCD 只改 sc_harm。
% RampSC = sum(Y) 在该窗 ±20 kHz。不改 WORD/RAW。
if nargin < 5
    sc_harm = '2f';
end
B = pfc_cav_bands(f0_hz, sc_harm);
if nargin < 4 || isempty(bw_hz)
    bw_hz = B.bw_hz;
end
Y = Y(:);
F = F(:);
n = min(numel(Y), numel(F));
Y = Y(1:n);
F = F(1:n);

sc = band_sum(Y, F, B.sc_hz, bw_hz);
sc_peak = band_max(Y, F, B.sc_hz, bw_hz);
ic_narrow = band_sum(Y, F, B.ic_hz, bw_hz);

nyq = max(F);
flo = min(B.floor_lo_hz, 0.90 * nyq);
fhi = min(B.floor_hi_hz, 0.95 * nyq);
if fhi <= flo
    flo = 0.55 * nyq;
    fhi = 0.85 * nyq;
end
floorY = band_median(Y, F, flo, fhi, B.notch_hz, B.notch_hw_hz);
if ~(isfinite(floorY) && floorY > 0)
    m = F > 0.3e6 & F <= min(8e6, nyq);
    if ~any(m)
        m(:) = true;
    end
    floorY = median(Y(m));
end
if ~(isfinite(floorY) && floorY > 0)
    floorY = realmin;
end

ic_lo = min(B.ic_lo_hz, nyq);
ic_hi = min(B.ic_hi_hz, nyq);
ic_bb = band_mean(Y, F, ic_lo, ic_hi, B.notch_hz, B.notch_hw_hz);
ic = ic_bb;

M = struct();
M.Y_kind = 'abs_fft';
M.floor = floorY;
M.sc_sum = sc;
M.sc_peak = sc_peak;
M.sc_ctrl = sc_peak / floorY;
M.ic_narrow_sum = ic_narrow;
M.ic_bb = ic_bb;
M.ic_ctrl = ic_bb / floorY;
M.ic_bb_mhz = [ic_lo, ic_hi] / 1e6;
M.floor_mhz = [flo, fhi] / 1e6;
M.sc_harm = B.sc_harm;
M.sc_mhz = B.sc_mhz;

if nargout >= 3
    harm.f0   = band_max(Y, F, 1.0 * f0_hz, max(bw_hz, 50e3));
    harm.h2   = band_max(Y, F, 2.0 * f0_hz, max(bw_hz, 50e3));
    harm.h3   = band_max(Y, F, 3.0 * f0_hz, max(bw_hz, 50e3));
    harm.uh   = band_max(Y, F, 1.5 * f0_hz, max(bw_hz, 50e3));
    harm.uh25 = band_max(Y, F, 2.5 * f0_hz, max(bw_hz, 50e3));
    harm.sub  = band_max(Y, F, 0.5 * f0_hz, max(bw_hz, 50e3));
    harm.icbb = ic_bb;
end
end

function s = band_sum(Y, F, fc, bw)
s = sum(Y(in_band(F, fc - bw, fc + bw)));
if s == 0 && ~any(in_band(F, fc - bw, fc + bw))
    [~, k] = min(abs(F - fc));
    s = Y(k);
end
end

function s = band_max(Y, F, fc, bw)
m = in_band(F, fc - bw, fc + bw);
if ~any(m)
    [~, k] = min(abs(F - fc));
    s = Y(k);
else
    s = max(Y(m));
end
end

function s = band_mean(Y, F, lo, hi, notch, nhw)
m = mask_notch(F, lo, hi, notch, nhw);
if ~any(m)
    s = NaN;
else
    s = mean(Y(m));
end
end

function s = band_median(Y, F, lo, hi, notch, nhw)
m = mask_notch(F, lo, hi, notch, nhw);
if ~any(m)
    s = NaN;
else
    s = median(Y(m));
end
end

function m = mask_notch(F, lo, hi, notch, nhw)
m = in_band(F, lo, hi);
for e = notch(:).'
    m = m & ~(abs(F - e) <= nhw);
end
end

function m = in_band(F, lo, hi)
m = F >= lo & F <= hi;
end
