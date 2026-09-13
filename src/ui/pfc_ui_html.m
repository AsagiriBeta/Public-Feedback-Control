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
    'waveform',   @(y, fs, f0, nm) html_waveform(fig, y, fs, f0, nm), ...
    'trend',      @(k, sc, ic, v, xmax, ymax) pfc_ui_push(fig, struct('cmd', 'trend', ...
        'k', k, 'sc', sc, 'ic', ic, 'volt', v, 'xmax', xmax, 'ymax', ymax)));
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

function [f_pk, db_pk] = html_waveform(fig, y, fs, f0, nm)
%HTML_WAVEFORM 时域 + FFT 推给前端，并返回谱峰 (f_pk, db_pk)。
% 上屏前必须降采样：屏幕只有几百像素宽，~1500 点与 4 万点肉眼无区别，
% 但 JSON 体积从 ~800 KB 降到 ~30 KB（实测 63 ms/帧 -> 2.5 ms/帧）。
MAXP = 1200;
f_pk = NaN;
db_pk = NaN;
y = double(y(:).');
if isempty(y) || ~isfinite(fs) || fs <= 0
    return;
end
n = numel(y);
step = max(1, ceil(n / MAXP));
idx = 1:step:n;

[F, ~, db] = pfc_spectrum(y, fs);
[f_pk, db_pk] = pfc_fft_peak_mhz(F, db, 0.3, 8);
m = numel(F);
fstep = max(1, ceil(m / MAXP));
fi = 1:fstep:m;

S = struct('cmd', 'waveform', 'name', char(string(nm)), ...
    'dt_us', (idx - 1) / fs * 1e6, ...
    'y', y(idx), ...
    'f', F(fi) / 1e6, ...
    'db', db(fi), ...
    'f0', f0, ...
    'marks', marks_for(f0));
pfc_ui_push(fig, S);
end

function mk = marks_for(f0)
% 0.5f / f0 / 1.5f / 2f(SC) / 2.5f / 3f；只有 2f 用强调色加粗
mults = [0.5 1 1.5 2 2.5 3];
mk = struct('f', num2cell(mults * f0), 'main', num2cell(mults == 2));
end
