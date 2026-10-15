function pcd_debug_run(ui)
%PCD_DEBUG_RUN 未打微泡的连续调试采集（界面无关）。
% ui 为 UI 适配层（实现见 pcd_ui_html，约定接口见 pcd_ui_check）。
ui = pcd_ui_check(ui);

S = ui.raw();
[freq, volt] = ui.debugfv();

opts = struct();
opts.ui = ui;
opts.outdir = ui.outdir();
opts.raw = S;
opts.freq_mhz = freq;
opts.volt_mVpp = volt;
opts.prf_hz = pick(S, 'prf_hz', 2);
L = pcd_param_limits();
opts.n_cycle = pick(S, 'n_cycle', L.n_cycle_default);
opts.npts = pick(S, 'npts', L.npts_default);

% 频率/电压必须由界面明确给出（空框 / 非法值时 ui.debugfv() 返回 NaN）。
% 这里报错，不兜底成 1.5 MHz / 20 mVpp —— 兜底等于在用户没填的时候照样开超声。
if ~isfinite(opts.freq_mhz) || opts.freq_mhz <= 0
    error('PCD:debugRun:params', '请先填写采集框的 频率 (MHz)。');
end
if ~isfinite(opts.volt_mVpp) || opts.volt_mVpp <= 0
    error('PCD:debugRun:params', '请先填写采集框的 电压 (mVpp)。');
end
if ~isfinite(opts.prf_hz) || opts.prf_hz <= 0, opts.prf_hz = 2; end
% 与正式实验同一套 npts / n_cycle 上下限（pcd_param_limits），避免调试 40k、
% 实验 50k、界面又能键入 400000 三套数字。
if ~isfinite(opts.n_cycle)
    opts.n_cycle = L.n_cycle_default;
end
opts.n_cycle = max(L.n_cycle_min, min(round(opts.n_cycle), L.n_cycle_max));
if ~isfinite(opts.npts)
    opts.npts = L.npts_default;
end
opts.npts = max(L.npts_min, min(round(opts.npts), L.npts_max));

pcd_debug_no_mb(opts);
end

function v = pick(S, k, def)
v = def;
if isstruct(S) && isfield(S, k)
    x = S.(k);
    if isnumeric(x) && isscalar(x) && isfinite(x)
        v = double(x);
    end
end
end
