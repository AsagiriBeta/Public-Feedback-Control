function s = rigol_visa_norm(addr)
%RIGOL_VISA_NORM 归一化 VISA 资源名，便于比较是否为同一台仪器。
% USB 地址常见两种写法：...::SERIAL::0::INSTR 与 ...::SERIAL::INSTR，连的是同一资源。
s = strtrim(char(string(addr)));
if isempty(s)
    return;
end
s = regexprep(s, '::0::INSTR$', '::INSTR', 'ignorecase');
end
