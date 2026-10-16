function result = pcd_run_experiment(mode, ui)
%PCD_RUN_EXPERIMENT
%  'before'  阶段2：无微泡，猝发，CH1+CH2
%  'open_mb' 阶段3：有微泡开环（输液泵已在跑，不等待注射）
%  'feedback'/'during' 阶段4：基线 + 闭环（同样假定泵已在输液）
%  文献映射（Chien BME Front 2022）：2=PCDcontrol/NoMB；假超声dummy在4基线（有微泡、~18 mVpp/0.2 MPa），不是2；本文无开环治疗组，3为实验室对照。
%  阶段4默认控 2f±20 kHz 窗求和（Fig.6 蓝线，3 MHz 不是 4.5）；峰/底在界面可选。
% ui 为 UI 适配层（实现见 pcd_ui_html，约定接口见 pcd_ui_check）；本函数与界面无关。
global pcd_abort fgen
ui = pcd_ui_check(ui);
cfg = rigol_instr_config();
p = ui.params();
metric = pcd_ctrl_metric(p);   % 默认 2f 窗求和（Fig.6 蓝线）；可选峰/底
use_sum = strcmp(metric, '2f_window_sum');
outdir = ui.outdir();
pcd_abort = false;
token = pcd_visa('token');

mode = lower(char(mode));
lead_cfg = 3e-3;
if isfield(cfg, 'scope_lead_s') && isnumeric(cfg.scope_lead_s) && isfinite(cfg.scope_lead_s) && cfg.scope_lead_s >= 0
    lead_cfg = double(cfg.scope_lead_s);
end
L = pcd_scope_labels();
if L.manual && any(strcmp(mode, {'during', 'feedback'}))
    error('pcd:awg:manual', ...
        '手动信号源不做闭环。请在发生器上自己调电压，用「3 开环」只采集。');
end
scope = pcd_visa('scope');
if L.manual
    fgen = [];
    ui.status('手动信号源：请先在发生器上设好频率、电压并打开输出。电脑只采示波器。');
else
    fgen = pcd_visa('fgen');
end
started_at = datestr(now, 'yyyy-mm-ddTHH:MM:SS');
% 开环 2/3 用「超声参数」电压。Max V 只限制闭环 4，不要拿来截断开环。
if any(strcmp(mode, {'during', 'feedback'}))
    v_out = min(p.volt_mVpp, p.max_mVpp);
    % 假超声常低于治疗电压。触发必须按「马上要打的那档」算，否则 CH1 到不了
    % 触发电平，:SINGle 一直等，界面就停在假超声 0/25。
    base_v = min(p.max_mVpp, max(1, p.base_mVpp));
    v_first = base_v;
else
    v_out = p.volt_mVpp;
    base_v = v_out;
    v_first = v_out;
end
% 触发电平必须低于实际回读峰值（约 Vpp/2）。
% 触发改接到发生器后面板（另一路）时，电平是 TTL，不用这套毫伏。
vpp_v = max(v_first, 1) / 1000;
trig = trig_from_mVpp(v_first);
ttlTrig = isfield(cfg, 'scope_trig_channel') && cfg.scope_trig_channel >= 1 ...
    && cfg.scope_trig_channel <= 4 && round(cfg.scope_trig_channel) ~= cfg.scope_tx_channel;
if ttlTrig
    trig = 1.5;
end
trig0 = trig;   % 触发电平的起始值，做「降档下限」用（见 run_loop 里的失败处理）
burst_s = p.n_cycle / (p.freq_mhz * 1e6);
% 第 8 个参数是 f0：rigol_dho814_capture_geometry 要用它算采样率下限
% （pcd_cav_bands 的参考底带到 3.87×f0，低于 Nyquist 就会静默退化成单 bin）。
info = rigol_dho814_setup(scope, p.fs_target, p.npts, cfg.scope_pcd_channel, trig, 'SINGle', burst_s, p.freq_mhz * 1e6);
% 循环前初值只给第一发（prime）用：按发生器 Vpp 估 CH1，故意偏宽以免 prime 就贴轨。
% 有效帧的量程由 set_ranges 的 K_DIV=1.0（4×余量）按实测峰值更新；prime 帧不入库。
scTx  = max(0.001, vpp_v / 1.4);
scPcd = max(0.001, vpp_v / 1.4);
writeline(scope, sprintf(':CHANnel%d:SCALe %.6g', cfg.scope_tx_channel, scTx));
writeline(scope, sprintf(':CHANnel%d:SCALe %.6g', cfg.scope_pcd_channel, scPcd));
if ttlTrig
    fprintf('PCD 第一档 %.4g mVpp  触发 CH%g 上升沿 %.2f V（发生器后面板，每发一个脉冲）\n', ...
        v_first, round(cfg.scope_trig_channel), trig);
else
    fprintf('PCD 第一档 %.4g mVpp  触发 %.3g mV  （闭环假超声按 base 设触发，勿用治疗电压）\n', v_first, trig * 1e3);
end
% CH1 若接在功放前，回读仍是发生器 mVpp，不能当作声压。
if isfinite(p.amp_gain) && p.amp_gain >= 40
    v_hint = v_out;
    if any(strcmp(mode, {'during', 'feedback'}))
        v_hint = p.max_mVpp;
    end
    vload = (v_hint / 1000) * p.amp_gain;
    fprintf('确认功放已开 ×%.4g    %.4g mVpp → 约 %.3g Vpp\n', p.amp_gain, v_hint, vload);
end

ui.clearTrend();

timeout_s = min(3.0, max(0.9, 3.5 * p.period_s));
% 分析长度 acq_n = 这一发本身的点数，由 rigol_dho814_capture_geometry 一次定死
% （burst_s × fs）。改之前它取自 prime 那一帧的裁剪结果、整轮不再变，于是后续帧
% 长度不足就补零，而频谱未归一化 → SC 与本帧实际长度线性相关，帧间不可比。
n_req = p.npts;
acq_n = n_req;
if isfield(info, 'geom_ok') && info.geom_ok && isfinite(info.acq_n) && info.acq_n >= 256
    acq_n = round(info.acq_n);
    n_req = acq_n;
elseif isfinite(info.realFs) && info.realFs > 0 && burst_s > 0
    % 没有几何信息（CW 调试 / 单次）时沿用旧口径
    n_req = max(256, round(burst_s * info.realFs));
    acq_n = n_req;
end
if isfield(info, 'geom_ok') && info.geom_ok
    fprintf(['采集几何：深度 %s  记录 %.3f ms  fs %.3f MSa/s（目标 %.3g，下限 %.3g）  ' ...
        '这一发 %.3f ms → %d 点  每帧传输 %.0f KB  Nyquist 余量 %.2f×\n'], ...
        info.depth_tag, info.record_s * 1e3, info.fs_planned / 1e6, ...
        info.fs_target / 1e6, info.fs_min / 1e6, burst_s * 1e3, acq_n, ...
        info.transfer_bytes / 1024, info.nyquist_margin);
    if ~isempty(info.geom_note)
        fprintf('  %s\n', info.geom_note);
    end
    if info.nyquist_margin < 1.15
        warning('pcd:geometry:nyquist', ...
            ['Nyquist 相对 %.2f MHz 的参考底带只剩 %.2f× 余量。' ...
             '再低就会让 pcd_band_energy 把频带 clamp 到 Nyquist、退化成单 bin，' ...
             '而且不会报错。请提高 npts 上限、缩短猝发或降低 f0。'], ...
            3.87 * p.freq_mhz, info.nyquist_margin);
    end
else
    fprintf('两路同一段，最长 %.3f ms（%d 点），不超过脉冲 %.3f ms。\n', ...
        n_req / max(info.realFs, 1) * 1e3, n_req, burst_s * 1e3);
end
datamat = [];
txmat = [];
Vrec = [];
Trec = [];    % 每帧入库墙钟（发生器 OUTPUT ON 起，秒）；Fig.6 横轴用它，不用 pulse #
SCrec = [];
ICrec = [];
PKrec = [];   % 2f峰/参考底（闭环控制量）
PKraw = [];   % 2f 窗内 |Y| 峰值（存档）
Flrec = [];   % 参考底 |Y|
peaks_ch1 = [];
harm_db = [];
lead_max = 0;   % 实测「记录开头到这一发起点」的最长空档，用来校准 scope_lead_s
pulse = 0;
save_path = '';
n_good = 0;
prefix = '';
n_clip = 0;      % 因削顶被丢弃并重采的帧数（不入库、不调压、不画点）
n_prime = 0;     % 仅用于标定量程、未入库的帧数
align = struct();% 采集窗对齐自检结果（随数据存盘）
n_dummy = 0;     % 假超声入库帧数（开环 2/3 为 0）
t_us = [];       % 第一声超声（发生器 OUTPUT ON）起的墙钟；PRF 空档也算进 duration_s
us_total = p.duration_s;
phase_limit_s = inf;   % 假超声单独限时；治疗段改回 inf，只受 duration_s 约束
sc0 = NaN;
sc0_pk = NaN;
ic0 = NaN;
sc_tgt = NaN;
sc_hi = NaN;
sc_lo = NaN;

try
    if any(strcmp(mode, {'during', 'feedback'}))
        prefix = ['Sonication_' sanitize_id(p.studyID)];
        ui.status(sprintf('4 闭环  目标 %.1f dB  IC 上限 %.1f dB', p.target_db, p.ic_limit_db));
        fprintf('4 闭环  target_db=%.4g  IC上限 %.4g dB  ctrl=%s\n', p.target_db, p.ic_limit_db, metric);
        % 文献 BaselineDuration = 5 s、PRF 2 Hz，5 秒里大约 10 发都进基线。
        % 这台示波器 USB 大约 1 秒一帧，第一帧还只定量程、不入库。
        % 15 秒大约能留下 10 帧做中位数，接近他们的 10 发，又不会占掉小鼠那两三分钟。
        % 假超声电压界面可调（base_mVpp）。文献 18 mVpp 是他们探头的 0.2 MPa。
        dummy_s = 15;
        t_us = start_burst(fgen, p, base_v);
        cd_push();
        phase_limit_s = dummy_s;
        run_loop(inf, base_v, false, sprintf('4 假超声基线 %.4g mVpp', base_v));
        phase_limit_s = inf;
        if pcd_abort
            cd_off();
            result = save_now();
            return;
        end
        n_dummy = numel(PKrec);
        if n_dummy < 1
            error('pcd:baseline', '基线没有采到有效 CH2 帧。未开始闭环。');
        end
        i0 = 1;
        % 假超声中位数作 SC0。控哪个量，sc_tgt 就用哪个量 —— 与 Fig.6 蓝线对齐时必须是窗求和。
        sc0_pk = median(PKrec(i0:n_dummy), 'omitnan');
        sc0_sum_med = median(SCrec(i0:n_dummy), 'omitnan');
        ic0 = mean(ICrec(i0:n_dummy), 'omitnan');
        if use_sum
            sc0 = sc0_sum_med;
            if ~(isfinite(sc0) && sc0 > 0)
                error('pcd:baseline', '基线 2f 窗求和无效。未开始闭环。');
            end
            fprintf('假超声  SC0=%.4g  目标 %.1f dB → %.4g\n', ...
                sc0, p.target_db, sc0 * (10^(p.target_db / 10)));
        else
            sc0 = sc0_pk;
            if ~(isfinite(sc0) && sc0 > 0)
                error('pcd:baseline', '基线 2f 峰无效。未开始闭环。');
            end
            fprintf('假超声  SC0=%.4g  目标 %.1f dB → %.4g\n', ...
                sc0, p.target_db, sc0 * (10^(p.target_db / 10)));
        end
        sc_tgt = sc0 * (10^(p.target_db / 10));
        sc_hi = sc0 * (10^((p.target_db + 0.4) / 10));
        sc_lo = sc0 * (10^((p.target_db - 0.4) / 10));
        % 假超声结束后从基线电压往上涨，不要跳到治疗电压再 +1 mVpp/帧。
        % USB 大约 1 秒一帧，+1 的话 500→1500 要十几分钟。步进界面可调。
        % 闭环不再按 n_expect 停：USB ~1 帧/s，PRF 5 Hz 时发生器打的发数远多于采到的帧。
        % 停表只看墙钟（含假超声已消耗的时间、PRF 空档）。
        run_loop(inf, base_v, true, ...
            '4 闭环 Feedback', sc_tgt, sc_hi, sc_lo, p.max_mVpp);
    elseif strcmp(mode, 'open_mb')
        prefix = ['OpenMB_' sanitize_id(p.studyID)];
        t_us = start_burst(fgen, p, v_out);
        cd_push();
        run_loop(inf, v_out, false, '3 有微泡开环');
    else
        prefix = ['NoMB_' sanitize_id(p.studyID)];
        t_us = start_burst(fgen, p, v_out);
        cd_push();
        run_loop(inf, v_out, false, '2 无微泡 CH2');
    end
catch err
    pcd_visa('rf_off_if', token);
    cd_off();
    try
        save_now();
    catch
    end
    rethrow(err);
end
pcd_visa('rf_off_if', token);
cd_off();
result = save_now();

    function result = save_now(do_plots)
        % 中途每 5 发只覆盖 raw.mat；分析图只在结束 / 中止时画一次。
        if nargin < 1
            do_plots = true;
        end
        S = pack_save();
        opts = struct('plots', logical(do_plots));
        if ~isempty(save_path)
            opts.rundir = save_path;
        end
        save_path = pcd_save_acquisition(outdir, prefix, S, opts);
        result.file = save_path;
        result.n_pulse = n_good;
        msg = sprintf('已保存  %d 帧有效  墙钟 %.0f s  %s', n_good, us_total, save_path);
        % USB ~1 帧/s，不能用 n_expect（= duration×PRF，发生器发数）当「采够了」。
        if n_good < max(8, round(0.3 * us_total)) && ~strcmp(mode, 'aborted')
            msg = ['【帧数不足，勿当完整实验】  ' msg];
        end
        ui.status(msg);
        fprintf('%s\n', msg);
        report_lead(lead_max, lead_cfg);
    end

    function S = pack_save()
        S = struct();
        S.datamat = datamat;
        S.txmat = txmat;
        S.realFs = info.realFs;
        S.Vrealtime = Vrec;
        S.t_pulse_s = Trec;        % 每帧入库墙钟（OUTPUT ON 起，秒）；USB≠PRF，不能用 pulse #
        S.TimeRecord = Trec;       % 同义，方便旧脚本
        S.t_elapsed_s = NaN;
        if ~isempty(t_us)
            S.t_elapsed_s = toc(t_us);
        end
        S.RampSC = SCrec;          % 所选谐波 ±20 kHz |FFT| 求和（Fig.6 蓝线）
        S.RampIC = ICrec;          % 2.2 f0 ±20 kHz 幅度求和（Sun 2022 的 IC）
        S.Peak2f = PKraw;          % SC 窗内 |Y| 峰
        S.SCctrl = PKrec;          % 窗内峰/底
        S.floorY = Flrec;
        S.ctrl_metric = metric;
        S.sc_harm = p.sc_harm;
        S.peaks_ch1_mhz_db = peaks_ch1;
        S.harm_db = harm_db;
        S.harm_db_cols = 'f0_dB  2f_dB  3f_dB  1.5f_dB  2.5f_dB  0.5f_dB';
        S.harm_halfwidth_mhz = 0.05;    % 2f 记录窗；旧数据是 0.20，会吞进 2.85 EMI
        cav = pcd_cav_bands(p.freq_mhz * 1e6, p.sc_harm);
        S.sc_band_mhz = cav.sc_mhz;
        S.ic_band_mhz = cav.ic_ctrl_mhz;
        S.floor_band_mhz = cav.floor_mhz;
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
        S.n_clip_retry = n_clip;         % 削顶丢弃次数（这些点未进 V/SC/闭环/图）
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
        % 当时设置的完整快照（新增字段，不改上面旧名）。2/3/4 都走这里。
        % 分析图在 pcd_save_acquisition 结束时画一次，不在每发脉冲。
        S.params = pcd_save_params(kind_of(mode), param_src());
        S.n_dummy = n_dummy;
        S.sc0 = sc0;                 % 闭环所用度量的假超声基线
        S.sc0_peak = sc0_pk;
        S.sc0_sum = NaN;
        if n_dummy >= 1 && numel(SCrec) >= 1
            S.sc0_sum = median(SCrec(1:min(n_dummy, numel(SCrec))), 'omitnan');
        end
        S.ic0 = ic0;
        S.sc_tgt = sc_tgt;
        S.sc_hi = sc_hi;
        S.sc_lo = sc_lo;
        S.target_db = p.target_db;
    end

    function src = param_src()
        src = struct();
        try, src.raw = ui.raw(); catch, src.raw = struct(); end
        src.freq_mhz = p.freq_mhz;
        src.volt_mVpp = p.volt_mVpp;
        src.volt_out_mVpp = v_out;
        src.max_mVpp = p.max_mVpp;
        src.base_mVpp = p.base_mVpp;
        src.vstep_mVpp = p.vstep_mVpp;
        src.prf_hz = p.prf_hz;
        src.n_cycle = p.n_cycle;
        src.cav_pct = p.cav_pct;
        src.amp_gain = p.amp_gain;
        src.v_load_Vpp = p.v_load_Vpp;
        src.period_s = p.period_s;
        src.duration_s = p.duration_s;
        src.npts = p.npts;
        src.fs_target = p.fs_target;
        src.realFs = info.realFs;
        src.n_expect = p.n_expect;
        src.target_db = p.target_db;
        src.ic_limit_db = p.ic_limit_db;
        src.n_dummy = n_dummy;
        src.sc0 = sc0;
        src.ic0 = ic0;
        src.ctrl_metric = metric;
        src.sc_harm = p.sc_harm;
        src.studyID = p.studyID;
        src.pcd_scale_vdiv = scPcd;
        src.tx_scale_vdiv = scTx;
        src.waveform_format = info.waveform_format;
        src.trig_v = trig;
        src.sweep = 'SINGle';
        src.started_at = started_at;
        src.scope_tx_channel = info.scope_tx_channel;
        src.scope_pcd_channel = info.scope_pcd_channel;
    end

    function run_loop(max_pulses, volt, do_fb, label, sc_tgt, sc_hi, sc_lo, max_mVpp)
        % 停靠墙钟 t_us（发生器开射频起算，含 PRF 空档），不靠采满 n_expect。
        % max_pulses 仅假超声基线用来凑够帧；治疗段传 inf，USB 能采多少算多少。
        if nargin < 5, sc_tgt = NaN; end
        if nargin < 6, sc_hi = NaN; end
        if nargin < 7, sc_lo = NaN; end
        if nargin < 8, max_mVpp = p.max_mVpp; end
        ramping = true;
        n_high = 0;        % 维持：滤波后连续偏高帧数（单发尖峰不计入）
        n_low = 0;         % 维持：滤波后连续偏低帧数
        n_tgt_hit = 0;     % 爬升：连续原值摸到黄带中心的帧数（单发噪声不切维持）
        n0 = n_good;
        prime = true;      % 第一发：只用来标定量程与校验采集窗（避免初值过宽浪费量化）
        clip_retry = 0;    % 连续削顶重采计数（上限 3，避免一直空转）
        wait_note = '';    % 触发失败时别被「有效 0 帧」盖掉
        acq_mode = 'single';
        n_miss = 0;
        while pcd_visa('alive', token)
            if us_expired() || dummy_done()
                break;
            end
            if isfinite(max_pulses) && (n_good - n0) >= max_pulses
                break;
            end
            tgt = max_pulses;
            if ~isfinite(tgt)
                tgt = NaN;
            end
            cd_push();
            % 只在还没有任何有效帧时用倒计时占状态栏。有帧之后改由本发诊断
            % （CH1 是否驱动、2f 真/EMI/底噪）占着，采集等待期间也能看见。
            % 触发失败时保留原因，不要每圈改回「有效 0 帧」，否则像页面死了。
            if n_good == n0 || dummy_done_pending()
                left = remain_us();
                if dummy_done_pending()
                    left = max(0, phase_limit_s - toc(t_us));
                end
                if ~isempty(wait_note)
                    ui.status(sprintf('%s  %s  剩余 %.0f s', label, wait_note, left));
                elseif isfinite(tgt)
                    ui.status(sprintf('%s  %d / %d  剩余 %.0f s', ...
                        label, n_good - n0, tgt, left));
                else
                    ui.status(sprintf('%s  有效 %d  剩余 %.0f s', ...
                        label, n_good - n0, left));
                end
            end
            [chPcd, ~, realFs, chTx, okTx, leadFrame] = rigol_dho814_acquire_block( ...
                scope, n_req, cfg.scope_pcd_channel, acq_mode, timeout_s, ...
                p.period_s + 0.08, burst_s);
            if ~pcd_visa('alive', token)
                break;
            end
            if isfinite(leadFrame)
                lead_max = max(lead_max, leadFrame);
            end
            if ~frame_ok(chPcd, chTx, okTx, volt)
                n_miss = n_miss + 1;
                show_live(chTx, chPcd, realFs, do_fb);
                % 触发电平只按「连续」失败降档，且设下限。改之前 n_miss==1 就降一半，
                % 而 n_miss 在任何成功帧后清零 —— 于是「成功一帧、失败一帧」交替时
                % 电平一路棘轮到 10 µV，之后噪声在 PRF 空档里就能触发示波器，
                % 采到纯空档、再判失败，实验就废在自我强化的循环里。
                % 下限取该档触发电平的 1/4，不再低于噪声可能触发的水平。
                if n_miss == 3 && ~ttlTrig && trig > 0.25 * trig0
                    trig = max(0.25 * trig0, 0.5 * trig);
                    try
                        writeline(scope, sprintf(':TRIGger:EDGE:LEVel %.8g', trig));
                    catch
                    end
                    wait_note = sprintf('%s 连续三发没等到边沿，电平降到 %.0f mV（下限 %.0f mV），仍是单次', ...
                        pcd_scope_labels().txTag, trig * 1e3, 0.25 * trig0 * 1e3);
                elseif ttlTrig
                    wait_note = sprintf('CH%g 未触发，检查发生器后面板到这一路的 BNC', ...
                        round(cfg.scope_trig_channel));
                elseif ~okTx
                    % 回读读失败就丢这一帧 —— 不是嫌它数据脏，而是裁窗锚在回读检测到的
                    % 发射沿上，没有锚点 PCD 的窗就是任意的，入库等于写进错窗的占空比。
                    wait_note = sprintf('%s 这一帧没读到（USB 毛刺），缺少发射沿锚点，本帧丢弃', ...
                        pcd_scope_labels().txTag);
                else
                    wait_note = sprintf('%s 仍在等发生器这一发，不采空档', ...
                        pcd_scope_labels().txTag);
                end
                ui.status(sprintf('%s  %s  墙钟剩余 %.0f s', label, wait_note, remain_us()));
                continue;
            end
            n_miss = 0;
            wait_note = '';
            if isfinite(realFs) && realFs > 0
                info.realFs = realFs;
            end
            % 第一发只用来标定量程 + 校验采集窗，不入库：量程若按循环前的初值走，
            % 第一帧的竖直分辨率会被白白浪费（实测那一帧的 SC 值是其余帧的 8 倍，
            % 纯粹是量程太宽带来的量化误差）。
            if prime
                prime = false;
                n_prime = n_prime + 1;
                % 这里**不再**改 acq_n。改之前 acq_n = numel(chTx) 只在这一帧定一次，
                % 后续帧长度不足就补零，而频谱未归一化 → 整轮 SC 被这一帧的裁剪长度
                % 定标，且帧间不可比。现在 acq_n 来自采集几何，与帧无关。
                [scTx, scPcd] = set_ranges(scope, cfg, chTx, chPcd, scTx, scPcd);
                align = check_burst_window(chTx, info.realFs, p);
                show_live(chTx, chPcd, info.realFs, do_fb);
                ui.status(sprintf('%s  第 1 屏只定量程，下一发入库  墙钟剩余 %.0f s', ...
                    label, remain_us()));
                continue;
            end
            % 削顶会造假谐波（对称贴轨 → 假 3f/5f，2f 被压），入库会把闭环和图带歪。
            % 策略：每发先按 K_DIV=1.0 留 4× 余量；若仍贴轨，本发不入库、不调压、不画点
            % （不插 NaN，曲线不出现野点），扩量程后重采。连续最多 3 次，避免卡死。
            if rigol_dho814_clipped(chTx, scTx) || rigol_dho814_clipped(chPcd, scPcd)
                n_clip = n_clip + 1;
                [scTx, scPcd] = set_ranges(scope, cfg, chTx, chPcd, scTx, scPcd);
                if clip_retry < 3
                    clip_retry = clip_retry + 1;
                    show_live(chTx, chPcd, info.realFs, do_fb);
                    ui.status(sprintf('%s  削顶已丢弃，扩量程重采（第 %d/3 次）', ...
                        label, clip_retry));
                    continue;
                end
                clip_retry = 0;
                ui.status(sprintf('%s  连续削顶仍丢弃（不入库），下一发再试', label));
                continue;
            end
            clip_retry = 0;
            rowP = pcd_fitrow(chPcd, acq_n);
            rowT = pcd_fitrow(chTx, acq_n);
            % 整形后再判一次：截断/补零后仍贴轨的同样不能进 SC。
            if rigol_dho814_clipped(rowT, scTx) || rigol_dho814_clipped(rowP, scPcd)
                n_clip = n_clip + 1;
                [scTx, scPcd] = set_ranges(scope, cfg, chTx, chPcd, scTx, scPcd);
                ui.status(sprintf('%s  削顶（整形后）已丢弃，不写入 SC', label));
                continue;
            end
            % :SINGle 竞态：上一发停在 STOP 时立刻读会把同一屏再记一次。
            % 调距离时看起来像「走了一步」，其实几何没变。
            if n_good >= 1 && isequal(rowT, txmat(n_good, :)) && isequal(rowP, datamat(n_good, :))
                fprintf('%s  跳过重复帧（示波器仍停在上一发）\n', label);
                continue;
            end
            pulse = pulse + 1;
            n_good = n_good + 1;
            k = n_good;
            datamat(k, :) = rowP; %#ok<AGROW>
            txmat(k, :) = rowT; %#ok<AGROW>
            % 闭环也每发刷新时域+FFT。以前每 5 发且 CH1 不算谱，界面会冻在假超声最后一屏。
            ui.waveform(txmat(k, :), info.realFs, p.freq_mhz, '回读', struct('ch', 'tx', 'fft', true));
            ui.waveform(datamat(k, :), info.realFs, p.freq_mhz, 'PCD', struct('ch', 'pcd', 'fft', true));
            [F, Y, db] = pcd_spectrum(datamat(k, :), info.realFs);
            [sc, ic, ~, ~, M] = pcd_band_energy(Y, F, p.freq_mhz * 1e6, cfg.harmonic_bandwidth_hz, p.sc_harm);
            pk = M.sc_ctrl;
            ic_ctrl = M.ic_ctrl;
            % 调压盯 ctrl：窗求和才能让 Fig.6 蓝线进黄带；峰/底更能到 4 dB 但蓝线对不上。
            if use_sum
                ctrl = sc;
            else
                ctrl = pk;
            end
            fM = F / 1e6;
            % ±50 kHz：给 2f 一点频偏余量，但 2.85 EMI 在 150 kHz 外。
            % 旧值 ±200 kHz 会把 2.85 写进 harm_db 的「2f」列；SC 本身一直是 ±20 kHz。
            grab = @(fm) local_band_db(fM, db, fm, 0.05);
            f0m = p.freq_mhz;
            harm_db(k, :) = [grab(f0m), grab(2*f0m), grab(3*f0m), ...
                grab(1.5*f0m), grab(2.5*f0m), grab(0.5*f0m)]; %#ok<AGROW>
            Vrec(k) = volt; %#ok<AGROW>
            if isempty(t_us)
                Trec(k) = NaN; %#ok<AGROW>
            else
                Trec(k) = toc(t_us); %#ok<AGROW>
            end
            SCrec(k) = sc; %#ok<AGROW>
            ICrec(k) = ic_ctrl; %#ok<AGROW>
            PKrec(k) = pk; %#ok<AGROW>
            PKraw(k) = M.sc_peak; %#ok<AGROW>
            Flrec(k) = M.floor; %#ok<AGROW>
            pp1 = (max(txmat(k, :)) - min(txmat(k, :))) * 1e3;
            pp2 = (max(datamat(k, :)) - min(datamat(k, :))) * 1e3;
            % 闭环不每发再 FFT CH1：峰位只用于状态栏，用时域峰峰值判断有没有驱动。
            if ~do_fb || mod(k, 10) == 1
                [F1, ~, db1] = pcd_spectrum(txmat(k, :), info.realFs);
                [ch1pk, ch1db] = pcd_fft_peak_mhz(F1, db1, 0.3, 8);
            else
                ch1pk = NaN;
                ch1db = NaN;
            end
            peaks_ch1(k, :) = [ch1pk, ch1db]; %#ok<AGROW>
            [scTx, scPcd] = set_ranges(scope, cfg, chTx, chPcd, scTx, scPcd);
            push_trend(k, ctrl, sc, ic_ctrl, volt);
            q2 = pcd_2f_quality(F, db, p.freq_mhz);
            ok1 = (isfinite(ch1pk) && abs(ch1pk - p.freq_mhz) < 0.25 && pp1 >= 0.2 * volt) ...
                || (do_fb && ~isfinite(ch1pk) && pp1 >= 0.2 * volt);
            tags = pcd_scope_labels();
            if ok1
                if isfinite(ch1pk)
                    txmsg = sprintf('%s %.1f mVpp @ %.3f MHz OK', tags.txTag, pp1, ch1pk);
                else
                    txmsg = sprintf('%s %.1f mVpp', tags.txTag, pp1);
                end
            else
                txmsg = sprintf('%s %.2f mVpp @ %s 【回读过弱/不是 %.2f MHz，先查 %s 接线】', ...
                    tags.txTag, pp1, num2str(ch1pk, '%.3f'), p.freq_mhz, tags.txTag);
            end
            if ~ok1 && ~strcmp(q2.flag, 'noise')
                cav = [q2.note '  （' tags.txTag ' 无驱动，2f 不可信）'];
            else
                cav = q2.note;
            end
            ic_hot = false;
            ic_db = NaN;
            % 本发相对假超声。事件阈值默认 1 dB：
            % Sun et al., BME Frontiers, 2022；Chien et al., Sci. Rep., 2022。
            if do_fb && isfinite(ic0) && ic0 > 0 && isfinite(p.ic_limit_db) && ...
                    k >= 1 && isfinite(ICrec(k)) && ICrec(k) > 0
                ic_db = 10 * log10(ICrec(k) / ic0);
                ic_hot = ic_db > p.ic_limit_db;
            end
            left = remain_us();
            cd_push();
            if isfinite(tgt)
                live = sprintf('%s  #%d/%d  剩余 %.0fs  %s  %s %s  %.2f mVpp', ...
                    label, k, tgt, left, txmsg, tags.pcdTag, cav, pp2);
            else
                live = sprintf('%s  #%d  剩余 %.0fs  %s  %s %s  %.2f mVpp', ...
                    label, k, left, txmsg, tags.pcdTag, cav, pp2);
            end
            if ic_hot
                live = sprintf('%s  IC %.1f dB 超上限 %.1f，本发降压', live, ic_db, p.ic_limit_db);
            end
            ui.status(live);
            if ~do_fb
                fprintf('%s  2f_dB=%.1f  f/2=%.1f dB\n', live, harm_db(k, 2), harm_db(k, 6));
            end
            sav_n = 5;
            if do_fb
                sav_n = 15;
            end
            if mod(k, sav_n) == 0
                save_now(false);
            end
            if do_fb
                % 图仍画本发原值。爬升用近 5 发平均；维持用近 7 发中位数。
                % 爬升：离目标 ≥1.8 dB 时 +80 mV/帧，接近黄带再收到 10 mV、3 mV。
                % IC 超上限时本发只降不升。SC 对加电压不再抬头就结束爬升。
                ctrl_f = ctrl;
                i1 = max(n0 + 1, k - 4);
                if use_sum
                    hist = SCrec(i1:k);
                else
                    hist = PKrec(i1:k);
                end
                avg = mean(hist(:), 'omitnan');
                if isfinite(avg) && avg > 0
                    ctrl_f = avg;
                end
                err_db = NaN;
                err_raw = NaN;
                if isfinite(sc_tgt) && sc_tgt > 0 && isfinite(ctrl_f) && ctrl_f > 0
                    err_db = 10 * log10(ctrl_f / sc_tgt);
                end
                if isfinite(sc_tgt) && sc_tgt > 0 && isfinite(ctrl) && ctrl > 0
                    err_raw = 10 * log10(ctrl / sc_tgt);
                end
                if ic_hot
                    % 这一发 IC 窄带比假超声高出上限：电压降 80 mV，SC 本发不动。
                    % 下一发 IC 回到上限以下，SC 继续。上限默认 1 dB（Sun 2022 的 IC 事件）。
                    n_high = 0;
                    n_low = 0;
                    volt = max(1, volt - 80);
                elseif ramping
                    % 快到目标：用本发与平均里更接近目标的那个算步距（平均滞后会让
                    % 单发已到 2 dB 仍大步加）。本发一旦进入黄带就停大步。
                    err_up = err_db;
                    if isfinite(err_raw)
                        if ~(isfinite(err_up))
                            err_up = err_raw;
                        else
                            err_up = max(err_db, err_raw);  % 负得少 = 更接近目标
                        end
                    end
                    raw_in = isfinite(sc_lo) && isfinite(ctrl) && ctrl >= sc_lo;
                    mean_in = isfinite(sc_lo) && isfinite(ctrl_f) && ctrl_f >= sc_lo;
                    flat = false;
                    if k >= n0 + 8 && isfinite(sc0) && sc0 > 0
                        if use_sum
                            aSc = SCrec(k-7:k-4);
                            bSc = SCrec(k-3:k);
                        else
                            aSc = PKrec(k-7:k-4);
                            bSc = PKrec(k-3:k);
                        end
                        dA = median(10 * log10(max(aSc, realmin) / sc0), 'omitnan');
                        dB = median(10 * log10(max(bSc, realmin) / sc0), 'omitnan');
                        if isfinite(dA) && isfinite(dB) && (Vrec(k) - Vrec(k-7)) >= 60 && (dB - dA) < 0.3
                            flat = true;
                        end
                    end
                    if k > n0 + 1 && (raw_in || mean_in || flat)
                        ramping = false;
                        n_high = 0;
                        n_low = 0;
                    else
                        volt = min(max_mVpp, volt + adapt_vstep_mV(err_up, true, true));
                    end
                end
                if ~ramping && ~ic_hot
                    % 维持：黄带（目标 ±0.4 dB）内不动。近 7 发中位数，连续 5 帧
                    % 出带才 ±1 mV。单发从 1 dB 跳到 4 dB 不带动电压。
                    % 近 8 发电压已升 ≥20 mV 而 SC 中位数没抬 0.3 dB，就停止往上加。
                    j1 = max(n0 + 1, k - 6);
                    if use_sum
                        seg = SCrec(j1:k);
                    else
                        seg = PKrec(j1:k);
                    end
                    seg = seg(isfinite(seg) & seg > 0);
                    err_hold = NaN;
                    if numel(seg) >= 3 && isfinite(sc_tgt) && sc_tgt > 0
                        err_hold = 10 * log10(median(seg) / sc_tgt);
                    end
                    if isfinite(err_hold)
                        if err_hold > 0.4
                            n_high = n_high + 1;
                            n_low = 0;
                            if n_high >= 5
                                volt = volt - 1;
                            end
                        elseif err_hold < -0.4
                            n_low = n_low + 1;
                            n_high = 0;
                            stalled = false;
                            if k >= n0 + 8 && isfinite(sc0) && sc0 > 0
                                if use_sum
                                    aSc = SCrec(k-7:k-4);
                                    bSc = SCrec(k-3:k);
                                else
                                    aSc = PKrec(k-7:k-4);
                                    bSc = PKrec(k-3:k);
                                end
                                dA = median(10 * log10(max(aSc, realmin) / sc0), 'omitnan');
                                dB = median(10 * log10(max(bSc, realmin) / sc0), 'omitnan');
                                if isfinite(dA) && isfinite(dB) && (Vrec(k) - Vrec(k-7)) >= 20 && (dB - dA) < 0.3
                                    stalled = true;
                                end
                            end
                            if n_low >= 5 && ~stalled
                                volt = volt + 1;
                            end
                        else
                            n_high = 0;
                            n_low = 0;
                        end
                        volt = min(max_mVpp, max(1, volt));
                    end
                end
                rigol_dg2052_set_vpp_mV(fgen, volt);
            end
        end
    end

    function push_trend(k, ctrl, sc, ic, volt)
        % 实时 SC：10 log10(控制量 / 假超声)，与 Fig.6 / 黄带同一套。开环仍画窗求和。
        is_fb = any(strcmp(mode, {'during', 'feedback'}));
        if is_fb
            ref = sc0;
            if ~(isfinite(ref) && ref > 0) && k >= 1
                if use_sum
                    ref = median(SCrec(1:k), 'omitnan');
                else
                    ref = median(PKrec(1:k), 'omitnan');
                end
            end
            icref = ic0;
            if ~(isfinite(icref) && icref > 0) && k >= 1
                icref = mean(ICrec(1:k), 'omitnan');
            end
            if isfinite(ref) && ref > 0
                sc_tr = 10 * log10(max(ctrl, realmin) / ref);
                if isfinite(icref) && icref > 0
                    ic_tr = 10 * log10(max(ic, realmin) / icref);
                else
                    ic_tr = ic;
                end
                ui.trend(k, sc_tr, ic_tr, volt, max(30, k + 12), max(volt * 1.5, 40));
                return;
            end
        end
        ui.trend(k, sc, ic, volt, max(30, k + 12), max(volt * 1.5, 40));
    end

    function s = remain_us()
        % 距离 duration_s 还剩多少墙钟秒；未开超声则为 0。
        if isempty(t_us) || ~isfinite(us_total)
            s = 0;
            return;
        end
        s = max(0, us_total - toc(t_us));
    end

    function tf = us_expired()
        % 发生器应按墙钟打满 duration_s（含 PRF 空档），到点就停，不等「再采几帧」。
        tf = ~isempty(t_us) && isfinite(us_total) && toc(t_us) >= us_total;
    end

    function tf = dummy_done()
        % 假超声只打 BaselineDuration 那么久，到点就交还给治疗段。
        tf = dummy_done_pending() && toc(t_us) >= phase_limit_s;
    end

    function tf = dummy_done_pending()
        tf = isfinite(phase_limit_s) && ~isempty(t_us);
    end

    function cd_push()
        if ~isfield(ui, 'countdown')
            return;
        end
        ui.countdown(remain_us(), us_total);
    end

    function cd_off()
        if ~isfield(ui, 'countdown')
            return;
        end
        ui.countdown(NaN, NaN);
    end

    function show_live(yTx, yPcd, fs, skip_tx_fft)
        % 未入库的屏也上图，避免触发/削顶时空转、网页一直停在上一实验。
        if ~(isfinite(fs) && fs > 0)
            fs = 40e6;
        end
        if nargin < 4
            skip_tx_fft = false;
        end
        fft_on = ~skip_tx_fft;
        if ~isempty(yTx)
            ui.waveform(yTx, fs, p.freq_mhz, '回读', ...
                struct('ch', 'tx', 'fft', fft_on));
        end
        if ~isempty(yPcd)
            ui.waveform(yPcd, fs, p.freq_mhz, 'PCD', ...
                struct('ch', 'pcd', 'fft', true));
        end
    end
end

function t0 = start_burst(fgen, p, volt)
%START_BURST 下发猝发并开射频。返回墙钟 tic：倒计时从 OUTPUT ON 这一刻起
% （假超声也是超声）。pause 只为等第一发进示波器，不计入「还没开始」。
% 手动信号源已经在面板上打开：这里不下发任何指令。
if pcd_scope_labels().manual
    t0 = tic;
    pause(0.2);
    return;
end
cfg = rigol_instr_config();
rigol_dg2052_apply_burst(fgen, cfg.awg_channel, p.freq_mhz, volt, 0, p.n_cycle, p.period_s);
rigol_dg2052_output_set(fgen, true);
t0 = tic;
pause(p.period_s + 0.15);
end

function [scTx, scPcd] = set_ranges(scope, cfg, chTx, chPcd, scTx, scPcd)
%SET_RANGES 按本帧峰值给下一帧定量程，预先留 4× 竖直余量。
% 削顶会造假谐波，入库会把闭环和图带歪：贴轨帧由主循环丢弃并重采，这里只放宽量程。
%
% K_DIV=1.0：SCALe = 峰值 / K_DIV，即峰值只占 1.0 格。
% DHO814 竖直 8 格、0 V 居中 → 半边满量程 4 格 = 4×本帧峰值（约 12 dB 余量）。
% 旧 K_DIV=1.4 只有 ≈2.8×，空化突跳仍会贴轨。
% 代价：LSB 约粗 1.4 倍（竖直分辨率略差），换少贴轨。
% 峰值太弱（<0.1 mV）保持原量程，避免把量程压进噪声。
K_DIV = 1.0;
scTx0 = scTx;
scPcd0 = scPcd;
scTx  = next_scale(scTx,  max(abs(chTx)),  0.001, K_DIV);
scPcd = next_scale(scPcd, max(abs(chPcd)), 0.002, K_DIV);
% 本发已贴轨则真实峰值未知（>满量程），再 ×1.5 给重采/下一发。
% DHO814 竖直最大 10 V/div。以前封在 1 V/div，回读超过约 ±4 V 就每帧削顶、
% 一帧都不入库，结束时没有波形，分析图也就不画。
if rigol_dho814_clipped(chTx, scTx0)
    scTx = min(10, 1.5 * scTx);
end
if rigol_dho814_clipped(chPcd, scPcd0)
    scPcd = min(10, 1.5 * scPcd);
end
% 量程几乎没变就不要每发写两次 :CHANnel:SCALe（USB 往返比 FFT 还慢）。
if abs(scTx - scTx0) / max(scTx0, 1e-6) > 0.08
    writeline(scope, sprintf(':CHANnel%d:SCALe %.6g', cfg.scope_tx_channel, scTx));
end
if abs(scPcd - scPcd0) / max(scPcd0, 1e-6) > 0.08
    writeline(scope, sprintf(':CHANnel%d:SCALe %.6g', cfg.scope_pcd_channel, scPcd));
end
end

function sc = next_scale(sc, pk, floor_vdiv, K)
if isfinite(pk) && pk > 1e-4
    sc = min(10, max(floor_vdiv, pk / K));
end
end

function a = check_burst_window(chTx, fs, p)
%CHECK_BURST_WINDOW 量一次猝发在采集窗里的位置，偏了就把话说清楚。
% 窗没对齐是「静默」错误：频谱照样出峰，但 SC/IC 会被占空比稀释（实测差约 11 dB）。
% 这里量脉冲在窗里实际占了多长，不只看窗的长度。
a = struct('burst_s', NaN, 'win_s', NaN, 'start_s', NaN, 'in_window', NaN);
if isempty(chTx) || ~isfinite(fs) || fs <= 0
    return;
end
win_s = numel(chTx) / fs;
burst_s = p.n_cycle / (p.freq_mhz * 1e6);
n0 = max(8, round(0.1e-3 * fs));
lead = mean(abs(chTx(1:min(numel(chTx), n0))));
acrms = sqrt(mean((chTx - mean(chTx)) .^ 2));
if lead > 0.15 && win_s <= burst_s * 1.05
    a = struct('burst_s', burst_s, 'win_s', win_s, 'start_s', 0, ...
        'in_window', min(1, win_s / burst_s));
    if acrms < 0.015
        fprintf(['采集窗在脉冲里：窗 %.3f ms，开头已经在这一发上。' ...
            '这段是电平，不是正弦（起伏 %.1f mV）。\n'], ...
            win_s * 1e3, acrms * 1e3);
    else
        fprintf('采集窗在脉冲里：窗 %.3f ms，开头已经在这一发上，脉冲 %.3f ms。\n', ...
            win_s * 1e3, burst_s * 1e3);
    end
    return
end
nq = max(8, floor(0.15 * numel(chTx)));
[~, ord] = sort(abs(chTx(:)));
base = median(chTx(ord(1:nq)));
env = abs(chTx - base);
pk = max(env);
if ~(pk > 0.01)
    fprintf('注意：%s 几乎是直流（峰峰值 %.2f mV），这一发没有正弦。\n', ...
        pcd_scope_labels().txTag, (max(chTx) - min(chTx)) * 1e3);
    return;
end
i1 = find(env > 0.25 * pk, 1, 'first');
i2 = find(env > 0.25 * pk, 1, 'last');
start_s = (i1 - 1) / fs;
dur_s = (i2 - i1 + 1) / fs;
inside = min(1, max(0, dur_s / burst_s));
a = struct('burst_s', burst_s, 'win_s', win_s, 'start_s', start_s, 'in_window', inside);
% 脉冲一直顶到窗的末尾：窗比脉冲短，但采的是脉冲开头，没有把后面的空档算进去。
reaches_end = i2 >= numel(chTx) - max(1, round(0.05e-3 * fs));
if start_s <= 0.3e-3 && win_s <= burst_s * 1.02 && (inside >= 0.9 || reaches_end)
    fprintf('采集窗在脉冲里：窗 %.3f ms，从 %.3f ms 起，脉冲 %.3f ms（窗内 %.3f ms）。\n', ...
        win_s * 1e3, start_s * 1e3, burst_s * 1e3, dur_s * 1e3);
else
    fprintf(['【采集窗未对齐】脉冲 %.3f ms、窗 %.3f ms，脉冲从 %.3f ms 到 %.3f ms，' ...
        '窗里只有 %.3f ms（%.0f%%）。\n'], ...
        burst_s * 1e3, win_s * 1e3, start_s * 1e3, (i2 - 1) / fs * 1e3, ...
        dur_s * 1e3, inside * 100);
end
end

function tf = frame_ok(chPcd, chTx, okTx, volt_mVpp)
%FRAME_OK 这一帧能不能入库。判据是**相对本发电压**的，不是绝对毫伏。
%
% 改之前是 swing > 0.2（200 mVpp）|| acrms > 0.02（20 mVrms），与这一发实际打多大
% 无关。正弦 acrms = Vpp/2√2，所以回读低于 ≈56.6 mVpp 就恒判 false —— 而假超声档
% 本来就设计成低电压（代码注释里把文献的 18 mVpp 当合法工作点）。后果：整轮 0 帧，
% 最后抛「基线没有采到有效 CH2 帧」，错误信息指不到真因。
%
% 现在：门限 = 本发电压的一个小比例，并保留绝对下限防止 volt 未知时退化成
% 「有噪声就算过」。
%
% 回读读失败时仍然丢帧 —— 不是因为它「数据脏」，而是因为**没有回读就没有猝发起点**：
% 裁窗锚在回读检测到的发射沿上（crop_fixed / crop_same），丢了锚点 PCD 的窗就是
% 任意的，入库等于把错窗的占空比写进 SC。所以这里丢帧是对的，真正要修的是别因为
% 单帧失败就把触发电平棘轮下去（见 run_loop）。
if isempty(chPcd) || numel(chPcd) < 256
    tf = false;
    return
end
if nargin >= 3 && ~okTx
    tf = false;
    return
end
if nargin < 4 || ~(isscalar(volt_mVpp) && isfinite(volt_mVpp) && volt_mVpp > 0)
    volt_mVpp = 0;
end
if isempty(chTx) || numel(chTx) < 256
    tf = false;
    return
end
swing = max(chTx) - min(chTx);
acrms = sqrt(mean((chTx - mean(chTx)) .^ 2));
% 相对门限：本发 Vpp 的 10%（acrms 口径）；volt 未知时退回原来的绝对下限。
floor_v = max(0.002, 0.10 * volt_mVpp / 1000);
tf = swing > 0.2 * max(volt_mVpp / 1000, 0.02) || acrms > floor_v;
if tf && numel(chPcd) ~= numel(chTx)
    tf = false;
end
end

function k = kind_of(mode)
switch lower(char(mode))
    case {'during', 'feedback'}
        k = 'feedback';
    case 'open_mb'
        k = 'open_mb';
    otherwise
        k = 'nomb';
end
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

function report_lead(lead_max, lead_cfg)
%REPORT_LEAD 把实测的「记录开头到这一发起点」空档报出来，用来校准 scope_lead_s。
%
% 这个数直接决定采样率：rigol_dho814_capture_geometry 要按它给记录留余量，
% 留得越多、装下这一发需要的点数越多、fs 越低。默认 3e-3 是照注释里「1–3 ms」
% 的实测上界保守取的；实测值更小就调小 rigol_config.ini 里的 scope_lead_s，fs 会回升。
% 不报出来这个数就只能一直靠猜，而它一个数量级的差别能决定 6.6 ms 的窗装不装得下。
if ~isfinite(lead_max) || lead_max <= 0
    return
end
fprintf(['实测前置空档最长 %.3f ms（记录开头到这一发起点）。\n' ...
    '  当前 scope_lead_s = %.3f ms。若实测明显更小，把它改小可提高采样率：' ...
    'rigol_config.ini 里 scope_lead_s=%.6g，或在 MATLAB 里 ' ...
    'cfg = rigol_instr_config(); cfg.scope_lead_s = %.6g; rigol_instr_config(''save'', cfg);\n'], ...
    lead_max * 1e3, lead_cfg * 1e3, max(1.2 * lead_max, 0.2e-3), max(1.2 * lead_max, 0.2e-3));
end

function t = trig_from_mVpp(mV)
% 单次采集要等发生器正弦跨过这个电平才开始记，空档里就停着。
% 以前上限 0.5 mV，噪声就能触发，窗里经常没有这一发。
% 取设定 Vpp 的 8%，限制在 15–150 mV：1 Vpp 约 80 mV，200 mVpp 约 16 mV。
vpp_v = max(mV, 1) / 1000;
t = min(0.15, max(0.015, 0.08 * vpp_v));
end

function mag = adapt_vstep_mV(err_db, want_up, is_ramp)
% 爬升：开始远（≥2.5 dB）+35 mV；差 <1 dB 收到 2–4 mV。步距按本发/平均里更近目标的那个。
if nargin < 3
    is_ramp = true;
end
if ~(isfinite(err_db))
    if is_ramp && want_up
        mag = 80;
    else
        mag = 4;
    end
    return
end
a = abs(err_db);
if is_ramp && want_up
    % 小鼠只有两三分钟，USB 约 1 帧/秒。离目标远时大步，进黄带前收住。
    if a >= 1.8
        mag = 80;
    elseif a >= 1.0
        mag = 40;
    elseif a >= 0.5
        mag = 10;
    else
        mag = 3;
    end
    return
end
if ~want_up
    if a >= 1.5
        mag = 8;
    elseif a >= 0.6
        mag = 4;
    else
        mag = 2;
    end
    return
end
if a >= 0.8
    mag = 4;
elseif a >= 0.4
    mag = 2;
else
    mag = 1;
end
end
