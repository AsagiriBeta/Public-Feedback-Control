function pfc_save_run_plots(rundir, S)
%PFC_SAVE_RUN_PLOTS 存盘结束时出一套分析图（每发脉冲不画，只在最终 pack_save 后一次）。
% 频谱走 pfc_spectrum / pfc_2f_quality / pfc_fft_peak_mhz，SC/IC 用已经存进
% S 的 RampSC / RampIC，不重写空化能量、也不碰 WORD/RAW。
% 图失败由调用方吞掉，保证 raw.mat 还在。
if nargin < 2 || ~isstruct(S) || strlength(string(rundir)) < 1
    return;
end
rundir = char(string(rundir));
[tx, pcd, fs, f0] = waves_from(S);
np = max(size(tx, 1), size(pcd, 1));
if np < 1 || ~(isfinite(fs) && fs > 0)
    return;
end
k = pick_rep_pulse(S, np);   % 代表帧：维持段 SNR 中位数，避免末发碰巧偏低
f_max = fft_cap(fs, f0);
emi_col = [0.769 0.639 0.353];
ch1_col = [0.10 0.35 0.75];
ch2_col = [0.80 0.25 0.15];

if ~isempty(tx)
    try_plot(fullfile(rundir, 'fft_ch1.png'), @(fig) plot_fft_ch1(fig, tx(min(k, size(tx,1)), :), fs, f0, f_max, ch1_col, k));
    if np >= 8
        try_plot(fullfile(rundir, 'fft_ch1_mean.png'), @(fig) plot_fft_mean(fig, tx, fs, f0, f_max, ch1_col, [], 'CH1 TX'));
    end
end
if ~isempty(pcd)
    try_plot(fullfile(rundir, 'fft_ch2.png'), @(fig) plot_fft_ch2(fig, pcd(min(k, size(pcd,1)), :), fs, f0, f_max, ch2_col, emi_col, k));
    if np >= 8
        try_plot(fullfile(rundir, 'fft_ch2_mean.png'), @(fig) plot_fft_mean(fig, pcd, fs, f0, f_max, ch2_col, emi_col, 'CH2 PCD'));
    end
end
try_plot(fullfile(rundir, 'time_ch1_ch2.png'), @(fig) plot_time(fig, tx, pcd, fs, f0, k, ch1_col, ch2_col));
n_good = np;
if isfield(S, 'n_good') && isnumeric(S.n_good) && isscalar(S.n_good) && isfinite(S.n_good)
    n_good = max(n_good, double(S.n_good));
end
if n_good > 1
    try_plot(fullfile(rundir, 'pulse_sc_ic.png'), @(fig) plot_pulse(fig, S, tx, pcd, fs, f0, emi_col, rundir));
    % 主 Fig.6：3 MHz 窗求和蓝线 + 本 run target_db 黄带。覆盖 fig6_control.png。
    try
        pfc_plot_fig6_literature(rundir);
    catch
    end
end
end

function try_plot(fpath, drawfun)
fig = [];
ws = warning('off', 'MATLAB:uicontainer:ScrollableOnWithTextScaling');
restorer = onCleanup(@() warning(ws)); %#ok<NASGU>
try
    fig = figure('Visible', 'off', 'Color', 'w', 'IntegerHandle', 'off', ...
        'Position', [80 80 900 480]);
    cleaner = onCleanup(@() close_fig(fig)); %#ok<NASGU>
    drawfun(fig);
    dumped = false;
    try
        exportgraphics(fig, fpath, 'Resolution', 150);
        dumped = true;
    catch
    end
    if ~dumped
        saveas(fig, fpath);
    end
catch
end
end

function close_fig(fig)
try
    if ~isempty(fig) && isvalid(fig)
        close(fig);
    end
catch
end
end

function k = pick_rep_pulse(S, np)
k = max(1, np);
sc = vec_field(S, 'SCctrl');
if isempty(sc)
    return;
end
nd = pick_num(S, {'n_dummy'});
if ~(isfinite(nd) && nd >= 1)
    nd = 0;
end
i0 = min(np, max(1, nd + 1));
seg = sc(i0:min(numel(sc), np));
if isempty(seg)
    return;
end
snr = 20 * log10(max(seg, realmin));
[~, ii] = min(abs(snr - median(snr, 'omitnan')));
k = i0 + ii - 1;
end

function plot_fft_mean(fig, mat, fs, f0, f_max, col, emi_col, who)
np = size(mat, 1);
Ysum = [];
F = [];
for i = 1:np
    [F, Y] = pfc_spectrum(mat(i, :), fs);
    if i == 1
        Ysum = Y(:);
    else
        Ysum = Ysum + Y(:);
    end
end
db = 20 * log10(max(Ysum / np, 1e-18));
q = pfc_2f_quality(F, db, f0);
[fw, dbw] = clip_fft(F, db, f_max);
ax = axes(fig); %#ok<LAXES>
plot(ax, fw, dbw, 'Color', col, 'LineWidth', 1.0);
hold(ax, 'on');
if isfinite(f0) && f0 > 0
    for m = [1 2]
        fm = m * f0;
        if fm <= f_max
            xline(ax, fm, ':', 'Color', [0.45 0.45 0.45], 'LineWidth', 0.9);
        end
    end
    if 2 * f0 <= f_max
        yl = ylim(ax);
        text(ax, 2 * f0, yl(2), sprintf('2f=%.2f', 2 * f0), 'FontSize', 9, ...
            'HorizontalAlignment', 'center', 'VerticalAlignment', 'top', 'FontWeight', 'bold');
    end
end
if ~isempty(emi_col)
    for e = [2.85 4.18]
        if e <= f_max
            xline(ax, e, '--', 'Color', emi_col, 'LineWidth', 0.9);
        end
    end
end
grid(ax, 'on');
xlim(ax, [0 f_max]);
xlabel(ax, 'Frequency (MHz)');
ylabel(ax, 'dB  (20 log_{10} mean |FFT|)');
title(ax, sprintf('%s  平均谱 n=%d  %s', who, np, q.note));
end

function plot_fft_ch1(fig, y, fs, f0, f_max, col, k)
[F, ~, db] = pfc_spectrum(y, fs);
[f_pk, db_pk] = pfc_fft_peak_mhz(F, db, 0.3, 8);
[fw, dbw] = clip_fft(F, db, f_max);
ax = axes(fig); %#ok<LAXES>
plot(ax, fw, dbw, 'Color', col, 'LineWidth', 1.0);
hold(ax, 'on');
if isfinite(f0) && f0 > 0 && f0 <= f_max
    xline(ax, f0, '-', 'Color', [0.25 0.25 0.25], 'LineWidth', 1.0);
    yl = ylim(ax);
    text(ax, f0, yl(2), '  f0', 'FontSize', 9, 'Color', [0.25 0.25 0.25], ...
        'VerticalAlignment', 'top');
end
grid(ax, 'on');
xlim(ax, [0 f_max]);
xlabel(ax, 'Frequency (MHz)');
ylabel(ax, 'dB  (20 log_{10} |FFT|)');
if isfinite(f_pk)
    title(ax, sprintf('CH1 TX FFT  pulse %d  峰 %.3f MHz  %.0f dB', k, f_pk, db_pk));
else
    title(ax, sprintf('CH1 TX FFT  pulse %d  无有效峰', k));
end
end

function plot_fft_ch2(fig, y, fs, f0, f_max, col, emi_col, k)
[F, ~, db] = pfc_spectrum(y, fs);
q = pfc_2f_quality(F, db, f0);
[fw, dbw] = clip_fft(F, db, f_max);
ax = axes(fig); %#ok<LAXES>
plot(ax, fw, dbw, 'Color', col, 'LineWidth', 1.0);
hold(ax, 'on');
if isfinite(f0) && f0 > 0
    for m = [1 2]
        fm = m * f0;
        if fm <= f_max
            xline(ax, fm, ':', 'Color', [0.45 0.45 0.45], 'LineWidth', 0.9);
        end
    end
    yl = ylim(ax);
    if f0 <= f_max
        text(ax, f0, yl(2), 'f0', 'FontSize', 9, 'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'top', 'Color', [0.35 0.35 0.35]);
    end
    if 2 * f0 <= f_max
        text(ax, 2 * f0, yl(2), sprintf('2f=%.2f', 2 * f0), 'FontSize', 9, ...
            'HorizontalAlignment', 'center', 'VerticalAlignment', 'top', ...
            'Color', [0.15 0.15 0.15], 'FontWeight', 'bold');
    end
end
for e = [2.85 4.18]
    if e <= f_max
        xline(ax, e, '--', 'Color', emi_col, 'LineWidth', 0.9);
        yl = ylim(ax);
        text(ax, e, yl(1), ' 干扰', 'FontSize', 8, 'Color', emi_col, ...
            'HorizontalAlignment', 'left', 'VerticalAlignment', 'bottom', ...
            'Rotation', 90);
    end
end
grid(ax, 'on');
xlim(ax, [0 f_max]);
xlabel(ax, 'Frequency (MHz)');
ylabel(ax, 'dB  (20 log_{10} |FFT|)');
title(ax, sprintf('CH2 PCD FFT  pulse %d  %s', k, q.note));
end

function plot_time(fig, tx, pcd, fs, f0, k, ch1_col, ch2_col)
nsub = double(~isempty(tx)) + double(~isempty(pcd));
if nsub < 1
    return;
end
ii = 0;
if ~isempty(tx)
    ii = ii + 1;
    y = tx(min(k, size(tx, 1)), :);
    [tt, yw] = snippet(y, fs, f0, 'sine');
    ax = subplot(nsub, 1, ii, 'Parent', fig);
    plot(ax, tt, yw * 1e3, 'Color', ch1_col, 'LineWidth', 0.8);
    grid(ax, 'on');
    ylabel(ax, 'CH1 (mV)');
    pp = (max(y) - min(y)) * 1e3;
    title(ax, sprintf('CH1 TX  pulse %d  p-p=%.2f mV', k, pp));
    if isempty(pcd)
        xlabel(ax, 'Time (\mus)');
    end
end
if ~isempty(pcd)
    ii = ii + 1;
    y = pcd(min(k, size(pcd, 1)), :);
    [tt, yw] = snippet(y, fs, f0, 'broad');
    ax = subplot(nsub, 1, ii, 'Parent', fig);
    plot(ax, tt, yw * 1e3, 'Color', ch2_col, 'LineWidth', 0.6);
    grid(ax, 'on');
    ylabel(ax, 'CH2 (mV)');
    xlabel(ax, 'Time (\mus)');
    pp = (max(y) - min(y)) * 1e3;
    title(ax, sprintf('CH2 PCD  pulse %d  p-p=%.2f mV', k, pp));
end
end

function plot_pulse(fig, S, tx, pcd, fs, f0, emi_col, rundir) %#ok<INUSD>
if nargin < 8
    rundir = '';
end
% 文献 Fig.6：电压 / 2f 窗求和 dB / IC dB。不画峰/底。横轴是采集墙钟。
set(fig, 'Position', [50 50 1000 860]);
volt = vec_field(S, 'Vrealtime');
sc_sum = vec_field(S, 'RampSC');
ic = vec_field(S, 'RampIC');
sc = sc_sum;
if isempty(sc)
    sc = vec_field(S, 'SCctrl');
end
[~, ic0, n_dummy, tgt_db] = baseline_of(S, volt, sc, ic, rundir);
sc0_sum = pick_num(S, {'sc0_sum'});
if ~(isfinite(sc0_sum) && sc0_sum > 0) && ~isempty(sc_sum) && n_dummy >= 1
    sc0_sum = mean(sc_sum(1:min(n_dummy, numel(sc_sum))), 'omitnan');
end
np_axis = max([numel(volt), numel(sc), numel(ic), 1]);
[xx, tmode, xlab] = pfc_pulse_time_s(S, np_axis);
xx = xx(:);
[xL, xR] = pulse_xlim(xx, np_axis, tmode);
use_db = (~isempty(sc_sum) && isfinite(sc0_sum) && sc0_sum > 0) || ...
    (~isempty(sc) && isfinite(sc0_sum) && sc0_sum > 0) || ...
    (~isempty(ic) && isfinite(ic0) && ic0 > 0);
n = double(~isempty(volt)) + double(use_db || ~isempty(sc) || ~isempty(ic));
if n_dummy >= 1 && use_db
    n = double(~isempty(volt)) + double(~isempty(sc) || ~isempty(sc_sum)) + double(~isempty(ic));
end
if n < 1
    return;
end
ii = 0;
if ~isempty(volt)
    ii = ii + 1;
    ax = subplot(n, 1, ii, 'Parent', fig);
    plot(ax, xx(1:numel(volt)), volt(:), 'k.-', 'LineWidth', 1.0, 'MarkerSize', 8);
    hold(ax, 'on');
    shade_dummy_x(ax, xx, n_dummy, tmode);
    grid(ax, 'on');
    ylabel(ax, 'Voltage (mVpp)');
    xlim(ax, [xL xR]);
    title(ax, sprintf('Fig.6-style  n=%d  dummy=%d  target=%.1f\\pm0.4 dB  (SUM vs this-run yellow)', ...
        np_axis, n_dummy, tgt_db));
end
if n_dummy >= 1 && use_db && (~isempty(sc_sum) || ~isempty(sc)) && ~isempty(ic)
    ii = ii + 1;
    ax = subplot(n, 1, ii, 'Parent', fig);
    hold(ax, 'on');
    if ~isempty(sc_sum) && isfinite(sc0_sum) && sc0_sum > 0
        % 蓝线 = Fig.6 度量。橙带 = 本 run HIS 目标 ±0.4 dB（不是写死 4）。不画峰/底。
        sc_db = 10 * log10(max(sc_sum(:), realmin) / sc0_sum);
        xs = xx(1:numel(sc_db));
        if isfinite(tgt_db)
            patch(ax, [xL xR xR xL], ...
                [tgt_db-0.4 tgt_db-0.4 tgt_db+0.4 tgt_db+0.4], ...
                [1.00 0.86 0.72], 'EdgeColor', 'none', 'HandleVisibility', 'off');
            yline(ax, tgt_db, '-', 'Color', [0.85 0.35 0.10], 'LineWidth', 1.1, 'HandleVisibility', 'off');
        end
        h_dot = plot(ax, xs, sc_db, '.', 'Color', [0.55 0.70 0.90], 'MarkerSize', 9);
        h_avg = [];
        if numel(sc_db) >= 5
            h_avg = plot(ax, xs, movmean(sc_db, 5, 'omitnan'), 'b-', 'LineWidth', 1.6);
        end
        yline(ax, 0, ':', 'Color', [0.5 0.5 0.5], 'HandleVisibility', 'off');
        ylabel(ax, 'SC (dB re dummy)');
        shade_dummy_x(ax, xx, n_dummy, tmode);
        grid(ax, 'on');
        xlim(ax, [xL xR]);
        ylo = min([-2.2, min(sc_db)]);
        yhi = max([tgt_db + 2.5, max(sc_db)]);
        ylim(ax, [max(-4, ylo - 0.3), yhi + 0.4]);
        legs = {};
        hs = [];
        if ~isempty(h_dot)
            hs(end+1) = h_dot; %#ok<AGROW>
            legs{end+1} = '2f\\pm20 kHz sum (Fig.6 blue)'; %#ok<AGROW>
        end
        if ~isempty(h_avg)
            hs(end+1) = h_avg; %#ok<AGROW>
            legs{end+1} = '5-frame mean of SUM'; %#ok<AGROW>
        end
        if ~isempty(hs)
            legend(ax, hs, legs, 'Location', 'best');
        end
    else
        sc_db = 10 * log10(max(sc(:), realmin) / max(sc0_sum, realmin));
        plot(ax, xx(1:numel(sc)), sc_db, 'b.-', 'LineWidth', 1.0, 'MarkerSize', 8);
        if isfinite(tgt_db)
            yline(ax, tgt_db, '-', 'Color', [0.85 0.25 0.10], 'LineWidth', 1.2, 'HandleVisibility', 'off');
            yline(ax, tgt_db + 0.4, '--', 'Color', [0.85 0.25 0.10], 'LineWidth', 0.8, 'HandleVisibility', 'off');
            yline(ax, tgt_db - 0.4, '--', 'Color', [0.85 0.25 0.10], 'LineWidth', 0.8, 'HandleVisibility', 'off');
        end
        yline(ax, 0, ':', 'Color', [0.5 0.5 0.5], 'HandleVisibility', 'off');
        ylabel(ax, 'SC (dB re dummy)');
        legend(ax, {'SC  10 log_{10}(SC/SC_0)', sprintf('target %.1f \\pm 0.4 dB', tgt_db)}, ...
            'Location', 'best');
        shade_dummy_x(ax, xx, n_dummy, tmode);
        grid(ax, 'on');
        xlim(ax, [xL xR]);
    end

    ii = ii + 1;
    ax = subplot(n, 1, ii, 'Parent', fig);
    ic_db = 10 * log10(max(ic(:), realmin) / max(ic0, realmin));
    plot(ax, xx(1:numel(ic)), ic_db, 'r.-', 'LineWidth', 1.0, 'MarkerSize', 8);
    hold(ax, 'on');
    yline(ax, 0, ':', 'Color', [0.5 0.5 0.5]);
    shade_dummy_x(ax, xx, n_dummy, tmode);
    grid(ax, 'on');
    ylabel(ax, 'IC (dB re dummy)');
    xlabel(ax, xlab);
    xlim(ax, [xL xR]);
    legend(ax, {'IC  (2f–2.5f mean / floor)'}, 'Location', 'best');
    return;
end
if ~isempty(sc) || ~isempty(ic)
    ii = ii + 1;
    ax = subplot(n, 1, ii, 'Parent', fig);
    hold(ax, 'on');
    legs = {};
    if ~isempty(sc) && isfinite(sc0_sum) && sc0_sum > 0
        plot(ax, xx(1:numel(sc)), 10 * log10(max(sc(:), realmin) / sc0_sum), 'b.-');
        legs{end+1} = 'SC dB'; %#ok<AGROW>
    elseif ~isempty(sc)
        plot(ax, xx(1:numel(sc)), sc(:), 'b.-');
        legs{end+1} = 'SC'; %#ok<AGROW>
    end
    if ~isempty(ic) && isfinite(ic0) && ic0 > 0
        plot(ax, xx(1:numel(ic)), 10 * log10(max(ic(:), realmin) / ic0), 'r.-');
        legs{end+1} = 'IC dB'; %#ok<AGROW>
    elseif ~isempty(ic)
        plot(ax, xx(1:numel(ic)), ic(:), 'r.-');
        legs{end+1} = 'IC'; %#ok<AGROW>
    end
    grid(ax, 'on');
    xlim(ax, [xL xR]);
    xlabel(ax, xlab);
    if ~isempty(legs)
        legend(ax, legs, 'Location', 'best');
    end
end
end

function shade_dummy_x(ax, xx, n_dummy, tmode)
xx = double(xx(:));
n = numel(xx);
if ~(n_dummy >= 1 && n_dummy < n)
    return;
end
if strcmp(tmode, 'index')
    x0 = 0.5;
    x1 = n_dummy + 0.5;
else
    x0 = 0;
    x1 = xx(min(n_dummy, n));
    if ~isfinite(x1)
        return;
    end
end
if x1 <= x0
    x1 = x0 + 1;
end
yl = ylim(ax);
h = patch(ax, [x0 x1 x1 x0], [yl(1) yl(1) yl(2) yl(2)], ...
    [0.93 0.93 0.93], 'EdgeColor', 'none', 'HandleVisibility', 'off');
uistack(h, 'bottom');
ylim(ax, yl);
end

function [xL, xR] = pulse_xlim(xx, np, tmode)
if strcmp(tmode, 'index')
    xL = 1;
    xR = max(1, np);
    return;
end
xx = double(xx(:));
xx = xx(isfinite(xx));
xL = 0;
if isempty(xx)
    xR = max(1, np);
else
    xR = max(xx);
end
if ~(isfinite(xR) && xR > xL)
    xR = xL + 1;
end
end

function [sc0, ic0, n_dummy, tgt_db] = baseline_of(S, volt, sc, ic, rundir)
if nargin < 5
    rundir = '';
end
sc0 = pick_num(S, {'sc0'});
ic0 = pick_num(S, {'ic0'});
n_dummy = pick_num(S, {'n_dummy'});
% 橙带中心：先用闭环 10*log10(sc_tgt/sc0)，再才是 HIS 存的 target_db。
tgt_db = loop_target_db(S, rundir);
if ~isfinite(n_dummy) || n_dummy < 1
    n_dummy = dummy_len(volt);
end
n_dummy = max(0, min(n_dummy, max(numel(sc), numel(ic))));
if ~(isfinite(sc0) && sc0 > 0) && ~isempty(sc) && n_dummy >= 1
    sc0 = mean(sc(1:min(n_dummy, numel(sc))));
end
if ~(isfinite(ic0) && ic0 > 0) && ~isempty(ic) && n_dummy >= 1
    ic0 = mean(ic(1:min(n_dummy, numel(ic))));
end
end

function n = dummy_len(volt)
n = 0;
if isempty(volt)
    return;
end
v0 = volt(1);
n = find(abs(volt(:) - v0) > 8, 1, 'first');
if isempty(n)
    n = numel(volt);
else
    n = max(1, n - 1);
end
end

function [tx, pcd, fs, f0] = waves_from(S)
fs = pick_num(S, {'realFs'});
f0 = pick_num(S, {'freq_MHz', 'freq_mhz'});
if ~isfinite(f0) && isfield(S, 'params') && isstruct(S.params)
    f0 = pick_num(S.params, {'freq_mhz', 'dbg_freq'});
end
if ~isfinite(fs) && isfield(S, 'params') && isstruct(S.params)
    fs = pick_num(S.params, {'realFs', 'fs_target'});
end
tx = as_rows(first_field(S, {'txmat', 'chTx'}));
pcd = as_rows(first_field(S, {'datamat', 'chA', 'chPcd'}));
end

function M = as_rows(x)
if isempty(x)
    M = [];
    return;
end
x = double(x);
if isvector(x)
    M = x(:).';
else
    M = x;
end
end

function v = first_field(S, names)
v = [];
for i = 1:numel(names)
    k = names{i};
    if isstruct(S) && isfield(S, k) && ~isempty(S.(k))
        v = S.(k);
        return;
    end
end
end

function v = loop_target_db(S, rundir)
%LOOP_TARGET_DB 黄带中心 = 当时闭环用的 dB，不是画图函数自己的缺省。
if nargin < 2
    rundir = '';
end
v = NaN;
sc0 = pick_num(S, {'sc0'});
sct = pick_num(S, {'sc_tgt'});
if isfinite(sc0) && sc0 > 0 && isfinite(sct) && sct > 0
    v = 10 * log10(sct / sc0);
end
if ~isfinite(v)
    v = pick_num(S, {'target_db'});
end
if ~isfinite(v) && isfield(S, 'params') && isstruct(S.params)
    v = pick_num(S.params, {'target_db'});
end
if ~isfinite(v)
    v = target_from_params_txt(rundir);
end
if ~isfinite(v)
    v = 2;  % 与 pfc_prefs 默认一致，不是 3/4
end
end

function v = target_from_params_txt(rundir)
%TARGET_FROM_PARAMS_TXT 从本次 run 的 params.txt 读 target_db（HIS 当时设定）。
v = NaN;
if nargin < 1 || strlength(string(rundir)) < 1
    return;
end
fp = fullfile(char(string(rundir)), 'params.txt');
if ~isfile(fp)
    return;
end
fid = fopen(fp, 'r');
if fid < 0
    return;
end
cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
while true
    ln = fgetl(fid);
    if ~ischar(ln)
        break;
    end
    tok = regexp(strtrim(ln), '^target_db\s*=\s*([-+0-9.eE]+)', 'tokens', 'once');
    if ~isempty(tok)
        x = str2double(tok{1});
        if isfinite(x)
            v = x;
        end
        return;
    end
end
end

function v = pick_num(S, names)
v = NaN;
for i = 1:numel(names)
    k = names{i};
    if ~isstruct(S) || ~isfield(S, k)
        continue;
    end
    x = S.(k);
    if isnumeric(x) && isscalar(x) && isfinite(x)
        v = double(x);
        return;
    end
end
end

function v = vec_field(S, name)
v = [];
if isstruct(S) && isfield(S, name) && ~isempty(S.(name)) && isnumeric(S.(name))
    v = double(S.(name)(:));
end
end

function f_max = fft_cap(fs, f0)
nyq = fs / 2 / 1e6;
if isfinite(f0) && f0 > 0
    f_max = min(nyq, max(8, 5 * f0));
else
    f_max = min(nyq, 8);
end
end

function [fw, dbw] = clip_fft(F, db, f_max)
fw = F(:) / 1e6;
dbw = db(:);
keep = fw <= f_max + 1e-9;
if ~any(keep)
    keep(:) = true;
end
fw = fw(keep);
dbw = dbw(keep);
end

function [tt, yw] = snippet(y, fs, f0, kind)
% 短窗：正弦截约 16 个驱动周期；PCD 略宽一点仍是「片段」不是整段记录。
y = double(y(:).');
n = numel(y);
if strcmp(kind, 'sine') && isfinite(f0) && f0 > 0
    nwin = max(64, round(16 / (f0 * 1e6) * fs));
else
    nwin = max(64, round(80e-6 * fs));   % PCD 约 80 µs，能看见猝发局部
end
nwin = min(n, max(2, nwin));
[~, ipk] = max(abs(y));
half = floor(nwin / 2);
i0 = ipk - half;
i1 = i0 + nwin - 1;
if i0 < 1
    i0 = 1;
    i1 = min(n, nwin);
elseif i1 > n
    i1 = n;
    i0 = max(1, n - nwin + 1);
end
ys = y(i0:i1);
MAXP = 1600;
step = max(1, ceil(numel(ys) / MAXP));
ti = 1:step:numel(ys);
tt = (i0 + ti - 2) / fs * 1e6;
yw = ys(ti);
end
