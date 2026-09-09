function result = pfc_run_experiment(mode, handles)
%PFC_RUN_EXPERIMENT
%  'before'  阶段2：无微泡，猝发，CH1+CH2
%  'open_mb' 阶段3：有微泡开环（输液泵已在跑，不等待注射）
%  'feedback'/'during' 阶段4：基线 + 闭环（同样假定泵已在输液）
global pfc_abort fgen
cfg = rigol_instr_config();
p = pfc_gui_fus_params(handles);
outdir = pfc_ensure_save_dir(handles);
pfc_abort = false;

scope = pfc_visa('scope');
fgen = pfc_visa('fgen');

mode = lower(char(mode));
% 开环 2/3 用「超声参数」电压。Max V 只限制闭环 4，不要拿来截断开环。
if any(strcmp(mode, {'during', 'feedback'}))
    v_out = min(p.volt_mVpp, p.max_mVpp);
else
    v_out = p.volt_mVpp;
end
% 触发电平必须低于实际 CH1 峰值（约 Vpp/2），否则有效帧永远是 0。
vpp_v = max(v_out, 1) / 1000;
trig = max(0.002, min(0.12 * vpp_v, 0.30 * (vpp_v / 2)));
info = rigol_dho814_setup(scope, p.fs_target, p.npts, cfg.scope_pcd_channel, trig, 'SINGle');
tx_scale = max(0.001, vpp_v / 3);
writeline(scope, sprintf(':CHANnel%d:SCALe %.6g', cfg.scope_tx_channel, tx_scale));
writeline(scope, sprintf(':CHANnel%d:SCALe %.6g', cfg.scope_pcd_channel, max(0.005, tx_scale)));
fprintf('PFC 输出 %.4g mVpp  触发 %.3g mV  （MaxV 仅用于闭环）\n', v_out, trig * 1e3);

cla(handles.realtimeSCplot);
cla(handles.realtimeICplot);
cla(handles.realtimeVplot);

timeout_s = min(3.0, max(0.9, 3.5 * p.period_s));
acq_n = p.npts;
datamat = [];
txmat = [];
Vrec = [];
SCrec = [];
ICrec = [];
peaks_ch1 = [];
harm_db = [];
pulse = 0;
scaled = false;
save_path = '';
n_good = 0;
prefix = '';

try
    if any(strcmp(mode, {'during', 'feedback'}))
        prefix = ['Sonication_' sanitize_id(p.studyID)];
        base_n = max(4, round(5 * p.prf_hz));
        base_v = min(p.max_mVpp, max(v_out, 18));
        start_burst(fgen, p, base_v);
        run_loop(inf, base_n, base_v, false, '4 基线');
        if pfc_abort
            result = save_now();
            return;
        end
        n_base = numel(SCrec);
        if n_base < 1
            error('pfc:baseline', '基线没有采到有效 CH2 帧。未开始闭环。');
        end
        sc0 = mean(SCrec(max(1, n_base-base_n+1):n_base));
        sc_tgt = sc0 * (10^(p.target_db / 10));
        sc_hi = sc0 * (10^((p.target_db + 0.4) / 10));
        sc_lo = sc0 * (10^((p.target_db - 0.4) / 10));
        start_burst(fgen, p, v_out);
        run_loop(p.duration_s, p.n_expect, v_out, true, ...
            '4 闭环 Feedback', sc_tgt, sc_hi, sc_lo, p.max_mVpp);
    elseif strcmp(mode, 'open_mb')
        prefix = ['OpenMB_' sanitize_id(p.studyID)];
        start_burst(fgen, p, v_out);
        run_loop(p.duration_s, p.n_expect, v_out, false, '3 有微泡开环');
    else
        prefix = ['NoMB_' sanitize_id(p.studyID)];
        start_burst(fgen, p, v_out);
        run_loop(p.duration_s, p.n_expect, v_out, false, '2 无微泡 CH2');
    end
catch err
    pfc_visa('rf_off');
    try
        save_now();
    catch
    end
    rethrow(err);
end
pfc_visa('rf_off');
result = save_now();

    function result = save_now()
        S = pack_save();
        if isempty(save_path)
            save_path = pfc_save_acquisition(outdir, prefix, S);
        else
            save(save_path, '-struct', 'S', '-v7.3');
        end
        result.file = save_path;
        result.n_pulse = n_good;
        msg = sprintf('已保存  %d 帧有效 / 目标 %d  %s', n_good, p.n_expect, save_path);
        if n_good < max(8, round(0.3 * p.n_expect)) && ~strcmp(mode, 'aborted')
            msg = ['【帧数不足，勿当完整实验】  ' msg];
        end
        if isfield(handles, 'PulseNum') && isgraphics(handles.PulseNum)
            set(handles.PulseNum, 'String', msg);
        end
        fprintf('%s\n', msg);
    end

    function S = pack_save()
        S = struct();
        S.datamat = datamat;
        S.txmat = txmat;
        S.realFs = info.realFs;
        S.Vrealtime = Vrec;
        S.RampSC = SCrec;
        S.RampIC = ICrec;
        S.peaks_ch1_mhz_db = peaks_ch1;
        S.harm_db = harm_db;
        S.harm_db_cols = 'f0_dB  2f_dB  3f_dB  1.5f_dB  2.5f_dB  0.5f_dB';
        S.sc_band_mhz = 2 * p.freq_mhz;     % 本实验室 PCD~3 MHz → SC=2f，非原文 3f
        S.ic_band_mhz = 2.2 * p.freq_mhz;    % 3.3 MHz；距 2f 300 kHz，±20 kHz 不重叠
        S.freq_MHz = p.freq_mhz;
        S.volt_mVpp = v_out;
        S.volt_gui_mVpp = p.volt_mVpp;
        S.max_mVpp = p.max_mVpp;
        S.PRF_Hz = p.prf_hz;
        S.BurstCount = p.n_cycle;
        S.npts = p.npts;
        S.duration_s = p.duration_s;
        S.n_expect = p.n_expect;
        S.n_good = n_good;
        S.studyID = p.studyID;
        S.mb_injection = 'continuous_infusion';
        S.note = 'burst; CH1 TX + CH2 PCD RAW; CH1 edge; MB pump assumed already on';
    end

    function run_loop(dur_s, max_pulses, volt, do_fb, label, sc_tgt, sc_hi, sc_lo, max_mVpp)
        if nargin < 6, sc_tgt = NaN; end
        if nargin < 7, sc_hi = NaN; end
        if nargin < 8, sc_lo = NaN; end
        if nargin < 9, max_mVpp = p.max_mVpp; end
        ramping = true;
        t1 = tic;
        n0 = n_good;
        while true
            if pfc_abort
                break;
            end
            if isfinite(dur_s) && toc(t1) >= dur_s
                break;
            end
            if isfinite(max_pulses) && (n_good - n0) >= max_pulses
                break;
            end
            if isfinite(dur_s) && (dur_s - toc(t1)) < 0.12
                break;
            end
            if isfield(handles, 'PulseNum') && isgraphics(handles.PulseNum)
                tgt = max_pulses;
                if ~isfinite(tgt)
                    tgt = p.n_expect;
                end
                if isfinite(dur_s)
                    set(handles.PulseNum, 'String', sprintf( ...
                        '%s  有效 %d / 目标 %d  剩余 %.0f s', ...
                        label, n_good - n0, tgt, max(0, dur_s - toc(t1))));
                else
                    set(handles.PulseNum, 'String', sprintf('%s  %d / %d', ...
                        label, n_good - n0, tgt));
                end
                drawnow;
            end
            [chPcd, ~, realFs, chTx] = rigol_dho814_acquire_block( ...
                scope, p.npts, cfg.scope_pcd_channel, 'single', timeout_s);
            if ~frame_ok(chPcd, chTx)
                continue;
            end
            if isfinite(realFs) && realFs > 0
                info.realFs = realFs;
            end
            pulse = pulse + 1;
            n_good = n_good + 1;
            k = n_good;
            datamat(k, :) = fitrow(chPcd, acq_n); %#ok<AGROW>
            txmat(k, :) = fitrow(chTx, acq_n); %#ok<AGROW>
            [fpk, ~] = pfc_update_signal_fft(handles, datamat(k, :), [], info.realFs, p.freq_mhz, 'CH2 PCD'); %#ok<ASGLU>
            [F, Y, db] = pfc_spectrum(datamat(k, :), info.realFs);
            [sc, ic] = pfc_band_energy(Y, F, p.freq_mhz * 1e6, cfg.harmonic_bandwidth_hz);
            fM = F / 1e6;
            grab = @(fm) local_band_db(fM, db, fm, 0.20);
            f0m = p.freq_mhz;
            harm_db(k, :) = [grab(f0m), grab(2*f0m), grab(3*f0m), ...
                grab(1.5*f0m), grab(2.5*f0m), grab(0.5*f0m)]; %#ok<AGROW>
            Vrec(k) = volt; %#ok<AGROW>
            SCrec(k) = sc; %#ok<AGROW>
            ICrec(k) = ic; %#ok<AGROW>
            [F1, ~, db1] = pfc_spectrum(txmat(k, :), info.realFs);
            [ch1pk, ch1db] = pfc_fft_peak_mhz(F1, db1, 0.3, 8);
            peaks_ch1(k, :) = [ch1pk, ch1db]; %#ok<AGROW>
            if max(abs(chTx)) > 1e-4
                writeline(scope, sprintf(':CHANnel%d:SCALe %.6g', cfg.scope_tx_channel, ...
                    min(1.0, max(0.001, max(abs(chTx)) / 3.2))));
                scaled = true; %#ok<NASGU>
            end
            if max(abs(chPcd)) > 1e-4
                writeline(scope, sprintf(':CHANnel%d:SCALe %.6g', cfg.scope_pcd_channel, ...
                    min(1.0, max(0.002, max(abs(chPcd)) / 3.2))));
            end
            pfc_plot_feedback(handles, k, sc, ic, volt, max(30, k + 12), max(volt * 1.5, 40));
            ok1 = isfinite(ch1pk) && abs(ch1pk - p.freq_mhz) < 0.25;
            fprintf('%s  #%d  CH1 %s  CH2 2f(%.2f MHz)=%.1f dB  f/2=%.1f dB\n', ...
                label, k, ...
                tern(ok1, sprintf('%.3f MHz OK', ch1pk), sprintf('peak=%s', num2str(ch1pk, '%.3f'))), ...
                2 * p.freq_mhz, harm_db(k, 2), harm_db(k, 6));
            if mod(k, 5) == 0
                save_now();
            end
            if do_fb
                if ramping
                    if k > n0 + 1 && sc >= sc_tgt
                        ramping = false;
                    else
                        volt = min(max_mVpp, volt + 1);
                    end
                else
                    if sc > sc_hi
                        volt = max(1, volt - 1);
                    elseif sc < sc_lo
                        volt = min(max_mVpp, volt + 1);
                    end
                end
                rigol_dg2052_set_vpp_mV(fgen, volt);
            end
        end
    end
end

function start_burst(fgen, p, volt)
cfg = rigol_instr_config();
rigol_dg2052_apply_burst(fgen, cfg.awg_channel, p.freq_mhz, volt, 0, p.n_cycle, p.period_s);
rigol_dg2052_output_set(fgen, true);
pause(p.period_s + 0.15);
end

function tf = frame_ok(chPcd, chTx)
tf = (~isempty(chTx) && numel(chTx) >= 256 && max(abs(chTx)) > 5e-5) || ...
    (~isempty(chPcd) && numel(chPcd) >= 256 && max(abs(chPcd)) > 5e-5);
end

function row = fitrow(x, n)
x = x(:).';
if isempty(x)
    row = zeros(1, n);
elseif numel(x) >= n
    row = x(1:n);
else
    row = [x, zeros(1, n - numel(x))];
end
end

function s = tern(c, a, b)
if c, s = a; else, s = b; end
end

function s = sanitize_id(id)
s = regexprep(char(string(id)), '[^A-Za-z0-9_-]+', '_');
s = regexprep(s, '^_+|_+$', '');
if isempty(s) || contains(lower(s), 'enter')
    s = 'ID';
end
end

function dbp = local_band_db(fM, db, fm, halfw)
m = fM >= (fm - halfw) & fM <= (fm + halfw);
if ~any(m)
    dbp = NaN;
else
    dbp = max(db(m));
end
end
