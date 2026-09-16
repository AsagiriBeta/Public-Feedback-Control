function pfc_plot_fig6_literature(rundir)
%PFC_PLOT_FIG6_LITERATURE  Fig.6 画法，频点用本实验室的，不照搬 4.5 MHz。
%
%   画法跟 Chien 一样：Y=|FFT|，谐波 ±20 kHz 求和，10*log10(相对假超声)，
%   黄带中心 = 闭环真阈值 10*log10(sc_tgt/sc0)，再缺才用 raw/params/params.txt
%   的 target_db；不是写死 3 或 4 dB。带宽固定 ±0.4 dB。缺目标时退回 2（prefs）。
%   频点不跟他们：他们 PCD ~4.7 MHz 所以听 3f=4.5 MHz；我们 PCD 听 2f=3.0 MHz。
%   IC 用 2f～2.5f / 参考底，不用他们的 3.3 MHz 窄窗。
%   横轴是入库墙钟秒（USB≠PRF，不能用 pulse #）。不画峰/底绿线。
%   不伪造旧数据进黄带。不改 WORD/RAW。
if nargin < 1 || strlength(string(rundir)) < 1
    error('pfc_plot_fig6_literature:rundir', '需要 run 目录');
end
rundir = char(string(rundir));
rawfile = fullfile(rundir, 'raw.mat');
if ~isfile(rawfile)
    error('pfc_plot_fig6_literature:raw', '没有 raw.mat：%s', rawfile);
end
S = load(rawfile);
[volt, sc, ic, n_dummy, tgt_db, f0, metric] = lit_series(S, rundir);
f2 = 2 * f0;
write_fig(fullfile(rundir, 'fig6_literature.png'), volt, sc, ic, n_dummy, tgt_db, f2, metric, S);
copyfile(fullfile(rundir, 'fig6_literature.png'), fullfile(rundir, 'fig6_control.png'));
old3f = fullfile(rundir, 'fig6_literature_3f.png');
if isfile(old3f)
    delete(old3f);
end
end

function [volt, sc, ic, n_dummy, tgt_db, f0, metric] = lit_series(S, rundir)
volt = vec_of(S, 'Vrealtime');
pcd = as_rows(first_of(S, {'datamat', 'chA', 'chPcd'}));
fs = num_of(S, {'realFs'});
f0 = num_of(S, {'freq_mhz', 'freq_MHz'});
if ~isfinite(f0) && isfield(S, 'params') && isstruct(S.params)
    f0 = num_of(S.params, {'freq_mhz', 'dbg_freq'});
end
if ~isfinite(fs) && isfield(S, 'params') && isstruct(S.params)
    fs = num_of(S.params, {'realFs', 'fs_target'});
end
if ~(isfinite(f0) && f0 > 0)
    f0 = 1.5;
end
f0_hz = f0 * 1e6;
bw = 20e3;
np = size(pcd, 1);
sc = nan(np, 1);
ic = nan(np, 1);
if np >= 1 && isfinite(fs) && fs > 0
    for i = 1:np
        [F, Y] = pfc_spectrum(pcd(i, :), fs);
        [sc(i), ~, ~, ~, M] = pfc_band_energy(Y, F, f0_hz, bw);
        ic(i) = M.ic_ctrl;       % 2f～2.5f 均值 / 参考底
    end
else
    sc = vec_of(S, 'RampSC');
    ic = vec_of(S, 'RampIC');
end
n_dummy = num_of(S, {'n_dummy'});
% 黄带优先用闭环真阈值 10*log10(sc_tgt/sc0)；再才是存盘的 target_db / params.txt。
% 缺目标时才退回 2（与 prefs 缺省一致），绝不写死 3 或 4。
tgt_db = loop_target_db(S, rundir);
if ~(isfinite(n_dummy) && n_dummy >= 1)
    n_dummy = dummy_len(volt);
end
n_dummy = max(0, min(n_dummy, max([numel(volt), numel(sc), 1])));
% 旧 raw 没写 ctrl_metric 时，固件实际控的是峰/底，不能默认成窗求和。
metric = pfc_ctrl_metric(S, 'recorded');
end

function write_fig(fpath, volt, sc, ic, n_dummy, tgt_db, f2_mhz, metric, S)
if nargin < 8 || isempty(metric)
    metric = '2f_peak_over_floor';
end
if nargin < 9 || ~isstruct(S)
    S = struct();
end
np = max([numel(volt), numel(sc), numel(ic), 1]);
sc0 = dummy_mean(sc, n_dummy);
ic0 = dummy_mean(ic, n_dummy);
sc_db = db_re(sc, sc0);
ic_db = db_re(ic, ic0);
[xx, tmode, xlab] = pfc_pulse_time_s(S, np);
xx = xx(:);
if ~(isfinite(f2_mhz) && f2_mhz > 0)
    f2_mhz = 3.0;
end
loop_sum = strcmp(metric, '2f_window_sum');
[xL, xR] = time_xlim(xx, np, tmode);

fig = figure('Visible', 'off', 'Color', 'w', 'IntegerHandle', 'off', ...
    'Position', [40 40 980 820]);
cleaner = onCleanup(@() close_soft(fig)); %#ok<NASGU>

if loop_sum
    loop_txt = 'loop=window sum';
else
    loop_txt = 'loop=peak/floor (blue SUM not controlled)';
end
tl = tiledlayout(fig, 3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
title(tl, sprintf(['Fig. 6  lab 2f=%.2f MHz (not 4.5)  dummy=%d  ', ...
    'yellow = this run target %.1f \\pm 0.4 dB  %s'], ...
    f2_mhz, n_dummy, tgt_db, loop_txt), 'FontSize', 11, 'FontWeight', 'bold');

ax1 = nexttile(tl);
hold(ax1, 'on');
if ~isempty(volt)
    plot(ax1, xx(1:numel(volt)), volt(:), 'k.-', 'LineWidth', 1.0, 'MarkerSize', 7);
end
grid(ax1, 'on');
ylabel(ax1, 'Voltage (mVpp)');
xlim(ax1, [xL xR]);
if ~isempty(volt)
    ylim(ax1, [0, max(volt(:)) * 1.12]);
end
shade_dummy_x(ax1, xx, n_dummy, tmode);
title(ax1, 'Voltage');
set(ax1, 'FontSize', 9, 'FontWeight', 'bold', 'Box', 'on');

ax2 = nexttile(tl);
hold(ax2, 'on');
if isfinite(tgt_db)
    patch(ax2, [xL xR xR xL], ...
        [tgt_db-0.4 tgt_db-0.4 tgt_db+0.4 tgt_db+0.4], ...
        [1.00 0.92 0.55], 'EdgeColor', 'none', 'HandleVisibility', 'off');
    yline(ax2, tgt_db, '-', 'Color', [0.85 0.55 0.05], 'LineWidth', 1.0, ...
        'HandleVisibility', 'off');
end
yline(ax2, 0, ':', 'Color', [0.55 0.55 0.55], 'HandleVisibility', 'off');
h_sc = plot(ax2, xx(1:numel(sc_db)), sc_db, 'b.-', 'LineWidth', 0.9, 'MarkerSize', 8);
grid(ax2, 'on');
ylabel(ax2, 'SC (dB re dummy)');
xlim(ax2, [xL xR]);
ylo = min([-1.2, min(sc_db, [], 'omitnan')]);
yhi = max([tgt_db + 1.6, max(sc_db, [], 'omitnan')]);
if ~isfinite(ylo), ylo = -2; end
if ~isfinite(yhi), yhi = tgt_db + 2; end
ylim(ax2, [ylo - 0.2, yhi + 0.3]);
shade_dummy_x(ax2, xx, n_dummy, tmode);
title(ax2, sprintf('Blue: %.2f MHz (2f) \\pm20 kHz sum |FFT|   (not 4.5 MHz)', f2_mhz));
if loop_sum
    sum_leg = sprintf('window sum = loop  SC_0=%.4g', sc0);
else
    sum_leg = sprintf('window sum (Fig.6 blue; NOT loop)  SC_0=%.4g', sc0);
end
legend(ax2, h_sc, sum_leg, 'Location', 'best');
set(ax2, 'FontSize', 9, 'FontWeight', 'bold', 'Box', 'on');

ax3 = nexttile(tl);
hold(ax3, 'on');
yline(ax3, 0, ':', 'Color', [0.55 0.55 0.55], 'HandleVisibility', 'off');
h_ic = plot(ax3, xx(1:numel(ic_db)), ic_db, 'r.-', 'LineWidth', 0.9, 'MarkerSize', 8);
grid(ax3, 'on');
ylabel(ax3, 'IC (dB)');
xlabel(ax3, xlab);
xlim(ax3, [xL xR]);
shade_dummy_x(ax3, xx, n_dummy, tmode);
title(ax3, 'IC = 2f–2.5f mean / floor');
legend(ax3, h_ic, sprintf('10 log_{10}(IC/IC_0),  IC_0=%.4g', ic0), ...
    'Location', 'best');
set(ax3, 'FontSize', 9, 'FontWeight', 'bold', 'Box', 'on');
linkaxes([ax1 ax2 ax3], 'x');

if ~isempty(volt)
    khold = find(volt(:) >= 1100, 1, 'first');
else
    khold = [];
end
if isempty(khold)
    khold = n_dummy + 1;
end
ih = max(1, khold):min(np, numel(sc_db));
fprintf(['Fig.6  2f=%.2f MHz (not 4.5)  yellow=%.1f+/-0.4 dB  x=%s\n', ...
    '  2f-sum 10log late med=%.2f mean=%.2f max=%.2f dB\n'], ...
    f2_mhz, tgt_db, tmode, ...
    median(sc_db(ih), 'omitnan'), mean(sc_db(ih), 'omitnan'), max(sc_db(ih)));

exportgraphics(fig, fpath, 'Resolution', 180);
end

function shade_dummy_x(ax, xx, n_dummy, tmode)
xx = double(xx(:));
n = numel(xx);
if ~(n_dummy >= 1 && n_dummy < n)
    return;
end
x1 = xx(min(n_dummy, n));
if strcmp(tmode, 'index')
    x0 = 0.5;
    x1 = n_dummy + 0.5;
else
    x0 = 0;
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

function [xL, xR] = time_xlim(xx, np, tmode)
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

function db = db_re(x, x0)
x = double(x(:));
if ~(isfinite(x0) && x0 > 0)
    db = nan(size(x));
    return;
end
db = 10 * log10(max(x, realmin) / x0);
end

function m = dummy_mean(x, n_dummy)
x = double(x(:));
n = min(max(1, n_dummy), numel(x));
if n < 1 || isempty(x)
    m = NaN;
    return;
end
m = mean(x(1:n), 'omitnan');
end

function n = dummy_len(volt)
n = 0;
if isempty(volt)
    return;
end
v0 = volt(1);
k = find(abs(volt(:) - v0) > 8, 1, 'first');
if isempty(k)
    n = numel(volt);
else
    n = max(1, k - 1);
end
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

function v = first_of(S, names)
v = [];
for i = 1:numel(names)
    k = names{i};
    if isstruct(S) && isfield(S, k) && ~isempty(S.(k))
        v = S.(k);
        return;
    end
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

function v = loop_target_db(S, rundir)
%LOOP_TARGET_DB 黄带中心 = 当时闭环用的 dB，不是画图函数自己的缺省。
v = NaN;
sc0 = num_of(S, {'sc0'});
sct = num_of(S, {'sc_tgt'});
if isfinite(sc0) && sc0 > 0 && isfinite(sct) && sct > 0
    v = 10 * log10(sct / sc0);
end
if ~isfinite(v)
    v = num_of(S, {'target_db'});
end
if ~isfinite(v) && isfield(S, 'params') && isstruct(S.params)
    v = num_of(S.params, {'target_db'});
end
if ~isfinite(v)
    v = target_from_params_txt(rundir);
end
if ~isfinite(v)
    v = 2;  % 与 pfc_prefs / 界面默认一致，不是 3/4
end
end

function v = num_of(S, names)
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

function v = vec_of(S, name)
v = [];
if isstruct(S) && isfield(S, name) && ~isempty(S.(name)) && isnumeric(S.(name))
    v = double(S.(name)(:));
end
end

function close_soft(fig)
try
    if ~isempty(fig) && isvalid(fig)
        close(fig);
    end
catch
end
end
