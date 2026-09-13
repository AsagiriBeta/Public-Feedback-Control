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
fails = fails + expect(~rigol_dho814_clipped(sine(0.0076), 0.002), '7.6 mV 正弦不判削顶');
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
    for K = [3.2 1.4]
        sc = max(0.002, mx(1) / K);
        retry = 0;
        for k = 1:n
            tries = 0;
            while mx(k) >= 0.98 * FS * sc
                if tries >= 3, break; end
                tries = tries + 1;
                retry = retry + 1;
                sc = max(0.002, mx(k) / K);
            end
            if mx(k) > 1e-4, sc = max(0.002, mx(k) / K); end
        end
        tag = '上一版 /3.2';
        if K < 2, tag = '本次 K=1.4'; end
        fprintf('  K=%-4.1f 需重采 %2d 帧   （%s）\n', K, retry, tag);
        if K < 2
            fails = fails + expect(retry == 0, 'K=1.4 时真实数据无需削顶重采');
        end
    end
end

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
