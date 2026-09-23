function p = pcd_fus_params(S)
%PCD_FUS_PARAMS 由「原始参数结构体」校验并推导 FUS 参数（唯一的参数规则出处）。
%
% 网页界面（web/index.html）与 GUIDE 界面都走这里，保证两边行为一致。
% 输入 S 字段（缺省则用默认值）：
%   freq_mhz volt_mVpp amp_gain prf_hz n_cycle cav_pct duration_s npts target_db max_mVpp base_mVpp vstep_mVpp ctrl_metric mb_load_s studyID
%
% 空化率 cav_pct (%) 与周期数 n_cycle 互算见 pcd_duty：
%   duty = n_cycle * PRF / f0_Hz ，cav_pct = 100 * duty
%   n_cycle = (cav_pct/100) * f0_Hz / PRF
% 功放增益 amp_gain：V_load ≈ volt_mVpp/1000 * amp_gain（功放在发生器后时的负载峰峰值）。
% CH1 若接在功放前，回读仍是发生器 mVpp，不能当作声压。
%
% 频率/电压/PRF/时长是必填项：缺失或非法一律报错，而不是静默兜底
% （清空电压框若静默变成 1 mVpp 就会直接开超声，很危险）。
% duration_s 是墙钟总治疗时长（含 PRF 空档），从发生器开射频起算，不是 USB 帧数。
if nargin < 1 || ~isstruct(S)
    S = struct();
end

p.freq_mhz   = req(S, 'freq_mhz');
p.volt_mVpp  = req(S, 'volt_mVpp');
p.prf_hz     = req(S, 'prf_hz');
p.duration_s = req(S, 'duration_s');

% 上下限见 pcd_param_limits；网页 input / JS 截断必须抄同一套数字。
L = pcd_param_limits();
p.npts    = max(L.npts_min, round(opt(S, 'npts', L.npts_default)));
p.npts    = min(p.npts, L.npts_max);
% 目标 dB 是用户每次填的数；缺省才是 2，绝不把 4 改回 2。
p.target_db = opt(S, 'target_db', 2);
p.max_mVpp  = opt(S, 'max_mVpp', 120);
p.base_mVpp = opt(S, 'base_mVpp', 100);
p.vstep_mVpp = opt(S, 'vstep_mVpp', 5);
% 默认窗求和 = Fig.6 蓝线（3 MHz ±20 kHz）。峰/底可在界面改回去。
p.ctrl_metric = pcd_ctrl_metric(S);
[~, p.sc_harm] = pcd_sc_harm(S);
p.mb_load_s = opt(S, 'mb_load_s', 15);
p.amp_gain  = opt(S, 'amp_gain', 40);
p.fs_target = 40e6;
p.studyID   = optstr(S, 'studyID', 'run');

if ~(isfinite(p.freq_mhz) && p.freq_mhz > 0)
    error('pcd:params', '请填写有效的 FUS 频率 (MHz)。');
end
if ~(isfinite(p.volt_mVpp) && p.volt_mVpp > 0)
    error('pcd:params', '请填写有效的 FUS 电压 (mVpp)。');
end
% DG2052 在 50 Ω 负载下常见 1 mVpp–10 Vpp；20 mV 与 500 mV 都合法，不要额外截断。
if p.volt_mVpp > 10000
    error('pcd:params', '电压 %.4g mVpp 超过 10 Vpp，请确认单位是 mVpp。', p.volt_mVpp);
end
if ~(isfinite(p.prf_hz) && p.prf_hz > 0)
    error('pcd:params', '请填写有效的 PRF (Hz)。');
end
if ~(isfinite(p.duration_s) && p.duration_s > 0)
    error('pcd:params', '请填写有效的治疗时长 (s)。');
end
if ~(isfinite(p.max_mVpp) && p.max_mVpp > 0)
    p.max_mVpp = 120;
end
% 假超声 / dummy 电压：文献锁 18 mVpp（他们探头 ≈0.2 MPa）。本实验室探头不同，
% 界面可调，默认 100 mVpp。仍须低于闭环上限；非法则退回 100。
if ~(isfinite(p.base_mVpp) && p.base_mVpp > 0)
    p.base_mVpp = 100;
end
p.base_mVpp = min(p.base_mVpp, p.max_mVpp);
if ~(isfinite(p.vstep_mVpp) && p.vstep_mVpp > 0)
    p.vstep_mVpp = 5;
end
p.vstep_mVpp = min(p.vstep_mVpp, p.max_mVpp);
if ~(isfinite(p.mb_load_s) && p.mb_load_s >= 0)
    p.mb_load_s = 0;
end
% 功放增益默认 40 倍。非法值不要静默成 1（1 等于「没开功放」，会把后面实验标成无功放）。
if ~(isfinite(p.amp_gain) && p.amp_gain > 0)
    p.amp_gain = 40;
end

% 周期数：界面填了 n_cycle 就用它（DG2052 BurstCount）；只填了空化率则反算。
% 只按 pcd_param_limits 截到 1–10000，不再按假 40 MSa/s 窗静默压到 ~3000。
% 100k 点 @ 12.5 MSa/s ≈ 8 ms，1.5 MHz × 9990 周期 = 6.66 ms，盖得住。
nc = opt(S, 'n_cycle', NaN);
if ~isfinite(nc)
    nc = pcd_duty('n_cycle', opt(S, 'cav_pct', NaN), p.freq_mhz, p.prf_hz);
end
if ~isfinite(nc)
    nc = L.n_cycle_default;
end
p.n_cycle = max(L.n_cycle_min, min(round(nc), L.n_cycle_max));
% 存盘 / 回写界面用截断后的真实周期数反算空化率，框里不能还留着用户键入的越限值。
p.cav_pct = pcd_duty('cav_pct', p.n_cycle, p.freq_mhz, p.prf_hz);
% V_load ≈ volt_mVpp/1000 * amp_gain ：功放在发生器后时的负载峰峰值（Vpp）。
% CH1 若接在功放前，回读仍是发生器 mVpp，不能当作声压。
p.v_load_Vpp = (p.volt_mVpp / 1000) * p.amp_gain;
p.period_s = 1 / p.prf_hz;
% n_expect = 墙钟 duration_s 内发生器按 PRF 会打的猝发数。采集停靠墙钟，
% 不靠采满这个数（USB ~1 帧/s，远少于 PRF）。
p.n_expect = max(1, round(p.duration_s * p.prf_hz));
end

function v = req(S, k)
v = NaN;
if isfield(S, k)
    v = as_num(S.(k));
end
end

function v = opt(S, k, def)
v = def;
if isfield(S, k)
    x = as_num(S.(k));
    if isfinite(x)
        v = x;
    end
end
end

function v = as_num(x)
% uihtml / JSON 有时把数字框送来成字符串或 1×1 cell，不能因此退回缺省 2 dB。
v = NaN;
if iscell(x) && isscalar(x)
    x = x{1};
end
if isnumeric(x) && isscalar(x) && isfinite(x)
    v = double(x);
elseif ischar(x) || isstring(x)
    n = str2double(strtrim(char(x)));
    if isfinite(n)
        v = n;
    end
end
end

function s = optstr(S, k, def)
s = def;
if isfield(S, k)
    x = S.(k);
    if ischar(x) || isstring(x)
        x = strtrim(char(x));
        if ~isempty(x)
            s = x;
        end
    end
end
end
