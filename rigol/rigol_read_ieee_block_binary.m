function payload = rigol_read_ieee_block_binary(dev)
%RIGOL_READ_IEEE_BLOCK_BINARY 读取 SCPI 二进制块响应（#N<len><payload>）。
b0 = read(dev, 1, 'uint8');
if char(b0) ~= '#'
    error('rigol:ieeeBlock', '期望 IEEE 块头 #，收到: %s', char(b0));
end
nd = str2double(char(read(dev, 1, 'uint8')));
lenStr = char(read(dev, nd, 'uint8').');
nbytes = str2double(lenStr);
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
