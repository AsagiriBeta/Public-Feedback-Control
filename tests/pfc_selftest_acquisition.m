function pfc_selftest_acquisition()
%PFC_SELFTEST_ACQUISITION 采集链自检：不需要接仪器也能跑。
%
%   pfc_selftest_acquisition
%
% 覆盖三处「改了就会静默出错」的地方（详见 README「采集链」一节）：
%   1) WORD 波形解码（字节序 / 有符号 / 奇数长度）
%   2) 削顶判定（rigol_dho814_clipped）
%   3) 量程策略：拿真实数据回放，看还会不会有帧顶穿量程
%
% 第 3 项在 data/ 里找不到 OpenMB 数据时自动跳过。
% 第 4 项用合成正弦在 tempdir 里走一遍新的「一目录/次」存盘，不碰 data/。
% 这是回归护栏：改动 rigol/ 或 pfc_run_experiment 的采集部分后请跑一遍。
cd(fileparts(fileparts(mfilename('fullpath'))));
pfc_setup();

fails = 0;

% ---------------------------------------------------------------- 1) 解码
fprintf('=== 1) WORD 波形解码 ===\n');
codes = [0 1 -1 32767 -32768 1234 -1234 4095 -4096];
b = zeros(1, 2 * numel(codes), 'uint8');
for i = 1:numel(codes)
    u = codes(i);
    if u < 0, u = u + 65536; end
    b(2 * i - 1) = uint8(mod(u, 256));      % 低字节在前（小端）
    b(2 * i) = uint8(floor(u / 256));
end
fails = fails + expect(isequal(rigol_decode_waveform(b, 'WORD'), codes), ...
    'WORD 往返（含 ±32767/±32768 边界）');
fails = fails + expect(numel(rigol_decode_waveform(b(1:end-1), 'WORD')) == numel(codes) - 1, ...
    '奇数长度容错（丢掉半个样本而不是崩）');

% 手册没写 WORD 是有符号补码还是偏移二进制，两种固件约定都要能吃（靠 YREFerence 判）
u = [32768 33768 31768 10];
bo = zeros(1, 2 * numel(u), 'uint8');
for i = 1:numel(u)
    bo(2 * i - 1) = uint8(mod(u(i), 256));
    bo(2 * i) = uint8(floor(u(i) / 256));
end
fails = fails + expect(isequal(rigol_decode_waveform(bo, 'WORD', 32768), u), ...
    '偏移二进制约定（yref≈32768）还原为无符号');
fails = fails + expect(isequal(rigol_decode_waveform(bo, 'WORD', 0), ...
    [-32768 -31768 31768 10]), '有符号补码约定（yref≈0）按补码解');

% ---------------------------------------------------------------- 2) 削顶判定
fprintf('\n=== 2) 削顶判定（SCALe = 2 mV/div，标称满量程 ±8.0 mV）===\n');
fs = 31.25e6;
t = (0:3999) / fs;
sine = @(a) a * sin(2 * pi * 1.5e6 * t);
fails = fails + expect(~rigol_dho814_clipped(sine(0.0060), 0.002), '6.0 mV 正弦不判削顶');
fails = fails + expect(~rigol_dho814_clipped(sine(0.0070), 0.002), '7.0 mV 正弦不判削顶');
fails = fails + expect(rigol_dho814_clipped(sine(0.0076), 0.002), '7.6 mV（95% 满格）判削顶');
fails = fails + expect(rigol_dho814_clipped(sign(sine(1)) * 0.0087, 0.002), '8.7 mV 平顶判削顶');
fails = fails + expect(~rigol_dho814_clipped([], 0.002), '空帧不误判');

% ---------------------------------------------------------------- 3) 量程策略
fprintf('\n=== 3) 量程策略回放（真实数据）===\n');
f = 'data/OpenMB_ID_20260909_212548move-success.mat';
if ~isfile(f)
    fprintf('  跳过：找不到 %s\n', f);
else
    S = load(f, 'datamat');
    D = S.datamat;
    n = size(D, 1);
    mx = zeros(n, 1);
    for k = 1:n, mx(k) = max(abs(D(k, :))); end
    % 满量程系数实测值：真削顶帧的 峰值/(scope_vdiv/2 × SCALe) 恒为 1.092
    FS = 1.092 * (rigol_instr_config().scope_vdiv / 2);
    for K = [1.4 1.0]
        sc = max(0.002, mx(1) / K);
        retry = 0;
        for k = 2:n
            % 4× 余量仍贴轨则丢弃并按本帧峰值重定量程（模拟重采后的下一发）。
            tries = 0;
            while mx(k) >= 0.98 * FS * sc
                if tries >= 3, break; end
                tries = tries + 1;
                retry = retry + 1;
                sc = max(0.002, mx(k) / K);
            end
            if mx(k) > 1e-4, sc = max(0.002, mx(k) / K); end
        end
        tag = '旧 K=1.4（≈2.8×）';
        if K < 1.2, tag = '本次 K=1.0（4×余量，贴轨丢弃重采）'; end
        fprintf('  K=%-4.1f 需重采 %2d 帧   （%s）\n', K, retry, tag);
    end
end

% ---------------------------------------------------------------- 4) 存盘目录
fprintf('\n=== 4) 每次保存一个目录（raw.mat + 图）===\n');
td = fullfile(tempdir, sprintf('pfc_save_selftest_%s', datestr(now, 'yyyymmdd_HHMMSS')));
fs = 40e6;
f0 = 1.5e6;
nn = 2048;
tt = (0:nn-1) / fs;
tx = 0.05 * sin(2 * pi * f0 * tt);
pcd = 0.001 * sin(2 * pi * 2 * f0 * tt);
S = struct();
S.txmat = [tx; tx];
S.datamat = [pcd; 1.1 * pcd];
S.realFs = fs;
S.freq_MHz = 1.5;
S.volt_mVpp = 20;
S.Vrealtime = [20; 20];
S.RampSC = [1.0; 1.2];
S.RampIC = [0.5; 0.6];
S.n_good = 2;
S.n_expect = 2;
S.npts = nn;
S.params = pfc_save_params('open_mb', struct('freq_mhz', 1.5, 'volt_mVpp', 20, ...
    'prf_hz', 1, 'n_cycle', 100, 'npts', nn, 'realFs', fs));
try
    rundir = pfc_save_acquisition(td, 'OpenMB_selftest', S);
    raw = fullfile(rundir, 'raw.mat');
    fails = fails + expect(isfolder(rundir), '返回值是本次目录');
    fails = fails + expect(isfile(raw), '目录里有 raw.mat');
    fails = fails + expect(isfile(fullfile(rundir, 'params.txt')), '目录里有 params.txt');
    L = load(raw);
    fails = fails + expect(isfield(L, 'datamat') && isequal(size(L.datamat), [2 nn]), ...
        'raw.mat 仍用旧字段名，load 与扁平 mat 一样');
    fails = fails + expect(isfield(L, 'params') && isstruct(L.params), 'raw.mat 含 params');
    pngs = {'fft_ch1.png', 'fft_ch2.png', 'time_ch1_ch2.png', 'pulse_sc_ic.png'};
    for i = 1:numel(pngs)
        fails = fails + expect(isfile(fullfile(rundir, pngs{i})), ['写出 ' pngs{i}]);
    end
    % 中途备份：同一目录覆盖 raw，不出第二套图时间戳
    S.n_good = 3;
    S.txmat = [S.txmat; tx];
    S.datamat = [S.datamat; pcd];
    same = pfc_save_acquisition(td, 'OpenMB_selftest', S, struct('plots', false, 'rundir', rundir));
    fails = fails + expect(strcmp(same, rundir), '中途备份复用同一目录');
    L2 = load(raw);
    fails = fails + expect(isfield(L2, 'n_good') && L2.n_good == 3, '中途备份覆盖 raw.mat');
    oldflat = 'data/OpenMB_ID_20260909_212548move-success.mat';
    fails = fails + expect(~contains(rundir, 'fft_OpenMB_'), '不写到事后分析用的 fft_OpenMB_* 目录');
    if isfile(oldflat)
        fails = fails + expect(isfile(oldflat), '不改动旧扁平 *_run_*.mat');
    end
catch err
    fails = fails + expect(false, sprintf('存盘自检异常：%s', err.message));
end
try
    if exist(td, 'dir')
        rmdir(td, 's');
    end
catch
end

% ---------------------------------------------------------------- 5) 空化率 / 功放
fprintf('\n=== 5) 空化率 ↔ 周期数、功放增益 ===\n');
fails = fails + expect(abs(pfc_duty('cav_pct', 3000, 1.5, 5) - 1) < 1e-12, ...
    '1.5 MHz PRF 5 Hz 3000 cyc → 空化率 1%');
fails = fails + expect(pfc_duty('n_cycle', 1, 1.5, 5) == 3000, '空化率 1% → 3000 周期');
fails = fails + expect(pfc_duty('n_cycle', 1, 1.5, 2) == 7500, '空化率 1% @ PRF 2 Hz → 7500 周期');
fails = fails + expect(pfc_duty('n_cycle', 100, 1.5, 2) == 10000, ...
    '空化率过大时周期数截到 10000（不静默 3000）');
p9990 = pfc_fus_params(struct('freq_mhz', 1.5, 'volt_mVpp', 50, 'prf_hz', 2, ...
    'n_cycle', 9990, 'duration_s', 1, 'npts', 40000));
fails = fails + expect(p9990.n_cycle == 9990, 'fus_params 9990 周期不被假 40 MSa/s 窗截断');
fails = fails + expect(abs(p9990.amp_gain - 40) < 1e-12, '功放增益默认 40');
fails = fails + expect(abs(p9990.v_load_Vpp - 2) < 1e-12, '50 mVpp ×40 → 2 Vpp');
Psave = pfc_save_params('open_mb', struct('freq_mhz', 1.5, 'volt_mVpp', 100, ...
    'amp_gain', 40, 'prf_hz', 5, 'n_cycle', 3000, 'npts', 4096));
fails = fails + expect(isfield(Psave, 'cav_pct') && abs(Psave.cav_pct - 1) < 1e-9, ...
    'save_params 含 cav_pct = 1');
fails = fails + expect(isfield(Psave, 'amp_gain') && Psave.amp_gain == 40 && ...
    abs(Psave.v_load_Vpp - 4) < 1e-12, 'save_params 100 mVpp ×40 → 4 Vpp');

% ---------------------------------------------------------------- 6) 目标 dB / 控制量（不锁死 2 dB）
fprintf('\n=== 6) target_db 与 ctrl_metric（无硬件）===\n');
base = struct('freq_mhz', 1.5, 'volt_mVpp', 50, 'prf_hz', 2, ...
    'n_cycle', 400, 'duration_s', 1, 'npts', 40000);
S4 = base; S4.target_db = 4;
p4 = pfc_fus_params(S4);
fails = fails + expect(abs(p4.target_db - 4) < 1e-12, '用户填 4 dB 不被改成 2');
S2 = base; S2.target_db = 2;
p2 = pfc_fus_params(S2);
fails = fails + expect(abs(p2.target_db - 2) < 1e-12, '用户填 2 dB 保持 2');
pdef = pfc_fus_params(base);
fails = fails + expect(abs(pdef.target_db - 2) < 1e-12, '没填目标时缺省才是 2');
Sstr = base; Sstr.target_db = '3';
pstr = pfc_fus_params(Sstr);
fails = fails + expect(abs(pstr.target_db - 3) < 1e-12, '字符串 3 也当成 3 dB，不退回 2');
sc0 = 1.0;
fails = fails + expect(abs(sc0 * (10^(p4.target_db / 10)) - 10^(0.4)) < 1e-12, ...
    'sc_tgt 用本次 target_db（4 dB → ×10^0.4）');
fails = fails + expect(strcmp(pfc_ctrl_metric(), '2f_window_sum'), '新实验缺省窗求和');
fails = fails + expect(strcmp(pfc_ctrl_metric(struct(), 'recorded'), '2f_peak_over_floor'), ...
    '旧 raw 没写字段时按峰/底读');
Spk = base; Spk.ctrl_metric = '2f_peak_over_floor';
ppk = pfc_fus_params(Spk);
fails = fails + expect(strcmp(ppk.ctrl_metric, '2f_peak_over_floor'), '界面可选峰/底');
Ssum = base; Ssum.ctrl_metric = '2f_window_sum';
psum = pfc_fus_params(Ssum);
fails = fails + expect(strcmp(psum.ctrl_metric, '2f_window_sum'), '界面可选窗求和');
S3 = base; S3.sc_harm = '3f';
p3h = pfc_fus_params(S3);
fails = fails + expect(strcmp(p3h.sc_harm, '3f'), 'SC 频点可选 3f');
B3 = pfc_cav_bands(1.5e6, '3f');
fails = fails + expect(abs(B3.sc_mhz - 4.5) < 1e-9, '1.5 MHz × 3f = 4.5 MHz');
B2 = pfc_cav_bands(1.5e6, '2f');
fails = fails + expect(abs(B2.sc_mhz - 3.0) < 1e-9, '1.5 MHz × 2f = 3.0 MHz');

fprintf('\n%s\n', repmat('-', 1, 46));
if fails == 0
    fprintf('采集链自检通过\n');
else
    fprintf('采集链自检失败：%d 项\n', fails);
end
end

function n = expect(ok, name)
if ok
    fprintf('  [OK]   %s\n', name);
    n = 0;
else
    fprintf('  [FAIL] %s\n', name);
    n = 1;
end
end
