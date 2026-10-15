function L = pcd_param_limits()
%PCD_PARAM_LIMITS 采样点 / 周期数的软件上下限（MATLAB 与网页必须同一套数字）。
%
% 这是调试采集与正式实验共用的唯一上限出处。web/index.html 的 input min/max
% 以及 web/app.js 的即时截断必须抄这里的数字；界面若允许键入 400000、后端再
% 悄悄截成 100000，截图里的数字会骗人。
%
% 上限为什么是 100000 而不是 400000：
%   100k WORD × 2 通道，约 40 MSa/s 仍只有 ~2.5 ms 窗，USB 传得动；
%   旧实验上限 50k 的 2 倍，属于「稍稍放宽」。再往上传输变慢，没有分析收益。
% 周期数硬上限 10000：与网页 input / JS 截断同一套数字。不要再按「假 40 MSa/s 窗」
% 把 n_cycle 静默压到 ~3000——框里写 9990、发生器却跑 3000，截图会骗人。
% 100k 点 @ 12.5 MSa/s ≈ 8 ms 窗，1.5 MHz × 9990 周期 = 6.66 ms，盖得住；
% 示波器窗对不齐由 check_burst_window 报，不改 DG2052 的 BurstCount。
L = struct( ...
    'npts_min', 4096, 'npts_max', 100000, 'npts_default', 40000, ...
    'n_cycle_min', 1, 'n_cycle_max', 10000, 'n_cycle_default', 400);
end
