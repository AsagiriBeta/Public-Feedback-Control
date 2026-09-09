function [f_peak_mhz, db_peak] = pfc_update_signal_fft(handles, chA, dt_ns, realFs, f0_mhz, srcName)
%PFC_UPDATE_SIGNAL_FFT 时域 + FFT（亮色曲线，标出换能器 f0）。
[F, ~, db] = pfc_spectrum(chA, realFs);
tt_us = (0:(numel(chA)-1)) / realFs * 1e6;
if nargin < 5 || isempty(f0_mhz)
    f0_mhz = 1.5;
end
if nargin < 6 || isempty(srcName)
    srcName = '';
end
prefix = '';
if ~isempty(srcName)
    prefix = [srcName '  '];
end

axBg = [0.09 0.11 0.15];
axFg = [0.82 0.86 0.90];
colT = [0.30 0.82 1.00];
colF = [1.00 0.78 0.22];

sax = handles.Signal_plot;
fax = handles.FFT_plot;

ht = plot(sax, tt_us, chA);
set(ht, 'Color', colT, 'LineWidth', 1.15);
grid(sax, 'on');
set(sax, 'Color', axBg, 'XColor', axFg, 'YColor', axFg, ...
    'GridColor', [0.28 0.34 0.40], 'GridAlpha', 0.45, 'Box', 'on');
title(sax, [prefix '时域  Time'], 'Color', axFg, 'FontSize', 11);
xlabel(sax, 'Time (\mus)', 'Color', axFg);
ylabel(sax, 'V', 'Color', axFg);

sig = chA(isfinite(chA));
if isempty(chA) || isempty(sig) || max(abs(sig(:))) < 1e-5
    title(sax, [prefix '时域  无信号 / no signal'], 'Color', [1 0.5 0.5], 'FontSize', 11);
    title(fax, [prefix 'FFT  无有效波形'], 'Color', [1 0.5 0.5], 'FontSize', 11);
    f_peak_mhz = NaN;
    db_peak = NaN;
    drawnow limitrate;
    return;
end
hf = plot(fax, F/1e6, db);
set(hf, 'Color', colF, 'LineWidth', 1.2);
grid(fax, 'on');
set(fax, 'Color', axBg, 'XColor', axFg, 'YColor', axFg, ...
    'GridColor', [0.28 0.34 0.40], 'GridAlpha', 0.45, 'Box', 'on');
xlim(fax, [0 min(10, max(6, 4*f0_mhz))]);
xlabel(fax, 'Frequency (MHz)', 'Color', axFg);
ylabel(fax, 'dB', 'Color', axFg);

hold(fax, 'on');
% 0.5f / f0 / 1.5f / 2f(SC, 实线绿、加粗) / 2.5f / 3f
marks = [0.5, 1.0, 1.5, 2.0, 2.5, 3.0] * f0_mhz;
cols = [
    0.75 0.45 1.00
    1.00 0.38 0.38
    0.55 0.75 1.00
    0.20 0.92 0.42
    0.55 0.75 1.00
    0.40 0.85 0.75
    ];
ls = {'--', '-', '--', '-', '--', '--'};
lw = [1.0, 1.4, 1.0, 2.2, 1.0, 1.0];
for i = 1:numel(marks)
    xline(fax, marks(i), 'Color', cols(i, :), 'LineWidth', lw(i), 'LineStyle', ls{i});
end
[f_peak_mhz, db_peak] = pfc_fft_peak_mhz(F, db, 0.3, 8);
db2 = band_peak_db(F, db, 2 * f0_mhz * 1e6, 200e3);
if ~isnan(f_peak_mhz)
    plot(fax, f_peak_mhz, db_peak, 'o', 'Color', [1 0.95 0.95], ...
        'MarkerSize', 7, 'LineWidth', 1.2);
    title(fax, sprintf('%sFFT  f_0=%.2f  SC 2f=%.2f MHz (%.0f dB)  peak=%.3f', ...
        prefix, f0_mhz, 2*f0_mhz, db2, f_peak_mhz), ...
        'Color', axFg, 'FontSize', 11);
else
    title(fax, sprintf('%sFFT  f_0=%.2f  SC 2f=%.2f MHz', prefix, f0_mhz, 2*f0_mhz), ...
        'Color', axFg, 'FontSize', 11);
end
hold(fax, 'off');
drawnow limitrate;
end

function dbp = band_peak_db(F, db, fc_hz, bw_hz)
m = (F >= fc_hz - bw_hz) & (F <= fc_hz + bw_hz);
if ~any(m)
    dbp = NaN;
else
    dbp = max(db(m));
end
end
