function txt = rigol_visa_query(dev, cmd)
%RIGOL_VISA_QUERY 发送 SCPI 查询并读取一行响应。
writeline(dev, cmd);
txt = strtrim(readline(dev));
end
