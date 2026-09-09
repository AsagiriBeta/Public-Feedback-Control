function result = pfc_debug_no_mb(opts)
%PFC_DEBUG_NO_MB 未打微泡调试：CW 正弦，示波器 AUTO，RAW 读 CH1 做 FFT。
% 运行至 STOP FUS。期间可改「2. 超声」里的频率/电压（回车或点别处即下发）。
if nargin < 1, opts = struct(); end
cfg = rigol_instr_config();

freq = getf(opts, 'freq_mhz', 1.5);
volt = getf(opts, 'volt_mVpp', 20);
npts = getf(opts, 'npts', 20000);
Fs   = getf(opts, 'fs_target', 40e6);
handles = [];
if isfield(opts, 'handles'), handles = opts.handles; end

global pfc_abort fgen
pfc_abort = false;
liveStop = onCleanup(@() pfc_debug_live('stop')); %#ok<NASGU>

outdir = fullfile(fileparts(mfilename('fullpath')), 'data');
if isfield(opts, 'outdir') && ~isempty(opts.outdir)
    outdir = opts.outdir;
end
if ~isfolder(outdir), mkdir(outdir); end

trig = max(1e-3, 0.2 * (volt / 1000));
scope = pfc_visa('scope');
fgen = pfc_visa('fgen');
info = rigol_dho814_setup(scope, Fs, npts, cfg.scope_pcd_channel, trig, 'AUTO');
[freq, volt] = pfc_debug_live('start', handles, freq, volt);

if isempty(handles)
    fig = figure('Name', 'PFC debug no-MB', 'Color', [0.11 0.12 0.14], ...
        'Position', [60 80 1100 420]);
    handles.Signal_plot = subplot(1,2,1);
    handles.FFT_plot = subplot(1,2,2);
    handles.PulseNum = [];
end

rigol_dg2052_output_set(fgen, true);
pause(0.3);
t0 = tic;
pulse = 0;
peaks = [];
datamat = [];
txmat = [];
try
    while true
        if pfc_abort
            break;
        end
        [freq, volt] = pfc_debug_live('get');
        [chPcd, dt_ns, realFs, chTx] = rigol_dho814_acquire_block(scope, npts, cfg.scope_pcd_channel, 'live');
        pulse = pulse + 1;
        datamat(pulse, :) = chPcd; %#ok<AGROW>
        txmat(pulse, :) = chTx; %#ok<AGROW>
        [fpk, dpk] = pfc_update_signal_fft(handles, chTx, dt_ns, realFs, freq, 'CH1 回读 TX');
        peaks(pulse, :) = [fpk, dpk]; %#ok<AGROW>
        if pulse == 1 && max(abs(chTx)) > 1e-4
            pkTx = max(abs(chTx));
            pkPcd = max(abs(chPcd));
            writeline(scope, sprintf(':CHANnel%d:SCALe %.6g', cfg.scope_tx_channel, min(1.0, max(0.005, pkTx/3.2))));
            if pkPcd > 1e-4
                writeline(scope, sprintf(':CHANnel%d:SCALe %.6g', cfg.scope_pcd_channel, min(1.0, max(0.005, pkPcd/3.2))));
            end
        end
        ok = isfinite(fpk) && abs(fpk - freq) < 0.25;
        msg = sprintf('调试  %.3g MHz  %.4g mVpp  CH1 peak=%s  #%d  （STOP 结束）', ...
            freq, volt, ...
            tern(ok, sprintf('%.3f MHz OK', fpk), sprintf('%.3f MHz', fpk)), pulse);
        if ~isfinite(fpk)
            msg = sprintf('调试 CH1 无有效峰（时域 max=%.3g V）  #%d', max(abs(chTx)), pulse);
        end
        if ~isempty(handles.PulseNum) && isgraphics(handles.PulseNum)
            set(handles.PulseNum, 'String', msg);
        end
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
