function result = pfc_run_experiment(mode, ui)
%PFC_RUN_EXPERIMENT
%  'before'  阶段2：无微泡，猝发，CH1+CH2
%  'open_mb' 阶段3：有微泡开环（输液泵已在跑，不等待注射）
%  'feedback'/'during' 阶段4：基线 + 闭环（同样假定泵已在输液）
% ui 为 UI 适配层（实现见 pfc_ui_html，约定接口见 pfc_ui_check）；本函数与界面无关。
global pfc_abort fgen
ui = pfc_ui_check(ui);
cfg = rigol_instr_config();
p = ui.params();
outdir = ui.outdir();
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
% 量程系数 K = 「满量程 ≈ K × 本帧峰值」。K=1.4 -> 满量程 ≈ 2.8× 峰值，能扛住一次
% 接近 3 倍的帧间跳变（真出空化时信号恰恰会突然变大）。K 太小会削顶 —— 对称削顶
% 会长出 3f/5f 假峰，闭环会去追假信号；K 太大则白白浪费竖直分辨率。
scTx  = max(0.001, vpp_v / 1.4);
scPcd = max(0.001, vpp_v / 1.4);
writeline(scope, sprintf(':CHANnel%d:SCALe %.6g', cfg.scope_tx_channel, scTx));
writeline(scope, sprintf(':CHANnel%d:SCALe %.6g', cfg.scope_pcd_channel, scPcd));
fprintf('PFC 输出 %.4g mVpp  触发 %.3g mV  （MaxV 仅用于闭环）\n', v_out, trig * 1e3);

ui.clearTrend();

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
save_path = '';
n_good = 0;
prefix = '';
n_clip = 0;      % 因削顶被丢弃并重采的帧数
n_prime = 0;     % 仅用于标定量程、未入库的帧数
align = struct();% 采集窗对齐自检结果（随数据存盘）

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
        ui.status(msg);
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
        % 采集质量元数据：以后复查数据时，这些值决定「这一帧能不能用」
        S.n_clip_retry = n_clip;         % >0 说明量程偏紧，削顶帧已重采
        S.n_prime_discard = n_prime;     % 只为标定量程而丢弃的帧数
        S.pcd_scale_vdiv = scPcd;        % CH2 最终量程 (V/div)，解释竖直分辨率
        S.tx_scale_vdiv = scTx;
        S.timebase_offset_s = info.time_offset_s;
        S.burst_align = align;           % 猝发在采集窗里的位置（对齐自检）
        S.waveform_format = info.waveform_format;   % WORD = 16 位容器 / 12 位 ADC
        % RAW 模式下的波形几何：XORigin 是「内存」波形的起始时间（手册 3.28.7），
        % 屏幕窗与内存记录不重合时它就解释了「猝发为什么落在窗内某处」
        S.wf_xorigin_s = info.wf_xorigin_s;
        S.wf_xref = info.wf_xref;
        S.wf_yorigin = info.wf_yorigin;
        S.wf_yref = info.wf_yref;        % 同时反映 WORD 的二进制约定（0=补码 / 32768=偏移）
        S.wf_yinc = info.wf_yinc;
    end

    function run_loop(dur_s, max_pulses, volt, do_fb, label, sc_tgt, sc_hi, sc_lo, max_mVpp)
        if nargin < 6, sc_tgt = NaN; end
        if nargin < 7, sc_hi = NaN; end
        if nargin < 8, sc_lo = NaN; end
        if nargin < 9, max_mVpp = p.max_mVpp; end
        ramping = true;
        t1 = tic;
        n0 = n_good;
        prime = true;      % 第一发：只用来标定量程与校验采集窗
        clip_retry = 0;    % 连续削顶重采计数（限次，避免一直空转）
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
            tgt = max_pulses;
            if ~isfinite(tgt)
                tgt = p.n_expect;
            end
            if isfinite(dur_s)
                ui.status(sprintf('%s  有效 %d / 目标 %d  剩余 %.0f s', ...
                    label, n_good - n0, tgt, max(0, dur_s - toc(t1))));
            else
                ui.status(sprintf('%s  %d / %d', label, n_good - n0, tgt));
            end
            drawnow;
            [chPcd, ~, realFs, chTx] = rigol_dho814_acquire_block( ...
                scope, p.npts, cfg.scope_pcd_channel, 'single', timeout_s);
            if ~frame_ok(chPcd, chTx)
                continue;
            end
            if isfinite(realFs) && realFs > 0
                info.realFs = realFs;
            end
            % 第一发只用来标定量程 + 校验采集窗，不入库：量程若按循环前的初值走，
            % 第一帧的竖直分辨率会被白白浪费（实测那一帧的 SC 值是其余帧的 8 倍，
            % 纯粹是量程太宽带来的量化误差）。
            if prime
                prime = false;
                n_prime = n_prime + 1;
                [scTx, scPcd] = set_ranges(scope, cfg, chTx, chPcd, scTx, scPcd);
                align = check_burst_window(chTx, info.realFs, p);
                continue;
            end
            % 削顶检测：量程是照上一帧峰值定的，信号突然变大就顶穿量程。对称削顶会
            % 凭空长出 3f/5f 假峰（实测能虚高 45 dB，闭环会把它当「空化增强」去追），
            % 所以判本帧作废、扩量程重采，而不是将就记录。
            if clip_retry < 3 && ...
                    (rigol_dho814_clipped(chTx, scTx) || rigol_dho814_clipped(chPcd, scPcd))
                clip_retry = clip_retry + 1;
                n_clip = n_clip + 1;
                [scTx, scPcd] = set_ranges(scope, cfg, chTx, chPcd, scTx, scPcd);
                ui.status(sprintf('%s  检测到削顶，扩量程重采（第 %d 次）', label, clip_retry));
                continue;
            end
            clip_retry = 0;
            pulse = pulse + 1;
            n_good = n_good + 1;
            k = n_good;
            datamat(k, :) = pfc_fitrow(chPcd, acq_n); %#ok<AGROW>
            txmat(k, :) = pfc_fitrow(chTx, acq_n); %#ok<AGROW>
            [fpk, ~] = ui.waveform(datamat(k, :), info.realFs, p.freq_mhz, 'CH2 PCD'); %#ok<ASGLU>
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
            % 按本帧峰值给下一帧定量程（帧首的削顶检查用的就是这两个值）
            [scTx, scPcd] = set_ranges(scope, cfg, chTx, chPcd, scTx, scPcd);
            ui.trend(k, sc, ic, volt, max(30, k + 12), max(volt * 1.5, 40));
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

function [scTx, scPcd] = set_ranges(scope, cfg, chTx, chPcd, scTx, scPcd)
%SET_RANGES 按本帧峰值给下一帧定量程：满量程 ≈ K × 峰值，留出帧间跳变余量。
% 峰值太弱（<0.1 mV）时保持原量程不动 —— 否则会把量程一路压进噪声里，
% 后面任何一次正常大小的信号都会削顶。
K = 1.4;
scTx  = next_scale(scTx,  max(abs(chTx)),  0.001, K);
scPcd = next_scale(scPcd, max(abs(chPcd)), 0.002, K);
writeline(scope, sprintf(':CHANnel%d:SCALe %.6g', cfg.scope_tx_channel, scTx));
writeline(scope, sprintf(':CHANnel%d:SCALe %.6g', cfg.scope_pcd_channel, scPcd));
end

function sc = next_scale(sc, pk, floor_vdiv, K)
if isfinite(pk) && pk > 1e-4
    sc = min(1.0, max(floor_vdiv, pk / K));
end
end

function a = check_burst_window(chTx, fs, p)
%CHECK_BURST_WINDOW 量一次猝发在采集窗里的位置，偏了就把话说清楚。
% 窗没对齐是「静默」错误：频谱照样出峰，但 SC/IC 会被占空比稀释（实测差约 11 dB），
% 而且稀释系数取决于 :TIMebase:MAIN:OFFSet 这个本来不受控的仪器状态。
% setup 里已把它显式归零，这里量一次结果、随数据存盘，免得以后再靠猜。
a = struct('burst_s', NaN, 'win_s', NaN, 'start_s', NaN, 'in_window', NaN);
if isempty(chTx) || ~isfinite(fs) || fs <= 0
    return;
end
win_s = numel(chTx) / fs;
burst_s = p.n_cycle / (p.freq_mhz * 1e6);
env = abs(chTx);
pk = max(env);
if ~(pk > 1e-5)
    fprintf('注意：CH1 里找不到猝发（回读幅度过小），无法校验采集窗对齐。\n');
    return;
end
start_s = (find(env > 0.25 * pk, 1, 'first') - 1) / fs;
inside = min(1, max(0, (win_s - start_s) / burst_s));
a = struct('burst_s', burst_s, 'win_s', win_s, 'start_s', start_s, 'in_window', inside);
if inside < 0.9
    fprintf(['【采集窗未对齐】猝发 %.3f ms、窗 %.3f ms，猝发从窗内 %.3f ms 才开始，' ...
        '只有 %.0f%% 在窗内。\n' ...
        '  SC/IC 会被占空比稀释、标定不稳。setup 已把 :TIMebase:MAIN:OFFSet 归零，' ...
        '若此处仍偏，说明水平位置还受别的设置影响，需在示波器上确认。\n'], ...
        burst_s * 1e3, win_s * 1e3, start_s * 1e3, inside * 100);
else
    fprintf('采集窗对齐 OK：猝发 %.3f ms 全部在窗内（起点 %.3f ms，窗 %.3f ms）\n', ...
        burst_s * 1e3, start_s * 1e3, win_s * 1e3);
end
end

function tf = frame_ok(chPcd, chTx)
tf = (~isempty(chTx) && numel(chTx) >= 256 && max(abs(chTx)) > 5e-5) || ...
    (~isempty(chPcd) && numel(chPcd) >= 256 && max(abs(chPcd)) > 5e-5);
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
