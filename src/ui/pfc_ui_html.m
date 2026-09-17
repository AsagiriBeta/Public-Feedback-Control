function ui = pfc_ui_html(fig)
%PFC_UI_HTML 界面的「UI 适配层」：把界面操作收敛成一组函数句柄交给算法层。
% 参数、状态、波形、点图都通过 uihtml 的 Data 通道推给前端（web/ 下的 Alpine 页面）。
% 约定接口见 pfc_ui_check；算法层只依赖这层，不依赖 uihtml 或任何具体控件。
ui = struct( ...
    'params',     @() pfc_fus_params(getappdata(fig, 'pfc_params')), ...
    'raw',        @() getappdata(fig, 'pfc_params'), ...
    'debugfv',    @() html_debugfv(fig), ...
    'outdir',     @() html_outdir(fig), ...
    'clearTrend', @() pfc_ui_push(fig, struct('cmd', 'clearTrend')), ...
    'status',     @(s) pfc_ui_push(fig, struct('cmd', 'status', 'text', char(string(s)))), ...
    'countdown',  @(remain, total) html_countdown(fig, remain, total), ...
    'waveform',   @(varargin) html_waveform(fig, varargin{:}), ...
    'trend',      @(k, sc, ic, v, xmax, ymax) pfc_ui_push(fig, struct('cmd', 'trend', ...
        'k', k, 'sc', sc, 'ic', ic, 'volt', v, 'xmax', xmax, 'ymax', ymax)));
end

function html_countdown(fig, remain, total)
% 墙钟倒计时推给网页。remain/total 非法则关掉（实验结束 / 未开超声）。
on = nargin >= 3 && isfinite(remain) && remain >= 0 && isfinite(total) && total > 0;
if ~on
    pfc_ui_push(fig, struct('cmd', 'countdown', 'on', false));
    return;
end
pfc_ui_push(fig, struct('cmd', 'countdown', 'on', true, ...
    'remain_s', double(remain), 'total_s', double(total)));
end

function [f, v] = html_debugfv(fig)
% 采集面板的频率/电压，两个独立输出（调用方普遍写成 [freq, volt] = ui.debugfv()）。
% 缺失或非法一律返回 NaN，由调用方（pfc_oneshot / pfc_debug_run）报错 ——
% 这里绝不兜底默认值，否则界面上把电压框清空后，实验会静默按 20 mVpp 开超声，
% 与 pfc_fus_params「必填项缺失就报错」的原则正好相反。
S = getappdata(fig, 'pfc_params');
f = req_num(S, 'dbg_freq');
v = req_num(S, 'dbg_volt');
end

function v = req_num(S, k)
v = NaN;
if isstruct(S) && isfield(S, k)
    x = S.(k);
    if isnumeric(x) && isscalar(x) && isfinite(x)
        v = double(x);
    end
end
end

function d = html_outdir(fig)
S = getappdata(fig, 'pfc_params');
d = '';
if isstruct(S) && isfield(S, 'directory')
    d = strtrim(char(string(S.directory)));
end
if isempty(d)
    d = fullfile(pfc_root(), 'data');
    if isstruct(S)
        S.directory = d;
        setappdata(fig, 'pfc_params', S);
        pfc_ui_push(fig, struct('cmd', 'params', 'params', S));
    end
end
if ~isfolder(d)
    try, mkdir(d); catch, end
end
end

function [f_pk, db_pk] = html_waveform(fig, y, fs, f0, nm, opts)
%HTML_WAVEFORM 时域（+ 可选 FFT）推给前端，并返回谱峰 (f_pk, db_pk)。
% 谱分析始终用整段原始记录；上屏才截窗/降采样，采集 npts / WORD/RAW 不变。
%
%   html_waveform(fig, y, fs, f0, name)
%   html_waveform(fig, y, fs, f0, name, opts)
% opts.ch   'tx'|'pcd'   前端时域槽（缺省从 name 猜：CH2/PCD→pcd，否则 tx）
% opts.fft  true|false   是否附带频谱（缺省 true）。CH1 / CH2 各推到前端自己的
%                        FFT 图（fftTx / fftPcd），不再共用一张谱。
% opts.kind 'sine'|'broad'  时域窗：正弦截 ~16 周期；宽带/噪声整段降采样。
%
% 时域窗为什么要分两种：
%   TX 正弦：调试 CW 几万点里叠几百个周期，整段再抽点会抽成一条实心带，
%            所以截 ~16 个驱动周期（约 10.7 µs @ 1.5 MHz）再降采样。
%   PCD / 无微泡底噪：没有周期可截。若仍按 16 周期去围 max(|y|)，会放大
%            一个随机毛刺，横轴变成几纳秒、幅度 ±1 mV，看起来像坏了。
%            宽带一律整段记录降采样（≤ MAXP 点），一眼能看到猝发是否在窗内。
% f0 约定 MHz、fs 约定 Hz；若明显按 Hz / MSa/s 误传，这里先折回来，避免
% 16/1.5e6 → nwin=2 → 横轴只剩一个采样间隔（@125 MSa/s 正好 ~8 ns）。
% FFT：Nyquist 常到 20–30 MHz，横轴只放到 min(Nyquist, max(8, 5*f0)) MHz。
if nargin < 5 || isempty(nm), nm = ''; end
if nargin < 6 || isempty(opts), opts = struct(); end
if ~isstruct(opts)
    opts = struct('ch', char(string(opts)));
end
MAXP = 1200;
FMAX_MIN = 8;        % MHz；缺 f0 或 5*f0 更小时至少看到 8 MHz（本实验室 PCD~3）
FMAX_FO_MULT = 5;    % 横轴至少盖到 ~5*f0，谐波标记才不会贴右边
f_pk = NaN;
db_pk = NaN;
y = double(y(:).');
fs = fs_as_hz(fs);
if isempty(y) || ~isfinite(fs) || fs <= 0
    return;
end
f0 = f0_as_mhz(f0);
ch = infer_ch(nm, opts);
kind = infer_kind(ch, opts);
do_fft = true;
if isfield(opts, 'fft') && ~isempty(opts.fft)
    do_fft = logical(opts.fft);
end

% --- 谱：整段记录，峰位给调用方；上屏另截频窗 ---
if do_fft
    [F, ~, db] = pfc_spectrum(y, fs);
    [f_pk, db_pk] = pfc_fft_peak_mhz(F, db, 0.3, 8);
end

% --- 时域展示窗：正弦先截连续短段再抽点；宽带整段抽点（顺序不能反） ---
[dt_us, yw] = time_view(y, fs, f0, kind, MAXP);
pp_mV = (max(y) - min(y)) * 1e3;

S = struct('cmd', 'waveform', ...
    'name', char(string(nm)), ...
    'ch', ch, ...
    'dt_us', dt_us, ...
    'y', yw, ...
    'pp_mV', pp_mV);
if do_fft
    nyq_mhz = fs / 2 / 1e6;
    if isfinite(f0)
        f_max = min(nyq_mhz, max(FMAX_MIN, FMAX_FO_MULT * f0));
    else
        f_max = min(nyq_mhz, FMAX_MIN);
    end
    f_mhz = F / 1e6;
    keep = f_mhz <= f_max + 1e-9;
    if ~any(keep)
        keep(:) = true;
    end
    fw = f_mhz(keep);
    dbw = db(keep);
    m = numel(fw);
    fstep = max(1, ceil(m / MAXP));
    si = 1:fstep:m;
    S.f = fw(si);
    S.db = dbw(si);
    S.f0 = f0;
    S.f_max = f_max;
    S.marks = marks_for(f0, ch);
    S.fft_of = char(string(nm));
    S.fft_title = fft_title_for(ch, f0, f_pk, db_pk, F, db);
end
pfc_ui_push(fig, S);
end

function [dt_us, yw] = time_view(y, fs, f0, kind, MAXP)
n = numel(y);
broad = any(strcmp(kind, {'broad', 'pcd', 'noise'}));
if broad
    % 整段降采样：无微泡 PCD 是底噪，截 16 个「周期」只会画出一个毛刺
    i0 = 1;
    i1 = n;
else
    N_CYC = 16;
    MIN_US = 8;          % 最短 8 µs，单位就算再错也不会只剩几个点
    MIN_N = 64;
    if isfinite(f0) && f0 > 0
        t_show_us = max(N_CYC / f0, MIN_US);   % f0 单位 MHz → 周期 = 1/f0 µs
    else
        t_show_us = 10;
    end
    nwin = max(MIN_N, round(t_show_us * 1e-6 * fs));
    nwin = min(n, max(2, nwin));
    if n <= round(1.25 * nwin)
        % 已经 ≤~20 个周期，再截只会丢掉有效波形
        i0 = 1;
        i1 = n;
    else
        % 取 |y| 最大附近一段，避免猝发触发前的零电平占满窗口
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
    end
end
ys = y(i0:i1);
ns = numel(ys);
step = max(1, ceil(ns / MAXP));
ti = 1:step:ns;
dt_us = (i0 + ti - 2) / fs * 1e6;
yw = ys(ti);
end

function f0 = f0_as_mhz(f0)
% 实验室 FUS ~1–3 MHz。>20 还带 ≥1000，当作 Hz 误传（1.5e6 → 1.5）。
if ~(isscalar(f0) && isfinite(f0) && f0 > 0)
    f0 = NaN;
    return;
end
if f0 > 20 && f0 >= 1e3
    f0 = f0 / 1e6;
end
end

function fs = fs_as_hz(fs)
% 采样率约定 Hz。40 / 125 这种小数当作 MSa/s 误传。
if ~(isscalar(fs) && isfinite(fs) && fs > 0)
    fs = NaN;
    return;
end
if fs < 1e3
    fs = fs * 1e6;
end
end

function ch = infer_ch(nm, opts)
ch = '';
if isstruct(opts) && isfield(opts, 'ch') && ~isempty(opts.ch)
    ch = lower(strtrim(char(string(opts.ch))));
end
if any(strcmp(ch, {'tx', 'pcd'}))
    return;
end
s = lower(char(string(nm)));
if contains(s, 'pcd') || contains(s, 'ch2')
    ch = 'pcd';
else
    ch = 'tx';
end
end

function k = infer_kind(ch, opts)
if isstruct(opts) && isfield(opts, 'kind') && ~isempty(opts.kind)
    k = lower(strtrim(char(string(opts.kind))));
    return;
end
if strcmp(ch, 'pcd')
    k = 'broad';
else
    k = 'sine';
end
end

function mk = marks_for(f0, ch)
% CH1：f0 及谐波淡虚线。CH2：只标 f0 / 2f（1.5 MHz 时 2f=3.0），
% 另两条琥珀线是实验室固定干扰 2.85、4.18 MHz，不是二次谐波。
blank = struct('f', {}, 'main', {}, 'kind', {}, 'label', {});
if ~(isscalar(f0) && isfinite(f0) && f0 > 0)
    mk = blank;
    return;
end
if nargin >= 2 && strcmp(ch, 'pcd')
    % 3 MHz（2f/SC）不发竖线，只在前端写 SC 字，避免白线盖住峰。
    mk = struct('f', {f0, 2.2 * f0, 2.85, 4.18}, ...
        'main', {false, false, false, false}, ...
        'kind', {'harm', 'ic', 'emi', 'emi'}, ...
        'label', {'f0', 'IC', '干扰', '干扰'});
    return;
end
mults = [0.5 1 1.5 2.5 3];
labs = {'', 'f0', '', '', '3f'};
mk = struct('f', num2cell(mults * f0), 'main', num2cell(mults == 2), ...
    'kind', repmat({'harm'}, 1, numel(mults)), 'label', labs);
end

function ttl = fft_title_for(ch, f0, f_pk, db_pk, F, db)
% CH1 报全局峰（驱动在不在 1.5 MHz）；CH2 报 2f 而不是 4.18 全局峰。
if strcmp(ch, 'pcd') && nargin >= 6 && ~isempty(F)
    q = pfc_2f_quality(F, db, f0);
    ttl = sprintf('频谱  FFT  ·  CH2  %s', q.note);
    return;
end
if isfinite(f_pk) && isfinite(db_pk)
    ttl = sprintf('频谱  FFT  ·  CH1  峰 %.3f MHz  %.0f dB', f_pk, db_pk);
    if isfinite(f0) && abs(f_pk - f0) > 0.25
        ttl = [ttl '  【≠f0，回读不是驱动】'];
    end
else
    ttl = '频谱  FFT  ·  CH1  无有效峰';
end
end
