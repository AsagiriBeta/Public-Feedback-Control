function out = pcd_duty(cmd, val, freq_mhz, prf_hz)
%PCD_DUTY 空化率 cav_pct (%) 与周期数 n_cycle 互算（MATLAB / 网页同一套公式）。
%
% 物理定义（不要另发明）：
%   猝发时长  T_on = n_cycle / f0_Hz
%   脉冲间隔  PRI  = 1 / PRF
%   空化率    duty = T_on / PRI = n_cycle * PRF / f0_Hz
% 界面显示百分数 cav_pct = 100 * duty，因此：
%   n_cycle = (cav_pct/100) * f0_Hz / PRF
%   cav_pct = 100 * n_cycle * PRF / f0_Hz
% 例：1.5 MHz、PRF 5 Hz、n_cycle 3000 → 空化率 1%。
% 默认 n_cycle 400、PRF 2 Hz、1.5 MHz → 约 0.0533%（PRF 5 Hz 时约 0.133%）。
%
%   n = pcd_duty('n_cycle', cav_pct, freq_mhz, prf_hz)  % 四舍五入为整数，再截到 1–10000
%   p = pcd_duty('cav_pct', n_cycle, freq_mhz, prf_hz)
%
% freq_mhz 单位 MHz，prf_hz 单位 Hz。非法输入返回 NaN。
% 网页 web/app.js 必须抄同一套公式，两边不能各算各的。

out = NaN;
if nargin < 4
    return;
end
cmd = lower(strtrim(char(string(cmd))));
val = to_num(val);
freq_mhz = to_num(freq_mhz);
prf_hz = to_num(prf_hz);
if ~isfinite(val) || ~isfinite(freq_mhz) || ~isfinite(prf_hz) || freq_mhz <= 0 || prf_hz <= 0
    return;
end
f0_Hz = freq_mhz * 1e6;

switch cmd
    case 'n_cycle'
        % n_cycle = (cav_pct/100) * f0_Hz / PRF
        L = pcd_param_limits();
        nc = round((val / 100) * f0_Hz / prf_hz);
        out = max(L.n_cycle_min, min(nc, L.n_cycle_max));
    case 'cav_pct'
        % cav_pct = 100 * n_cycle * PRF / f0_Hz
        out = 100 * val * prf_hz / f0_Hz;
    otherwise
        error('pcd:duty:cmd', '未知命令 %s（用 n_cycle 或 cav_pct）', cmd);
end
end

function v = to_num(x)
v = NaN;
if isnumeric(x) && isscalar(x) && isfinite(x)
    v = double(x);
end
end
