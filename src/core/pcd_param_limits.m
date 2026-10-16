function L = pcd_param_limits()
%PCD_PARAM_LIMITS 采样点 / 周期数的软件上下限（MATLAB 与网页必须同一套数字）。
%
% 这是调试采集与正式实验共用的唯一上限出处。web/index.html 的 input min/max
% 以及 web/app.js 的即时截断必须抄这里的数字；界面若允许键入 400000、后端再
% 悄悄截成 100000，截图里的数字会骗人。
%
% ---- npts 的语义（已变，别再按旧注释理解）----
% 采集窗长度现在由**这一发的猝发长度**决定，见 rigol_dho814_capture_geometry：
%   fs      : 要满足 pcd_cav_bands 的最高频带（参考底带 3.87×f0）落在 Nyquist 内
%   深度档  : 满足 fs ≥ fs_min 的最小标准档，且不小于 npts
%   记录长度: 至少装下「前置空档 + 猝发」
% 所以：
%   npts      = 深度档的**下界**（沿用旧语义，保证不会比用户要的还少），不再是时基来源。
%   npts_max  = **传输预算**上限。传输量 = 深度档 × 2 通道 × 2 B，只由深度档决定。
%
% ---- 为什么默认 100000 ----
% 100k 档 → 每帧约 400 KB（2 通道 WORD）。USB 下一帧约 0.2–1 s，这是日常实验的
% 合适量级：猝发在 ~2.7 ms 以内都能装下，且各频带 Nyquist 余量充足。
%
% ---- 想采满 6.6 ms（n_cycle ≈ 9990 @1.5 MHz）怎么办 ----
% 6.6 ms 的窗加上前置空档（默认按 3 ms 预留）合起来约 11 ms。100k 档装不下：
% fs 会被压到 9.0 MSa/s，低于 1.5 MHz 需要的 15.1 MSa/s，rigol_dho814_capture_geometry
% 会直接报错并给出建议。要让 6.6 ms 成立，把 npts_max 抬到 1e6：
%   cfg = pcd_param_limits();  % 只为看数字
% 实际改的是下面这个常量。抬到 1e6 后：深度 1M、fs 40 MSa/s、记录 25 ms、
% 每帧 3.9 MB、acq_n ≈ 266k —— 帧率会掉到约 1 帧/s。
% 注意：6.6 ms 与「每周期收一次」不可兼得。PRF=5 Hz 时周期只有 200 ms，
% 而 3.9 MB 的传输本身就接近这个量级，采样只能隔几个周期做一次。
% 若不需要 6.6 ms 那么长的猝发，减小 n_cycle 是最省的办法。
%
% 周期数硬上限 10000：与网页 input / JS 截断同一套数字。不要再按「假 40 MSa/s 窗」
% 把 n_cycle 静默压到 ~3000——框里写 9990、发生器却跑 3000，截图会骗人。
% 旧注释写的「100k 点 @ 12.5 MSa/s ≈ 8 ms 窗」是错的：100k 档配 8 ms 记录时
% fs 只有 12.5 MSa/s，而记录长度本来就不该由 npts 决定。窗能不能装下这一发，
% 现在由 rigol_dho814_capture_geometry 判定并在装不下时报错，不再静默截断。
L = struct( ...
    'npts_min', 4096, 'npts_max', 100000, 'npts_default', 40000, ...
    'n_cycle_min', 1, 'n_cycle_max', 10000, 'n_cycle_default', 400);
end
