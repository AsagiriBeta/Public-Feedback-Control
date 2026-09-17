function rigol_dg2052_load(dev, ch)
%RIGOL_DG2052_LOAD 输出负载设为 50 Ω（面板 Impedance = 50Ω，低阻）。
% 必须在写 VOLTage 之前调用：同样的 Vpp 数字在高阻和 50 Ω 下实际幅度差一倍。
if nargin < 2 || isempty(ch)
    cfg = rigol_instr_config();
    ch = cfg.awg_channel;
end
out = sprintf('OUTPut%d', ch);
writeline(dev, sprintf(':%s:LOAD 50', out));
rd = strtrim(char(writeread(dev, sprintf(':%s:LOAD?', out))));
n = str2double(rd);
if ~(isfinite(n) && abs(n - 50) < 1)
    error('rigol:dg2052:load', '未能把 DG2052 输出负载设为 50 Ω（回读 %s）。', rd);
end
end
