function pfc_oneshot(ui)
%PFC_ONESHOT 开环发一帧：CH1 回读做 FFT、CH2 存 PCD 波形。界面无关。
% ui 为 UI 适配层（实现见 pfc_ui_html，约定接口见 pfc_ui_check）；本函数与界面无关。
global fgen %#ok<GVMIS>
ui = pfc_ui_check(ui);

S = ui.raw();
[freq, volt] = ui.debugfv();
cycle = pick(S, 'n_cycle', 400);
PRF   = pick(S, 'prf_hz', NaN);
depth = pick(S, 'npts', NaN);
% 频率/电压由 ui.debugfv() 严格给出（界面空框时得到 NaN，不会兜底成默认值）；
% PRF 必须为正，否则 1/PRF 变成 Inf、猝发周期非法。
if any(~isfinite([freq, cycle, PRF, volt, depth])) || ...
        freq <= 0 || volt <= 0 || PRF <= 0 || cycle < 1 || depth < 1024
    error('PFC:oneshot:params', ...
        '请先填写有效的采集 频率/电压 (MHz / mVpp)，以及 PRF (>0)、周期数、采样点 (>=1024)。');
end
depth = max(4096, min(round(depth), 40000));
cycle = max(1, round(cycle));

outdir = ui.outdir();
cfg = rigol_instr_config();
Fs = 40e6;

ui.status('采集中 Acquiring…');

scope = rigol_dho814_open();
rigol_dho814_setup(scope, Fs, depth, cfg.scope_channel, max(5e-4, 0.25 * (volt / 1000)));
fgen_excute_UTSW(freq, volt, 0, cycle, 1 / PRF);
try
    rigol_dg2052_output_set(fgen, true);
    [chA, dt_ns, realFs, chTx] = rigol_dho814_acquire_block(scope, depth, cfg.scope_pcd_channel);
    rigol_dg2052_output_set(fgen, false);
    % 采集失败时返回的是空数组。不拦住的话后面照样算 FFT、写 .mat、还提示
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

ui.waveform(chTx, realFs, freq, 'CH1 回读 TX');
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
R.studyID = pickstr(S, 'studyID', '');
fp = pfc_save_acquisition(outdir, ['oneshot_' R.studyID], R);
ui.status(['已保存 Saved  ' fp]);
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
