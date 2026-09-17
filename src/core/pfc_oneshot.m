function pfc_oneshot(ui)
%PFC_ONESHOT 开环发一帧：CH1/CH2 时域+频谱上屏，写入本次目录（raw.mat + 图）。界面无关。
% ui 为 UI 适配层（实现见 pfc_ui_html，约定接口见 pfc_ui_check）；本函数与界面无关。
global fgen %#ok<GVMIS>
ui = pfc_ui_check(ui);

S = ui.raw();
[freq, volt] = ui.debugfv();
L = pfc_param_limits();
cycle = pick(S, 'n_cycle', L.n_cycle_default);
PRF   = pick(S, 'prf_hz', NaN);
depth = pick(S, 'npts', NaN);
% 频率/电压由 ui.debugfv() 严格给出（界面空框时得到 NaN，不会兜底成默认值）；
% PRF 必须为正，否则 1/PRF 变成 Inf、猝发周期非法。
if any(~isfinite([freq, cycle, PRF, volt, depth])) || ...
        freq <= 0 || volt <= 0 || PRF <= 0 || cycle < L.n_cycle_min || depth < L.npts_min
    error('PFC:oneshot:params', ...
        '请先填写有效的采集 频率/电压 (MHz / mVpp)，以及 PRF (>0)、周期数、采样点 (>=%d)。', ...
        L.npts_min);
end
% 与正式实验同一上限，避免 oneshot 静默卡在旧的 40k。
depth = max(L.npts_min, min(round(depth), L.npts_max));
cycle = max(L.n_cycle_min, min(round(cycle), L.n_cycle_max));

outdir = ui.outdir();
cfg = rigol_instr_config();
Fs = 40e6;
started_at = datestr(now, 'yyyy-mm-ddTHH:MM:SS');
trig = max(5e-4, 0.25 * (volt / 1000));

ui.status('采集中 Acquiring…');

scope = rigol_dho814_open();
info = rigol_dho814_setup(scope, Fs, depth, cfg.scope_channel, trig);
fgen_excute_UTSW(freq, volt, 0, cycle, 1 / PRF);
try
    rigol_dg2052_output_set(fgen, true);
    [chA, dt_ns, realFs, chTx] = rigol_dho814_acquire_block(scope, depth, cfg.scope_pcd_channel);
    rigol_dg2052_output_set(fgen, false);
    % 采集失败时返回的是空数组。不拦住的话后面照样算 FFT、写目录、还提示
    % 「已保存」—— 看着像成功，实际存进去是一片空数据。
    if ~isfinite(realFs) || realFs <= 0
        error('PFC:oneshot:frame', '示波器未返回有效采样率，本次采集失败（未保存）。');
    end
    if isempty(chTx) || numel(chTx) < 256 || max(abs(chTx)) <= 5e-5
        error('PFC:oneshot:frame', ...
            ['未采到有效波形（触发超时或幅度过小），本次不保存。\n' ...
             '请确认：CH1 已接信号源回读、触发已产生、射频输出已打开。']);
    end
catch err
    try, rigol_dg2052_output_set(fgen, false); catch, end
    rethrow(err);
end

% CH1 / CH2 都上时域+频谱；前端分槽显示，不再共用一张 FFT。
ui.waveform(chTx, realFs, freq, 'CH1 回读 TX', struct('ch', 'tx', 'fft', true));
if ~isempty(chA)
    ui.waveform(chA, realFs, freq, 'CH2 PCD', struct('ch', 'pcd', 'fft', true));
end
[F, Y, db, NFFT] = pfc_spectrum(chTx, realFs);

R = struct();
R.chA = chA;
R.chTx = chTx;
R.realFs = realFs;
R.timeIntervalNanoSeconds = dt_ns;
R.f_Hz = F;
R.fft_abs = Y;
R.fft_dB = db;
R.NFFT = NFFT;
R.freq_MHz = freq;
R.volt_mVpp = volt;
R.PRF_Hz = PRF;
R.BurstCount = cycle;
R.npts = depth;
R.studyID = pickstr(S, 'studyID', '');
R.waveform_format = info.waveform_format;
% 与 2/3/4 同一套 params 快照；顶层旧名（freq_MHz / BurstCount 等）不动。
% 超声参数的频/压从 raw 来；真正驱动 AWG 的是采集框 → dbg_* / volt_out。
src = struct('raw', S, 'volt_out_mVpp', volt, ...
    'prf_hz', PRF, 'n_cycle', cycle, 'npts', depth, 'fs_target', Fs, ...
    'realFs', realFs, 'n_expect', 1, 'studyID', R.studyID, ...
    'dbg_freq', freq, 'dbg_volt', volt, 'trig_v', trig, 'sweep', 'SINGle', ...
    'started_at', started_at, 'waveform_format', info.waveform_format, ...
    'tx_scale_vdiv', 0.05, 'pcd_scale_vdiv', 0.05, ...
    'scope_tx_channel', info.scope_tx_channel, ...
    'scope_pcd_channel', info.scope_pcd_channel);
R.params = pfc_save_params('oneshot', src);
fp = pfc_save_acquisition(outdir, ['oneshot_' R.studyID], R);
ui.status(['已保存 Saved  ' fp]);   % fp 是本次目录，raw.mat 与分析图都在里面
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

function s = pickstr(S, k, def)
s = def;
if isstruct(S) && isfield(S, k)
    x = S.(k);
    if ischar(x) || isstring(x)
        s = char(x);
    end
end
end
