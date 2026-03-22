function dev = rigol_dho814_open(visaAddr)
%RIGOL_DHO814_OPEN 打开 DHO814（DHO800 系列）USBTMC 连接。
if nargin < 1 || isempty(visaAddr)
    visaAddr = rigol_instr_config().scope_visa;
end
if ~exist('visadev', 'file')
    error('rigol:visadev', '需要 MATLAB Instrument Control Toolbox 提供的 visadev（建议 R2020b+）。');
end
dev = visadev(visaAddr);
dev.Timeout = 15;
end
