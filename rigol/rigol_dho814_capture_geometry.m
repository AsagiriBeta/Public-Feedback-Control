function G = rigol_dho814_capture_geometry(burst_s, f0_hz, fs_target, npts, npts_max, T, margin)
%RIGOL_DHO814_CAPTURE_GEOMETRY 由实测档位表挑出「深度档 + 时基」，定死这一发的采集几何。
%
% 这个函数是纯计算，不碰仪器：档位表由 rigol_dho814_probe_timing 实测得到并传进来。
% 这样做是因为公式推不出来 —— DHO814（固件 00.01.04）的真实行为有三条与直觉不符：
%   1) :ACQuire:SRATe? 是离散档位（采样间隔 3.2ns × {1,2,5,10,25,50,125,250}），
%      把时基设 375µs/div、深度 100k，它给 12.5 MSa/s，而不是 MDEPth/记录 = 26.67；
%   2) 内存记录长度 ≥ 屏幕窗（实测 1.28–3.2 倍），不是 10 格；
%   3) :WAVeform:XORigin 恒等于 -记录长度/2 —— **触发点固定在记录正中央**，
%      :TIMebase:HREFerence:MODE LB 对内存记录无效（只影响屏幕）。
% 第 3 条决定判据：能装这一发的只有触发之后那一半，
%   可用触后窗口 = 记录/2 = MDEPth/(2·SRATe)
% 所以「记录 ≥ 前置空档 + 猝发」是错的，正确判据是 post_s ≥ burst_s × margin。
%
% 输入
%   burst_s   这一发的长度 (s)
%   f0_hz     超声频率 (Hz)：用来定采样率下限（不改，见下）
%   fs_target 希望的采样率 (Sa/s)：只在同等深度下用来挑「最接近」的实测档位
%   npts      深度档下界（沿用旧语义；<=0 表示不设下限）
%   npts_max  传输预算：允许用的最大深度档点数（pcd_param_limits.npts_max）
%   T         rigol_dho814_probe_timing 的实测输出
%   margin    触后窗口相对猝发的余量（默认 1.15）
%
% 采样率下限为什么是 10.06×f0：pcd_cav_bands 的参考底带最高到 3.87×f0，
% IC 宽带到 2.5×f0，这些带都要落在 Nyquist 内并留 30% 余量。
% 低于它就 pcd_band_energy 会把频带 clamp 到 Nyquist 并退化成单 bin，且不报错。
%
% 选档策略：先取「能满足 fs 下限 + 触后窗口」的**最小深度档**（传输量 = 深度档，
% 这是帧率的唯一瓶颈），再在该深度档内取 fs 最接近 fs_target 的实测档位。
%
% 输出 G.ok=false 时 G.reason 给出实测到的可行边界，便于照着调参。

if nargin < 7 || isempty(margin) || ~isfinite(margin) || margin <= 1
    margin = 1.15;
end
if nargin < 6 || isempty(T)
    T = struct('depth_tag', {}, 'depth_pts', {}, 'div_s', {}, 'fs', {}, 'record_s', {}, 'post_s', {});
end
if nargin < 5 || isempty(npts_max) || ~isfinite(npts_max) || npts_max < 1e3
    npts_max = 1e5;
end
if nargin < 4 || isempty(npts) || ~isfinite(npts) || npts < 0
    npts = 0;
end
if nargin < 3 || isempty(fs_target) || ~isfinite(fs_target) || fs_target <= 0
    fs_target = 40e6;
end

G = struct();
G.burst_s = burst_s;
G.f0_hz = f0_hz;
G.fs_target = fs_target;
G.margin = margin;
G.npts = npts;
G.npts_max = npts_max;
G.fs_min = fs_bands_min(f0_hz);
G.ok = false;
G.reason = '';
G.note = '';

if ~(isscalar(burst_s) && isfinite(burst_s) && burst_s > 0)
    G.reason = 'burst_s 非法（须为有限正数）；这一发有多长都不知道就没法定采集几何。';
    return;
end
if ~(isscalar(f0_hz) && isfinite(f0_hz) && f0_hz > 0)
    G.reason = 'f0_hz 非法（须为有限正数），无法定采样率下限。';
    return;
end
if isempty(T)
    G.reason = ['没有实测档位表。DHO814 的采样率/记录长度不能按公式算，' ...
        '必须先跑 rigol_dho814_probe_timing 探测。'];
    return;
end

need_post = burst_s * margin;
% 单通道一次波形块能读回多少点（WORD = 2 字节/点）。深度档超了它，每帧读都会失败、
% 帧被静默丢弃 —— 所以这里是硬上限，不是建议值。与 rigol_read_ieee_block_binary 同一个数。
cap_bytes = 2e6;
try
    L = pcd_param_limits();
    if isfield(L, 'wf_max_bytes') && isfinite(L.wf_max_bytes) && L.wf_max_bytes >= 16
        cap_bytes = L.wf_max_bytes;
    end
catch
end
max_pts_by_read = floor(cap_bytes / 2);
G.wf_max_bytes = cap_bytes;
G.max_depth_pts = max_pts_by_read;

% 条件筛：预算内 + 读得回来 + 采样率够 + 触后窗口装得下这一发
keep = false(1, numel(T));
for i = 1:numel(T)
    keep(i) = T(i).depth_pts <= npts_max ...
        && T(i).depth_pts <= max_pts_by_read ...
        && T(i).depth_pts >= npts ...
        && T(i).fs >= G.fs_min * (1 - 1e-9) ...
        && T(i).post_s >= need_post;
end
cand = T(keep);

if isempty(cand)
    G.reason = explain_failure(T, burst_s, need_post, G.fs_min, npts_max, margin, max_pts_by_read);
    if npts_max > max_pts_by_read
        G.reason = sprintf(['%s\n  另注意：传输预算 %.4g 点已经超过单通道一次能读回的上限 %d 点' ...
            '（wf_max_bytes = %.4g 字节）。抬 npts 上限时要把 wf_max_bytes 一起抬，' ...
            '否则深度档选上去了、波形却读不回来。'], G.reason, npts_max, max_pts_by_read, cap_bytes);
    end
    return;
end

% 先卡最小深度档（传输量只由它决定），再在该档内挑 fs 最接近 fs_target 的
dmin = min([cand.depth_pts]);
cand = cand([cand.depth_pts] == dmin);
[~, k] = min(abs(log([cand.fs]) - log(fs_target)));
pick = cand(k);

G.ok = true;
G.depth_tag = pick.depth_tag;
G.depth_pts = pick.depth_pts;
G.div_s = pick.div_s;
G.fs = pick.fs;
G.record_s = pick.record_s;
G.post_s = pick.post_s;
G.scale_s_per_div = pick.div_s;
% acq_n 用**实测**采样率算，不能用规划值：规划值只是请求，固件给的是档位值。
% 差 2.13 倍的话，按规划值裁出来的「一帧」会把猝发之外的 2 倍空档也包进去。
G.acq_n = max(256, round(burst_s * pick.fs));
G.nyquist_hz = pick.fs / 2;
G.band_max_hz = 3.87 * f0_hz;
G.nyquist_margin = G.nyquist_hz / G.band_max_hz;
G.transfer_bytes = pick.depth_pts * 2 * 2;   % 2 通道 × WORD(2 B)
G.post_slack_s = pick.post_s - burst_s;

if pick.fs < fs_target * (1 - 1e-9)
    G.note = sprintf(['实测档位里没有 %.4g MSa/s：在 %s 深度上取到最接近的 %.4g MSa/s。' ...
        '分析点数 %d（= 猝发 × 实测 fs）。'], ...
        fs_target / 1e6, pick.depth_tag, pick.fs / 1e6, G.acq_n);
end
if G.record_s > 4 * (burst_s + need_post)
    G.note = [G.note sprintf(' 记录 %.3f ms 相对这一发偏长，多余部分在触发前，不影响取窗。', ...
        G.record_s * 1e3)];
end
end

function s = explain_failure(T, burst_s, need_post, fs_min, npts_max, margin, max_pts_by_read)
%EXPLAIN_FAILURE 用实测数字说明卡在哪一关，并给出可执行的选项。
% 不要只说「装不下」——用户需要知道是深度不够、还是采样率不够、还是读不回来。
% 注意必须把「读回上限」也纳入筛选：否则会报出一档实际被滤掉的深度（例如 10M），
% 说它「最好」，然后建议用户去提高 npts_max —— 提了也没用，因为卡在块读那一侧。
if nargin < 7 || isempty(max_pts_by_read) || ~isfinite(max_pts_by_read)
    max_pts_by_read = inf;
end
in_budget = [T.depth_pts] <= npts_max;
readable  = [T.depth_pts] <= max_pts_by_read;
usable    = in_budget & readable;
dmax = max([T.depth_pts]);
if isempty(dmax), dmax = NaN; end

if ~any(usable)
    % 两端都被卡死：要分别说清是哪一侧
    if ~any(readable)
        s = sprintf(['实测最小深度档就超过单通道一次能读回的上限 %d 点' ...
            '（wf_max_bytes = %.4g 字节）。'], max_pts_by_read, max_pts_by_read * 2);
    elseif ~any(in_budget)
        s = sprintf(['最小深度档就超过传输预算 %.4g 点（实测最大档 %g 点）。' ...
            '请提高 pcd_param_limits.npts_max。'], npts_max, dmax);
    else
        s = sprintf('实测档位表里没有落在「预算 %.4g 点」且「可读回 %d 点」内的组合。', ...
            npts_max, max_pts_by_read);
    end
    return
end

best = T(usable);
[pmax, ip] = max([best.post_s]);
f_at = best(ip).fs;
s = sprintf(['预算内且读得回来的档里装不下这一发 %.4g ms（需触后窗口 ≥ %.4g ms）。' ...
    '实测最好的一档是 %s @ %.4g µs/div：触后窗口 %.4g ms、fs %.4g MSa/s' ...
    '（采样率下限 %.4g MSa/s）。'], ...
    burst_s * 1e3, need_post * 1e3, ...
    best(ip).depth_tag, best(ip).div_s * 1e6, pmax * 1e3, f_at / 1e6, fs_min / 1e6);
if pmax < need_post
    s = [s sprintf(['\n  → 这一关是窗口不够：需要更大的深度档（提高 pcd_param_limits.npts_max），' ...
        '或缩短 n_cycle。'])]; %#ok<AGROW>
else
    s = [s sprintf(['\n  → 这一关是采样率不够：窗口够但 fs 低于下限，' ...
        '需要更大的深度档才能在这档采样率上再压一档。'])]; %#ok<AGROW>
end
end

function fs = fs_bands_min(f0_hz)
%FS_BANDS_MIN 让 pcd_cav_bands 的所有频带都落在 Nyquist 内、并留 30% 余量。
if ~(isscalar(f0_hz) && isfinite(f0_hz) && f0_hz > 0)
    fs = 15.1e6;
    return;
end
fs = 2 * 3.87 * f0_hz * 1.3;
end
