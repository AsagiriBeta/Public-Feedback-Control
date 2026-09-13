function result = pfc_debug_no_mb(opts)
%PFC_DEBUG_NO_MB 未打微泡调试：CW 正弦，示波器 AUTO，RAW 读 CH1 做 FFT。
% 运行至 STOP FUS。期间可改「1. 采集」里的频率/电压（回车或点别处即下发）。
% opts.ui 为 UI 适配层（实现见 pfc_ui_html，约定接口见 pfc_ui_check）。
if nargin < 1
    opts = struct();
end

ui = [];
if isfield(opts, 'ui'), ui = opts.ui; end
ui = pfc_ui_check(ui);

cfg = rigol_instr_config();

freq = getf(opts, 'freq_mhz', 1.5);
volt = getf(opts, 'volt_mVpp', 20);
npts = getf(opts, 'npts', 20000);
Fs   = getf(opts, 'fs_target', 40e6);

global pfc_abort fgen
pfc_abort = false;
liveStop = onCleanup(@() pfc_debug_live('stop')); %#ok<NASGU>

outdir = fullfile(pfc_root(), 'data');
if isfield(opts, 'outdir') && ~isempty(opts.outdir)
    outdir = opts.outdir;
end
if ~isfolder(outdir), mkdir(outdir); end

trig = max(1e-3, 0.2 * (volt / 1000));
scope = pfc_visa('scope');
fgen = pfc_visa('fgen');
info = rigol_dho814_setup(scope, Fs, npts, cfg.scope_pcd_channel, trig, 'AUTO');
scTx = 0.05;    % 与 setup 里两个通道的初值一致，下面按实测峰值重定标
scPcd = 0.05;
[freq, volt] = pfc_debug_live('start', ui, freq, volt);

rigol_dg2052_output_set(fgen, true);
pause(0.3);
t0 = tic;
pulse = 0;
n_clip = 0;
peaks = [];
datamat = [];
txmat = [];
try
    while true
        if pfc_abort
            break;
        end
        [freq, volt] = pfc_debug_live('get');
        [chPcd, ~, realFs, chTx] = rigol_dho814_acquire_block(scope, npts, cfg.scope_pcd_channel, 'live');
        pulse = pulse + 1;
        % 采样失败时 acquire_block 返回 []，帧长也可能和上一帧不同：
        % 先整形成定长行，否则下面的矩阵赋值会因维度不一致直接中断整轮调试。
        datamat(pulse, :) = pfc_fitrow(chPcd, npts); %#ok<AGROW>
        txmat(pulse, :) = pfc_fitrow(chTx, npts); %#ok<AGROW>
        [fpk, dpk] = ui.waveform(chTx, realFs, freq, 'CH1 回读 TX');
        peaks(pulse, :) = [fpk, dpk]; %#ok<AGROW>
        pkTx = 0;  if ~isempty(chTx),  pkTx = max(abs(chTx));   end
        pkPcd = 0; if ~isempty(chPcd), pkPcd = max(abs(chPcd)); end
        clipped = rigol_dho814_clipped(chTx, scTx) || rigol_dho814_clipped(chPcd, scPcd);
        if pulse == 1 && pkTx > 1e-4
            % 第一帧按峰值定标；余量用 1.4（满量程 ≈ 2.8×峰值），别再压到 3.2 那么紧 ——
            % 量程照上一帧定、余量又小的时候，信号一变大就顶穿。
            scTx  = min(1.0, max(0.005, pkTx  / 1.4));
            scPcd = min(1.0, max(0.005, pkPcd / 1.4));
            writeline(scope, sprintf(':CHANnel%d:SCALe %.6g', cfg.scope_tx_channel, scTx));
            writeline(scope, sprintf(':CHANnel%d:SCALe %.6g', cfg.scope_pcd_channel, scPcd));
        elseif clipped
            % 顶到满量程：翻倍量程再看。削顶是对称的，3f 会虚高几十 dB ——
            % 调试时屏幕上那个「4.5 MHz 峰」很可能就是这么来的。
            scTx  = min(1.0, 2 * scTx);
            scPcd = min(1.0, 2 * scPcd);
            n_clip = n_clip + 1;
            writeline(scope, sprintf(':CHANnel%d:SCALe %.6g', cfg.scope_tx_channel, scTx));
            writeline(scope, sprintf(':CHANnel%d:SCALe %.6g', cfg.scope_pcd_channel, scPcd));
        end
        ok = isfinite(fpk) && abs(fpk - freq) < 0.25;
        msg = sprintf('调试  %.3g MHz  %.4g mVpp  CH1 peak=%s  #%d  （STOP 结束）', ...
            freq, volt, ...
            tern(ok, sprintf('%.3f MHz OK', fpk), sprintf('%.3f MHz', fpk)), pulse);
        if ~isfinite(fpk)
            msg = sprintf('调试 CH1 无有效峰（时域 max=%.3g V）  #%d', max(abs(chTx)), pulse);
        end
        if clipped
            msg = [msg '  【削顶·已扩量程】']; %#ok<AGROW>
        end
        ui.status(msg);
        fprintf('%s\n', msg);
        drawnow;
        pause(0.05);
    end
catch err
    pfc_visa('rf_off');
    rethrow(err);
end
pfc_visa('rf_off');

S = struct();
S.datamat = datamat;
S.txmat = txmat;
S.peaks_mhz_db = peaks;
S.realFs = info.realFs;
S.freq_MHz = freq;
S.volt_mVpp = volt;
S.duration_s = toc(t0);
S.note = 'debug CW; live V/f from GUI; CH1 FFT, CH2 PCD; RAW snapshot';
S.n_clip_expand = n_clip;        % 因削顶而扩大量程的次数
S.pcd_scale_vdiv = scPcd;        % CH2 最终量程 (V/div)
S.waveform_format = info.waveform_format;
fp = pfc_save_acquisition(outdir, 'debug_noMB', S);
result.file = fp;
result.n_pulse = pulse;
if ~isempty(peaks)
    result.median_peak_mhz = median(peaks(:,1), 'omitnan');
else
    result.median_peak_mhz = NaN;
end
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
