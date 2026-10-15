function Q = pcd_2f_quality(F, db, f0_mhz)
%PCD_2F_QUALITY  判断 CH2 在 2f 处是真空化、2.85 EMI，还是底噪。
% 调探头 / PCB / 微泡管距离时看这个：不要把 0.3–8 MHz 全局峰（常见 4.18）
% 或 ±200 kHz 里的 2.85 MHz 干扰当成 2f 空化。
% 判据与 SC 带宽一致（2*f0 ±20 kHz）；2.85 距 3.00 有 150 kHz，不会进 SC 窗，
% 但会进旧的 harm_db ±200 kHz 窗。
Q = struct('f2_mhz', NaN, 'db2', NaN, 'snr2', NaN, ...
    'floor_db', NaN, 'flag', 'noise', 'note', '2f 无有效谱');
if nargin < 3 || isempty(F) || isempty(db) || ~(isscalar(f0_mhz) && isfinite(f0_mhz) && f0_mhz > 0)
    return;
end
fM = F(:) / 1e6;
d = db(:);
if numel(fM) ~= numel(d)
    n = min(numel(fM), numel(d));
    fM = fM(1:n);
    d = d(1:n);
end
keep = fM > 0.3 & fM <= 8;
if ~any(keep)
    keep(:) = true;
end
Q.floor_db = median(d(keep));
hw = 0.02;                              % ±20 kHz，与 pcd_band_energy SC 一致
f2 = 2 * f0_mhz;
p2 = local_peak(fM, d, f2, hw);
p285 = local_peak(fM, d, 2.85, hw);
Q.f2_mhz = p2.f;
Q.db2 = p2.db;
Q.snr2 = p2.db - Q.floor_db;
Q.db_emi285 = p285.db;
Q.snr_emi285 = p285.db - Q.floor_db;
% 真 2f：紧贴 3.00 MHz、高出底噪 ≥8 dB、并且比 2.85 EMI 至少高 3 dB。
real2 = isfinite(Q.snr2) && Q.snr2 >= 8 && isfinite(p2.f) && abs(p2.f - f2) < 0.03 ...
    && ~(isfinite(p285.db) && p2.db < p285.db + 3);
emi = isfinite(p285.db) && isfinite(Q.snr_emi285) && Q.snr_emi285 >= 8 ...
    && p285.db > p2.db + 1;
if real2
    Q.flag = 'real';
    Q.note = sprintf('2f=%.2f MHz（二次谐波） SNR %.1f  真峰', f2, Q.snr2);
elseif emi
    Q.flag = 'emi';
    % 黄线是 2.85 MHz 电磁干扰，不是 2f。2f 在 2*f0（1.5 MHz → 3.0 MHz）。
    Q.note = sprintf('2f 在 %.2f MHz  SNR %.1f；黄线 2.85 MHz 是电磁干扰 SNR %.1f（干扰比二次谐波强，不是空化）', ...
        f2, Q.snr2, Q.snr_emi285);
else
    Q.flag = 'noise';
    Q.note = sprintf('2f 在 %.2f MHz  SNR %.1f  贴底噪，还不是空化', f2, Q.snr2);
end
end

function s = local_peak(f, db, fm, hw)
mask = abs(f - fm) <= hw;
if ~any(mask)
    s.f = NaN;
    s.db = NaN;
    return;
end
[s.db, i] = max(db(mask));
ff = f(mask);
s.f = ff(i);
end
