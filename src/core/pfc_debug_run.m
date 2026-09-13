function pfc_debug_run(ui)
%PFC_DEBUG_RUN 未打微泡的连续调试采集（界面无关）。
% ui 为 UI 适配层（实现见 pfc_ui_html，约定接口见 pfc_ui_check）。
ui = pfc_ui_check(ui);

S = ui.raw();
[freq, volt] = ui.debugfv();

opts = struct();
opts.ui = ui;
opts.outdir = ui.outdir();
opts.freq_mhz = freq;
opts.volt_mVpp = volt;
opts.prf_hz = pick(S, 'prf_hz', 2);
opts.n_cycle = pick(S, 'n_cycle', 400);
opts.npts = pick(S, 'npts', 40000);

% 频率/电压必须由界面明确给出（空框 / 非法值时 ui.debugfv() 返回 NaN）。
% 这里报错，不兜底成 1.5 MHz / 20 mVpp —— 兜底等于在用户没填的时候照样开超声。
if ~isfinite(opts.freq_mhz) || opts.freq_mhz <= 0
    error('PFC:debugRun:params', '请先填写采集框的 频率 (MHz)。');
end
if ~isfinite(opts.volt_mVpp) || opts.volt_mVpp <= 0
    error('PFC:debugRun:params', '请先填写采集框的 电压 (mVpp)。');
end
if ~isfinite(opts.prf_hz) || opts.prf_hz <= 0, opts.prf_hz = 2; end
if ~isfinite(opts.n_cycle) || opts.n_cycle < 1, opts.n_cycle = 400; end
if ~isfinite(opts.npts) || opts.npts < 1024, opts.npts = 40000; end
opts.npts = min(opts.npts, 40000);
opts.n_cycle = min(opts.n_cycle, 800);

pfc_debug_no_mb(opts);
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
