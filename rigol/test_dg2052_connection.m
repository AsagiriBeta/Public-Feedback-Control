%% RIGOL DG2052 连接与控制自检脚本
% 用法：在 MATLAB 中打开本文件点击「运行」，或在项目根目录执行：
%       run('rigol/test_dg2052_connection.m')
%
% 前置：已安装 Instrument Control Toolbox；USB 驱动与 VISA 正常；已在
%       rigol_instr_config.m 中填写正确的 cfg.awg_visa（可用 visadevlist 查看）。

%% ========== 用户选项 ==========
% false：仅查询 *IDN*、写入频率/幅度并回读，不打开前面板 RF 输出（最安全）。
% true ：在通过上述检查后，将输出打开约 2 秒再关闭——请先确认负载/功放/换能器安全。
enable_output_pulse = false;

%% ========== 路径与工具箱 ==========
rigolDir = fileparts(mfilename('fullpath'));
addpath(rigolDir);

if isempty(ver('instrument'))
    error('test_dg2052:NoToolbox', '未检测到 Instrument Control Toolbox，无法使用 visadev。');
end
if ~exist('visadev', 'file')
    error('test_dg2052:NoVisadev', '当前 MATLAB 版本无 visadev，请升级到支持 visadev 的版本（建议 R2020b+）。');
end

cfg = rigol_instr_config();
if contains(cfg.awg_visa, 'YOUR_', 'IgnoreCase', true)
    error('test_dg2052:Config', ['请在 rigol_instr_config.m 中将 awg_visa 改为本机 VISA 地址。\n' ...
        '在命令窗口执行 visadevlist 可列出设备。']);
end

ch = cfg.awg_channel;
src = sprintf('SOURce%d', ch);
outTag = sprintf('OUTPut%d', ch);

fprintf('连接 AWG: %s\n', cfg.awg_visa);
dev = visadev(cfg.awg_visa);
dev.Timeout = 15;

cleanupObj = onCleanup(@() dg2052_test_cleanup(dev, ch));

%% ---------- 1) 识别 ----------
writeline(dev, '*IDN?');
idn = strtrim(char(readline(dev)));
fprintf('[OK] *IDN? -> %s\n', idn);

%% ---------- 2) 关闭输出，避免残留 ----------
writeline(dev, [':' outTag ':STATe OFF']);

%% ---------- 3) 写参数并回读（验证程控）----------
% 连续正弦、1 kHz、20 mVpp，与主程序一致的 VPP 单位
writeline(dev, [':' src ':FUNCtion SINusoid']);
writeline(dev, sprintf(':%s:FREQuency 1000', src));
writeline(dev, sprintf(':%s:VOLTage:UNIT VPP', src));
writeline(dev, sprintf(':%s:VOLTage 0.02', src));
writeline(dev, sprintf(':%s:BURSt:STATe OFF', src));
writeline(dev, sprintf(':%s:PHASe 0', src));
writeline(dev, [':' outTag ':LOAD INFinity']);

writeline(dev, sprintf(':%s:FREQuency?', src));
f_rd = str2double(strtrim(char(readline(dev))));
writeline(dev, sprintf(':%s:VOLTage?', src));
v_rd = str2double(strtrim(char(readline(dev))));

if abs(f_rd - 1000) > 0.5
    warning('test_dg2052:FreqReadback', '频率回读 %.6g Hz，与设定 1000 Hz 偏差较大。', f_rd);
else
    fprintf('[OK] 频率回读: %.6g Hz\n', f_rd);
end
if abs(v_rd - 0.02) > 1e-4
    warning('test_dg2052:VoltReadback', '幅度回读 %.6g Vpp，与设定 0.02 Vpp 偏差较大。', v_rd);
else
    fprintf('[OK] 幅度回读: %.6g Vpp\n', v_rd);
end

%% ---------- 4) 猝发命令（与主 GUI 同一路径）----------
try
    rigol_dg2052_apply_burst(dev, ch, 1.0, 20, 0, 10, 0.01);
    fprintf('[OK] rigol_dg2052_apply_burst 已执行（1 MHz, 10 周期/猝发, 100 Hz PRF, 20 mVpp）。\n');
catch ME
    warning('test_dg2052:Burst', '猝发配置失败（可对照 DG2000 编程手册核对 SCPI）：%s', ME.message);
end

%% ---------- 5) 可选：短脉冲输出 ----------
if enable_output_pulse
    fprintf('\n*** 即将打开 CH%d 输出约 2 秒 — 确认负载与下游设备安全 ***\n', ch);
    pause(1);
    writeline(dev, [':' outTag ':STATe ON']);
    pause(2);
    writeline(dev, [':' outTag ':STATe OFF']);
    fprintf('[OK] 输出测试完成，已关闭输出。\n');
else
    fprintf('\n未开启射频输出（enable_output_pulse = false）。连接与写读已验证。\n');
end

fprintf('\n全部检查结束。\n');

function dg2052_test_cleanup(dev, ch)
try
    writeline(dev, sprintf('OUTPut%d:STATe OFF', ch));
catch
end
end
