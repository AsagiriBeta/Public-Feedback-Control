function payload = rigol_read_ieee_block_binary(dev)
%RIGOL_READ_IEEE_BLOCK_BINARY 读取 SCPI 二进制块响应（#N<len><payload>）。
b0 = read(dev, 1, 'uint8');
if char(b0) ~= '#'
    error('rigol:ieeeBlock', '期望 IEEE 块头 #，收到: %s', char(b0));
end
nd = str2double(char(read(dev, 1, 'uint8')));
lenStr = char(read(dev, nd, 'uint8').');
nbytes = str2double(lenStr);
% 上限与深度预算共用同一个数（pcd_param_limits.wf_max_bytes），
% 否则「几何选了 5M 档」和「这里只收 2 MB」会打架，表现为每帧波形读失败、帧被静默丢弃。
CAP = 2e6;
try
    L = pcd_param_limits();
    if isfield(L, 'wf_max_bytes') && isfinite(L.wf_max_bytes) && L.wf_max_bytes >= 16
        CAP = L.wf_max_bytes;
    end
catch
end
if ~(isfinite(nbytes) && nbytes >= 16 && nbytes <= CAP)
    error('rigol:ieeeBlock', ...
        ['IEEE 块长度异常: %s（上限 %.4g 字节）。' ...
         '若是深度档太大，请同时调整 pcd_param_limits.npts_max 与 wf_max_bytes。'], ...
        lenStr, CAP);
end
payload = read(dev, nbytes, 'uint8');
try
    flush(dev, "input");
catch
    try
        flush(dev);
    catch
    end
end
end
