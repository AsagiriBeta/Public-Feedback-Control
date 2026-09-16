function P = pfc_save_params(kind, src)
%PFC_SAVE_PARAMS 采集存盘用的参数快照（2/3/4/oneshot/debug 同一套字段）。
%
%   P = pfc_save_params(kind, src)
%
% kind  'nomb' | 'open_mb' | 'feedback' | 'oneshot' | 'debug'
% src   调用方手头的实际生效值。缺的键从 src.raw（界面原始字典）补，再缺则 NaN / ''。
%
% 本结构作为 .mat 的新增字段 params 写入，不改顶层旧名
% （freq_MHz、BurstCount、volt_mVpp 等）。旧加载脚本继续读顶层；
% 下一轮保存的 mat 用 params 即可还原当时的超声参数 / 调试频幅 / 仪器通道与负载。
% 存盘时另写一份 params.txt（在本次 run 目录里），方便不打开 MATLAB 就看。

if nargin < 2 || ~isstruct(src)
    src = struct();
end
kind = lower(char(string(kind)));
raw = struct();
if isfield(src, 'raw') && isstruct(src.raw)
    raw = src.raw;
end
cfg = rigol_instr_config();

P = struct();
P.kind = kind;
% debug 走 CW；2/3/4/oneshot 走猝发。允许调用方覆盖（src.drive）。
if strcmp(kind, 'debug')
    P.drive = pickstr(src, 'drive', 'cw');
else
    P.drive = pickstr(src, 'drive', 'burst');
end
P.started_at = pickstr(src, 'started_at', '');
P.saved_at = datestr(now, 'yyyy-mm-ddTHH:MM:SS');
P.studyID = pickstr(src, 'studyID', pickstr(raw, 'studyID', ''));

% —— 界面「超声参数」（2/3/4 共用）。oneshot/debug 不要用采集框覆盖这两项，
%     采集框走 dbg_*；真正下发到 AWG 的幅度走 volt_out_mVpp。
P.freq_mhz = pickn(src, 'freq_mhz', raw, 'freq_mhz');
P.volt_mVpp = pickn(src, 'volt_mVpp', raw, 'volt_mVpp');
P.volt_out_mVpp = pickn(src, 'volt_out_mVpp');
if ~isfinite(P.volt_out_mVpp)
    P.volt_out_mVpp = P.volt_mVpp;
end
P.max_mVpp = pickn(src, 'max_mVpp', raw, 'max_mVpp');
P.base_mVpp = pickn(src, 'base_mVpp', raw, 'base_mVpp');
P.vstep_mVpp = pickn(src, 'vstep_mVpp', raw, 'vstep_mVpp');
% 功放增益：V_load ≈ volt_mVpp/1000 * amp_gain（功放在发生器后时的负载 Vpp）。
% CH1 若接在功放前，回读仍是发生器 mVpp，不能当作声压。旧存档没有此项时默认 40。
P.amp_gain = pickn(src, 'amp_gain', raw, 'amp_gain');
if ~isfinite(P.amp_gain) || P.amp_gain <= 0
    P.amp_gain = 40;
end
P.v_load_Vpp = pickn(src, 'v_load_Vpp');
if ~isfinite(P.v_load_Vpp) && isfinite(P.volt_mVpp)
    P.v_load_Vpp = (P.volt_mVpp / 1000) * P.amp_gain;
end
P.prf_hz = pickn(src, 'prf_hz', raw, 'prf_hz');
P.n_cycle = pickn(src, 'n_cycle', raw, 'n_cycle');
% 空化率 cav_pct (%)：duty = n_cycle * PRF / f0_Hz，cav_pct = 100 * duty。
P.cav_pct = pickn(src, 'cav_pct', raw, 'cav_pct');
if ~isfinite(P.cav_pct) && isfinite(P.n_cycle) && isfinite(P.freq_mhz) && ...
        isfinite(P.prf_hz) && P.freq_mhz > 0 && P.prf_hz > 0
    P.cav_pct = pfc_duty('cav_pct', P.n_cycle, P.freq_mhz, P.prf_hz);
end
P.duration_s = pickn(src, 'duration_s', raw, 'duration_s');
P.npts = pickn(src, 'npts', raw, 'npts');
P.fs_target = pickn(src, 'fs_target');
if ~isfinite(P.fs_target)
    P.fs_target = 40e6;   % 与 pfc_fus_params 一致，界面没有这项
end
P.realFs = pickn(src, 'realFs');
P.period_s = pickn(src, 'period_s');
if ~isfinite(P.period_s) && isfinite(P.prf_hz) && P.prf_hz > 0
    P.period_s = 1 / P.prf_hz;
end
P.n_expect = pickn(src, 'n_expect');
if ~isfinite(P.n_expect) && isfinite(P.duration_s) && isfinite(P.prf_hz)
    P.n_expect = max(1, round(P.duration_s * P.prf_hz));
end
P.target_db = pickn(src, 'target_db', raw, 'target_db');
P.n_dummy = pickn(src, 'n_dummy');
P.sc0 = pickn(src, 'sc0');
P.ic0 = pickn(src, 'ic0');
P.ctrl_metric = pickstr(src, 'ctrl_metric', '');

% —— 调试页采集框（oneshot / 连续调试用它驱动 AWG；正式实验只作当时界面留档）
P.dbg_freq = pickn(src, 'dbg_freq', raw, 'dbg_freq');
P.dbg_volt = pickn(src, 'dbg_volt', raw, 'dbg_volt');

% —— 影响波形的仪器设置（通道、50 Ω 负载、WORD/RAW、量程格数）
P.awg_channel = pickn(src, 'awg_channel', cfg, 'awg_channel');
P.awg_load_ohm = pickn(src, 'awg_load_ohm');
if ~isfinite(P.awg_load_ohm)
    P.awg_load_ohm = 50;  % rigol_dg2052_load 固定 50 Ω，幅度按低阻解释
end
P.scope_tx_channel = pickn(src, 'scope_tx_channel', cfg, 'scope_tx_channel');
P.scope_pcd_channel = pickn(src, 'scope_pcd_channel', cfg, 'scope_pcd_channel');
P.waveform_format = pickstr(src, 'waveform_format', 'WORD');
P.waveform_mode = pickstr(src, 'waveform_mode', 'RAW');
P.pcd_scale_vdiv = pickn(src, 'pcd_scale_vdiv');
P.tx_scale_vdiv = pickn(src, 'tx_scale_vdiv');
P.scope_vdiv = pickn(src, 'scope_vdiv', cfg, 'scope_vdiv');
P.harmonic_bandwidth_hz = pickn(src, 'harmonic_bandwidth_hz', cfg, 'harmonic_bandwidth_hz');
P.trig_v = pickn(src, 'trig_v');
P.sweep = pickstr(src, 'sweep', '');
if isempty(P.sweep)
    if strcmp(kind, 'debug')
        P.sweep = 'AUTO';
    else
        P.sweep = 'SINGle';
    end
end
end

function v = pickn(varargin)
%PICKN 按 (struct, key) 对取第一个有限标量。
v = NaN;
for i = 1:2:nargin
    s = varargin{i};
    k = varargin{i+1};
    if ~isstruct(s) || isempty(k) || ~isfield(s, k)
        continue;
    end
    x = s.(k);
    if isnumeric(x) && isscalar(x) && isfinite(x)
        v = double(x);
        return;
    end
end
end

function s = pickstr(S, k, def)
s = def;
if ~isstruct(S) || ~isfield(S, k)
    return;
end
x = S.(k);
if ischar(x) || isstring(x)
    x = strtrim(char(x));
    if ~isempty(x)
        s = x;
    end
end
end
