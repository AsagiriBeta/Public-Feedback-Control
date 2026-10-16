function G = rigol_dho814_capture_geometry(burst_s, f0_hz, fs_target, npts, npts_max, lead_s)
%RIGOL_DHO814_CAPTURE_GEOMETRY 从「猝发长度 + 分析频带 + 传输预算」反推采集几何。
%
% 为什么不能继续用 npts/targetFs 直接定时基（改之前的做法）：
%   rigol_dho814_setup 原来写 scale = (npts/targetFs)/10，于是记录长度与这一发
%   多长完全无关。npts=40000、targetFs=40e6 时记录恒为 1 ms：
%     n_cycle=400  (猝发 0.27 ms) -> 窗里 3.7 倍是空档，signal_span 得在空档里找包络；
%     n_cycle=9990 (猝发 6.66 ms) -> 窗根本装不下，静默截断、丢占空比。
%   而且 realFs = 深度档/记录长度 = 100k/1ms = 100 MSa/s，比设计的 40 MSa/s
%   多采 2.5 倍，acq_n（真正要 FFT + 推给前端 + 做频谱的点数）也跟着翻倍。
%   实测：n_cycle=400 那一档 acq_n=26667，其中只有约 1/4 是有效猝发。
%
% 现在反过来推。三个量的关系是硬的：
%   传输量 = 深度档点数 × 2 通道 × 2 B   —— 只由深度档决定，与时基无关
%   realFs = 深度档 / 记录长度              —— 时基刻度 = 记录长度/10
%   acq_n  = burst_s × realFs              —— 实际参与分析的点数
% 所以真正的旋钮是 fs：fs 越大时间分辨率越好，但 acq_n 线性变大；
% 深度档只在跨档时把传输量跳一档。
%
% fs 的**下限**由分析频带决定，不是拍脑袋。pcd_cav_bands：
%   参考底带 3.40–3.87×f0、IC 宽带到 2.5×f0、SC = n×f0、IC 窄带 2.2×f0。
%   这些带都要落在 Nyquist 内并留 30% 余量 -> fs ≥ 2 × 3.87f0 × 1.3 = 10.06×f0。
%   f0=1.5 MHz -> 15.1 MSa/s；f0=3 MHz -> 30.2 MSa/s。
% 低于这个值不是「精度差一点」：pcd_band_energy 会把频带 clamp 到 Nyquist 并退化
% 成「最近那一个 bin」，指标彻底不可信且无任何告警 —— 所以这里直接判不合格。
%
% 输入
%   burst_s    这一发的长度 (s)。为空 / 非法时返回 ok=false，调用方应回退旧行为。
%   f0_hz      超声频率 (Hz)，用来定 fs 下限
%   fs_target  希望的采样率 (Sa/s)；预算不够时自动降到能装下的值，并在 G.note 说明
%   npts       深度档下界（沿用旧语义：深度档 ≥ npts）。空则取 0。
%   npts_max   传输预算：允许用的最大深度档点数（pcd_param_limits.npts_max）
%   lead_s     猝发之前预计有多长空档 (s)。这台机器 XORigin 会落在真正跳变前 1–3 ms
%              （见 rigol_dho814_setup 里的实测记录），记录必须留出这段，否则猝发
%              尾部被切掉。默认 3 ms 取实测上界；实测到更小的值就调小，fs 会回升。

if nargin < 5 || isempty(npts_max) || ~isfinite(npts_max) || npts_max < 1e3
    npts_max = 1e5;
end
if nargin < 4 || isempty(npts) || ~isfinite(npts) || npts < 0
    npts = 0;
end
if nargin < 6 || isempty(lead_s) || ~isfinite(lead_s) || lead_s < 0
    lead_s = 3e-3;
end
if nargin < 3 || isempty(fs_target) || ~isfinite(fs_target) || fs_target <= 0
    fs_target = 40e6;
end

% 标准深度档（:ACQuire:MDEPth）。开两路时 25M 会让 DHO814 报远程指令错误
% （rigol_dho814_setup 原来就降级到 10M），这里直接不给这个坑留机会。
DEPTH_PTS = [1e3, 1e4, 1e5, 1e6, 5e6, 1e7];
DEPTH_TAG = {'1k', '10k', '100k', '1M', '5M', '10M'};

G = struct();
G.burst_s = burst_s;
G.f0_hz = f0_hz;
G.fs_target = fs_target;
G.lead_s = lead_s;
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
    G.reason = 'f0_hz 非法（须为有限正数），无法定采集几何。';
    return;
end

% 记录至少要装下「前置空档 + 这一发」，再留 15% 余量给裁剪
rec_need = (lead_s + burst_s) * 1.15;

idx_cap = find(DEPTH_PTS <= npts_max, 1, 'last');
if isempty(idx_cap)
    G.reason = sprintf('传输预算 %.4g 点连最小深度档 1k 都容不下。', npts_max);
    return;
end
idx_npts = find(DEPTH_PTS >= npts, 1, 'first');
if isempty(idx_npts)
    % npts 比最高档还大：取最高档，让下面的预算判定去报错，不要静默忽略用户的请求。
    idx_npts = numel(DEPTH_PTS);
end

fs_want = max(fs_target, G.fs_min);          % 不允许低于频带下限
% 选深度档的目标是**最小化传输量**，不是「凑到 fs_target」：
% 传输量 = 深度档，而深度档一旦为了凑 fs_target 往上跳一档，每帧就多传一大截，
% 帧率直接掉下来（默认配置就会从 391 KB 跳到 3.9 MB）。所以：
%   深度档 = 能满足 fs ≥ fs_min 的最小档，且不小于 npts（沿用旧语义）；
%   fs_target 只当**上限**用 —— 深度档取定后，若还有余量就把记录拉长把 fs 压回目标，
%   这样 acq_n 不会因为深度档向上取整而白白变大。
idx_floor = first_ge(DEPTH_PTS, rec_need * G.fs_min);
if isempty(idx_floor)
    idx_floor = numel(DEPTH_PTS);
end

idx = max([idx_npts, idx_floor]);
if idx > idx_cap
    % 连频带下限都满足不了：报清楚差在哪。前置空档本身可能就已经超预算，
    % 这时「缩短猝发」这条建议没有意义，硬报一个负的「猝发上限」只会更困惑。
    idx = idx_cap;
    fs_eff = DEPTH_PTS(idx) / rec_need;
    lead_pts = lead_s * G.fs_min * 1.15;
    if lead_pts >= npts_max
        tail = sprintf(['光前置空档就要 %.4g 点（预算只有 %.4g 点），' ...
            '所以这不是猝发长度的问题。'], lead_pts, npts_max);
    else
        tail = sprintf('前置空档占 %.4g 点；把猝发缩短到 %.2f ms 以内可以装下。', ...
            lead_pts, (npts_max / (G.fs_min * 1.15) - lead_s) * 1e3);
    end
    G.reason = sprintf(['这一发 %.4g ms 加上前置空档 %.1f ms 装不进 %.4g 点的传输预算。' ...
        '要让 %.4g MHz 的参考底带（3.87×f0）落在 Nyquist 内，fs 至少要 %.4g MSa/s，' ...
        '而预算内最多只能到 %.4g MSa/s。%s 三个办法：' ...
        '(1) 把 npts 上限（pcd_param_limits.npts_max）抬到 %s 档，传输涨到 %.1f MB/帧；' ...
        '(2) 核对前置空档的真实值（rigol_instr_config.scope_lead_s），确认后调小，fs 会立刻回升；' ...
        '(3) 换更低的 f0。'], ...
        burst_s * 1e3, lead_s * 1e3, npts_max, 3.87 * f0_hz / 1e6, ...
        G.fs_min / 1e6, fs_eff / 1e6, tail, ...
        tag_at(DEPTH_TAG, idx_cap + 1), bytes_at(DEPTH_PTS, idx_cap + 1) / 1048576);
    return;
end

% 记录长度：至少装下 rec_need；深度档有余量就拉长记录把 fs 压回 fs_target，
% 免得深度档向上取整把 acq_n 白白放大（acq_n = burst_s × fs）。
record_s = max(rec_need, DEPTH_PTS(idx) / fs_want);
fs_eff = DEPTH_PTS(idx) / record_s;
if fs_eff < G.fs_min * (1 - 1e-9)
    G.reason = sprintf('内部不自洽：深度档 %s 在记录 %.4g ms 上只给出 %.4g MSa/s，低于下限 %.4g MSa/s。', ...
        DEPTH_TAG{idx}, record_s * 1e3, fs_eff / 1e6, G.fs_min / 1e6);
    return;
end
if fs_eff < fs_want * (1 - 1e-9)
    G.note = sprintf(['预算装不下 %.4g MSa/s，实际 %.4g MSa/s（记录取刚好的 %.4g ms）。' ...
        '时间分辨率下降，但所有频带仍在 Nyquist 内（余量 %.2f×）。'], ...
        fs_want / 1e6, fs_eff / 1e6, record_s * 1e3, (fs_eff / 2) / (3.87 * f0_hz));
elseif fs_want > fs_target * (1 + 1e-9)
    G.note = sprintf('fs 目标 %.4g MSa/s 低于频带下限，已抬到 %.4g MSa/s。', ...
        fs_target / 1e6, fs_want / 1e6);
end

G.ok = true;
G.depth_pts = DEPTH_PTS(idx);
G.depth_tag = DEPTH_TAG{idx};
G.fs = fs_eff;
G.record_s = record_s;
G.scale_s_per_div = G.record_s / 10;
% acq_n 是「这一发本身」的点数，固定由 burst_s × fs 决定，不再由某一帧的裁剪结果决定。
% 这样每帧长度一致，频谱幅值不会随帧抖动（改之前 acq_n 取自 prime 帧）。
G.acq_n = max(256, round(burst_s * fs_eff));
G.lead_covered_s = G.record_s - burst_s;
G.nyquist_hz = fs_eff / 2;
G.band_max_hz = 3.87 * f0_hz;
G.transfer_bytes = G.depth_pts * 2 * 2;   % 2 通道 × WORD(2 B)
end

function idx = first_ge(v, x)
idx = find(v >= x, 1, 'first');
end

function s = tag_at(tags, idx)
if idx >= 1 && idx <= numel(tags)
    s = tags{idx};
else
    s = '（已到最高档）';
end
end

function b = bytes_at(pts, idx)
if idx >= 1 && idx <= numel(pts)
    b = pts(idx) * 2 * 2;
else
    b = NaN;
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
