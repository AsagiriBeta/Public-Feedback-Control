function [f_mhz, db_pk] = pfc_fft_peak_mhz(F, db, fmin_mhz, fmax_mhz)
%PFC_FFT_PEAK_MHZ 在指定频带内找谱峰；接近底噪则视为无峰。
if nargin < 3, fmin_mhz = 0.3; end
if nargin < 4, fmax_mhz = 8; end
mask = (F >= fmin_mhz*1e6) & (F <= fmax_mhz*1e6);
if ~any(mask)
    f_mhz = NaN;
    db_pk = NaN;
    return;
end
d = db(mask);
f = F(mask);
[db_pk, i] = max(d);
noise = median(d);
if ~(isfinite(db_pk) && db_pk > noise + 8 && db_pk > -120)
    f_mhz = NaN;
    db_pk = NaN;
    return;
end
f_mhz = f(i) / 1e6;
end
