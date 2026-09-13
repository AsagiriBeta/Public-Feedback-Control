function p = pfc_fus_params(S)
%PFC_FUS_PARAMS 由「原始参数结构体」校验并推导 FUS 参数（唯一的参数规则出处）。
%
% 网页界面（web/index.html）与 GUIDE 界面都走这里，保证两边行为一致。
% 输入 S 字段（缺省则用默认值）：
%   freq_mhz volt_mVpp prf_hz n_cycle duration_s npts target_db max_mVpp mb_load_s studyID
%
% 频率/电压/PRF/时长是必填项：缺失或非法一律报错，而不是静默兜底
% （清空电压框若静默变成 1 mVpp 就会直接开超声，很危险）。
if nargin < 1 || ~isstruct(S)
    S = struct();
end

p.freq_mhz   = req(S, 'freq_mhz');
p.volt_mVpp  = req(S, 'volt_mVpp');
p.prf_hz     = req(S, 'prf_hz');
p.duration_s = req(S, 'duration_s');

p.n_cycle = max(1, round(opt(S, 'n_cycle', 400)));
p.n_cycle = min(p.n_cycle, 5000);
p.npts    = max(4096, round(opt(S, 'npts', 40000)));
p.npts    = min(p.npts, 50000);
p.target_db = opt(S, 'target_db', 2);
p.max_mVpp  = opt(S, 'max_mVpp', 120);
p.mb_load_s = opt(S, 'mb_load_s', 15);
p.fs_target = 40e6;
p.studyID   = optstr(S, 'studyID', 'run');

if ~(isfinite(p.freq_mhz) && p.freq_mhz > 0)
    error('pfc:params', '请填写有效的 FUS 频率 (MHz)。');
end
if ~(isfinite(p.volt_mVpp) && p.volt_mVpp > 0)
    error('pfc:params', '请填写有效的 FUS 电压 (mVpp)。');
end
% DG2052 高阻常见 1 mVpp–10 Vpp；20 mV 与 500 mV 都合法，不要额外截断。
if p.volt_mVpp > 10000
    error('pfc:params', '电压 %.4g mVpp 超过 10 Vpp，请确认单位是 mVpp。', p.volt_mVpp);
end
if ~(isfinite(p.prf_hz) && p.prf_hz > 0)
    error('pfc:params', '请填写有效的 PRF (Hz)。');
end
if ~(isfinite(p.duration_s) && p.duration_s > 0)
    error('pfc:params', '请填写有效的治疗时长 (s)。');
end
if ~(isfinite(p.max_mVpp) && p.max_mVpp > 0)
    p.max_mVpp = 120;
end
if ~(isfinite(p.mb_load_s) && p.mb_load_s >= 0)
    p.mb_load_s = 0;
end

% 50k 点、约 31–40 MSa/s 只能盖住约 1.2–1.6 ms，周期数不能按 5000 硬打满。
max_cyc = max(80, floor((p.npts / p.fs_target) * p.freq_mhz * 1e6 / 1.25));
p.n_cycle = min(p.n_cycle, max_cyc);
p.period_s = 1 / p.prf_hz;
p.n_expect = max(1, round(p.duration_s * p.prf_hz));
end

function v = req(S, k)
v = NaN;
if isfield(S, k)
    x = S.(k);
    if isnumeric(x) && isscalar(x) && isfinite(x)
        v = double(x);
    end
end
end

function v = opt(S, k, def)
v = def;
if isfield(S, k)
    x = S.(k);
    if isnumeric(x) && isscalar(x) && isfinite(x)
        v = double(x);
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
