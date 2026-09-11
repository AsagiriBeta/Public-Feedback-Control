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

C = pfc_ui_colors();
axBg = C.axBg; axFg = C.axFg; gridC = C.grid;
colT = C.line; colF = C.line;

sax = handles.Signal_plot;
fax = handles.FFT_plot;

ht = plot(sax, tt_us, chA);
set(ht, 'Color', colT, 'LineWidth', 1.15);
grid(sax, 'on');
set(sax, 'Color', axBg, 'XColor', axFg, 'YColor', axFg, ...
    'GridColor', gridC, 'GridAlpha', 0.5, 'GridLineStyle', ':', ...
    'Box', 'off', 'TickDir', 'out');
title(sax, [prefix '时域  Time'], 'Color', axFg, 'FontSize', 10);
xlabel(sax, 'Time (\mus)', 'Color', axFg);
ylabel(sax, 'V', 'Color', axFg);

sig = chA(isfinite(chA));
if isempty(chA) || isempty(sig) || max(abs(sig(:))) < 1e-5
    title(sax, [prefix '时域  无信号 / no signal'], 'Color', C.warn, 'FontSize', 10);
    title(fax, [prefix 'FFT  无有效波形'], 'Color', C.warn, 'FontSize', 10);
    f_peak_mhz = NaN;
    db_peak = NaN;
    drawnow limitrate;
    return;
end
hf = plot(fax, F/1e6, db);
set(hf, 'Color', colF, 'LineWidth', 1.2);
grid(fax, 'on');
set(fax, 'Color', axBg, 'XColor', axFg, 'YColor', axFg, ...
    'GridColor', gridC, 'GridAlpha', 0.5, 'GridLineStyle', ':', ...
    'Box', 'off', 'TickDir', 'out');
xlim(fax, [0 min(10, max(6, 4*f0_mhz))]);
xlabel(fax, 'Frequency (MHz)', 'Color', axFg);
ylabel(fax, 'dB', 'Color', axFg);

hold(fax, 'on');
% 0.5f / f0 / 1.5f / 2f(SC, 实线绿、加粗) / 2.5f / 3f
marks = [0.5, 1.0, 1.5, 2.0, 2.5, 3.0] * f0_mhz;
% 参考谐波统一中性灰，仅 2f（SC）用强调色加粗，避免多色杂糅
cols = [C.ref; C.refHi; C.ref; C.line; C.ref; C.ref];
ls = {'--', '-', '--', '-', '--', '--'};
lw = [1.0, 1.2, 1.0, 2.2, 1.0, 1.0];
for i = 1:numel(marks)
    xline(fax, marks(i), 'Color', cols(i, :), 'LineWidth', lw(i), 'LineStyle', ls{i});
end
[f_peak_mhz, db_peak] = pfc_fft_peak_mhz(F, db, 0.3, 8);
db2 = band_peak_db(F, db, 2 * f0_mhz * 1e6, 200e3);
if ~isnan(f_peak_mhz)
    plot(fax, f_peak_mhz, db_peak, 'o', 'Color', C.text, ...
        'MarkerSize', 7, 'LineWidth', 1.2);
    title(fax, sprintf('%sFFT  f_0=%.2f  SC 2f=%.2f MHz (%.0f dB)  peak=%.3f', ...
        prefix, f0_mhz, 2*f0_mhz, db2, f_peak_mhz), ...
        'Color', axFg, 'FontSize', 10);
else
    title(fax, sprintf('%sFFT  f_0=%.2f  SC 2f=%.2f MHz', prefix, f0_mhz, 2*f0_mhz), ...
        'Color', axFg, 'FontSize', 10);
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
