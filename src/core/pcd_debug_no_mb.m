function result = pcd_debug_no_mb(opts)
%PCD_DEBUG_NO_MB 未打微泡调试：CW 正弦，示波器 AUTO，RAW 读 CH1 做 FFT。
% 运行至 STOP FUS。期间可改「1. 采集」里的频率/电压（回车或点别处即下发）。
% opts.ui 为 UI 适配层（实现见 pcd_ui_html，约定接口见 pcd_ui_check）。
if nargin < 1
    opts = struct();
end

ui = [];
if isfield(opts, 'ui'), ui = opts.ui; end
ui = pcd_ui_check(ui);

cfg = rigol_instr_config();

L = pcd_param_limits();
freq = getf(opts, 'freq_mhz', 1.5);
volt = getf(opts, 'volt_mVpp', 20);
npts = getf(opts, 'npts', 20000);
npts = max(L.npts_min, min(round(npts), L.npts_max));
Fs   = getf(opts, 'fs_target', 40e6);

global pcd_abort fgen
pcd_abort = false;
token = pcd_visa('token');
liveStop = onCleanup(@() pcd_debug_live('stop')); %#ok<NASGU>
rfStop = onCleanup(@() pcd_visa('rf_off_if', token)); %#ok<NASGU>

outdir = fullfile(pcd_root(), 'data');
if isfield(opts, 'outdir') && ~isempty(opts.outdir)
    outdir = opts.outdir;
end
if ~isfolder(outdir), mkdir(outdir); end
started_at = datestr(now, 'yyyy-mm-ddTHH:MM:SS');

trig = max(1e-3, 0.2 * (volt / 1000));
scope = pcd_visa('scope');
fgen = pcd_visa('fgen');
info = rigol_dho814_setup(scope, Fs, npts, cfg.scope_pcd_channel, trig, 'AUTO');
scTx = 0.05;    % 与 setup 里两个通道的初值一致，下面按实测峰值重定标
scPcd = 0.05;
[freq, volt] = pcd_debug_live('start', ui, freq, volt);

rigol_dg2052_output_set(fgen, true);
tWait = tic;
while toc(tWait) < 0.3
    if ~pcd_visa('alive', token)
        break;
    end
    pause(0.05);
end
t0 = tic;
pulse = 0;
n_clip = 0;
clip_retry = 0;
peaks = [];
datamat = [];
txmat = [];
try
    while pcd_visa('alive', token)
        [freq, volt] = pcd_debug_live('get');
        [chPcd, ~, realFs, chTx] = rigol_dho814_acquire_block(scope, npts, cfg.scope_pcd_channel, 'live');
        if ~pcd_visa('alive', token)
            break;
        end
        pkTx = 0;  if ~isempty(chTx),  pkTx = max(abs(chTx));   end
        pkPcd = 0; if ~isempty(chPcd), pkPcd = max(abs(chPcd)); end
        clipped = rigol_dho814_clipped(chTx, scTx) || rigol_dho814_clipped(chPcd, scPcd);
        % 每发按峰值预留 4× 余量（K_DIV=1.0）。削顶会造假谐波，入库会把谱带歪：
        % 贴轨帧不写入 datamat，扩量程后重采，连续最多 3 次。
        K_DIV = 1.0;
        if pkTx > 1e-4
            scTx = min(1.0, max(0.005, pkTx / K_DIV));
        end
        if pkPcd > 1e-4
            scPcd = min(1.0, max(0.005, pkPcd / K_DIV));
        end
        if clipped
            scTx  = min(1.0, 1.5 * scTx);
            scPcd = min(1.0, 1.5 * scPcd);
            n_clip = n_clip + 1;
        end
        writeline(scope, sprintf(':CHANnel%d:SCALe %.6g', cfg.scope_tx_channel, scTx));
        writeline(scope, sprintf(':CHANnel%d:SCALe %.6g', cfg.scope_pcd_channel, scPcd));
        if clipped
            if clip_retry < 3
                clip_retry = clip_retry + 1;
                ui.status(sprintf('调试  削顶已丢弃，扩量程重采（第 %d/3 次）', clip_retry));
                pause(0.05);
                continue;
            end
            clip_retry = 0;
            ui.status('调试  连续削顶仍丢弃（不入库），下一发再试');
            pause(0.05);
            continue;
        end
        clip_retry = 0;
        pulse = pulse + 1;
        % 采样失败时 acquire_block 返回 []，帧长也可能和上一帧不同：
        % 先整形成定长行，否则下面的矩阵赋值会因维度不一致直接中断整轮调试。
        datamat(pulse, :) = pcd_fitrow(chPcd, npts); %#ok<AGROW>
        txmat(pulse, :) = pcd_fitrow(chTx, npts); %#ok<AGROW>
        % 两路上时域+频谱：CH1 正弦截窗，CH2 整段底噪。峰位仍取 CH1（调试看驱动）。
        [fpk, dpk] = ui.waveform(chTx, realFs, freq, 'CH1 回读 TX', struct('ch', 'tx', 'fft', true));
        if ~isempty(chPcd)
            ui.waveform(chPcd, realFs, freq, 'CH2 PCD', struct('ch', 'pcd', 'fft', true));
        end
        peaks(pulse, :) = [fpk, dpk]; %#ok<AGROW>
        ok = isfinite(fpk) && abs(fpk - freq) < 0.25;
        pp1 = 0;
        if ~isempty(chTx)
            pp1 = (max(chTx) - min(chTx)) * 1e3;
        end
        if pp1 < 0.2 * volt
            ok = false;
        end
        msg = sprintf('调试  设定 %.3g MHz  %.4g mVpp  CH1 %.2f mVpp @ %s  #%d  （STOP 结束）', ...
            freq, volt, pp1, ...
            tern(ok && isfinite(fpk), sprintf('%.3f MHz OK', fpk), ...
            tern(isfinite(fpk), sprintf('%.3f MHz', fpk), '无峰')), pulse);
        if pp1 < 0.2 * volt
            msg = [msg '  【CH1 回读过弱，检查接线/探头】']; %#ok<AGROW>
        end
        if ~isfinite(fpk)
            mx = 0;
            if ~isempty(chTx), mx = max(abs(chTx)); end
            msg = sprintf('调试 CH1 无有效峰（时域 max=%.3g V，p-p=%.2f mV）  #%d', mx, pp1, pulse);
        end
        ui.status(msg);
        fprintf('%s\n', msg);
        pause(0.05);
    end
catch err
    pcd_visa('rf_off_if', token);
    rethrow(err);
end
pcd_visa('rf_off_if', token);

S = struct();
S.datamat = datamat;
S.txmat = txmat;
S.peaks_mhz_db = peaks;
S.realFs = info.realFs;
S.freq_MHz = freq;
S.volt_mVpp = volt;
S.duration_s = toc(t0);
S.npts = npts;
S.note = 'debug CW; live V/f from GUI; CH1 FFT, CH2 PCD; RAW snapshot';
S.n_clip_expand = n_clip;        % 削顶丢弃并重采的次数（未写入 datamat）
S.pcd_scale_vdiv = scPcd;        % CH2 最终量程 (V/div)
S.waveform_format = info.waveform_format;
% 与正式实验同一套 params；debug 是 CW，PRF/周期数只作当时界面留档。
src = struct();
try, src.raw = ui.raw(); catch, src.raw = struct(); end
if isfield(opts, 'raw') && isstruct(opts.raw)
    src.raw = opts.raw;
end
src.volt_out_mVpp = volt;
src.dbg_freq = freq;
src.dbg_volt = volt;
src.npts = npts;
src.fs_target = Fs;
src.realFs = info.realFs;
src.prf_hz = getf(opts, 'prf_hz', NaN);
src.n_cycle = getf(opts, 'n_cycle', NaN);
src.pcd_scale_vdiv = scPcd;
src.tx_scale_vdiv = scTx;
src.waveform_format = info.waveform_format;
src.trig_v = trig;
src.sweep = 'AUTO';
src.started_at = started_at;
src.scope_tx_channel = info.scope_tx_channel;
src.scope_pcd_channel = info.scope_pcd_channel;
S.params = pcd_save_params('debug', src);
fp = pcd_save_acquisition(outdir, 'debug_noMB', S);
result.file = fp;
result.n_pulse = pulse;
if ~isempty(peaks)
    result.median_peak_mhz = median(peaks(:,1), 'omitnan');
else
    result.median_peak_mhz = NaN;
end
ui.status(sprintf('已保存  %d 帧  %s', pulse, fp));
fprintf('调试结束：%d 帧，CH1 谱峰中位 %.3f MHz\n%s\n', pulse, result.median_peak_mhz, fp);
end

function v = getf(s, name, def)
if isfield(s, name) && ~isempty(s.(name)) && all(isfinite(s.(name)))
    v = s.(name);
else
    v = def;
end
end

function s = tern(c, a, b)
if c, s = a; else, s = b; end
end
