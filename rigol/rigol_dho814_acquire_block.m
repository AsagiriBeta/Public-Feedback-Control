function [chA, timeIntervalNanoSeconds, realFs] = rigol_dho814_acquire_block(dev, npts, ch)
%RIGOL_DHO814_ACQUIRE_BLOCK 单次触发后读取 RAW 波形（WORD），返回电压行向量。
% 流程参考 DHO800 编程手册 3.28 节 :WAVeform:DATA?
cfg = rigol_instr_config();
if nargin < 3 || isempty(ch)
    ch = cfg.scope_channel;
end
chan = sprintf('CHANnel%d', ch);

writeline(dev, ':RUN');
writeline(dev, ':SINGle');
t0 = tic;
ok = false;
while toc(t0) < cfg.acquire_timeout_s
    st = rigol_visa_query(dev, ':TRIGger:STATus?');
    if contains(st, 'STOP', 'IgnoreCase', true)
        ok = true;
        break;
    end
    pause(0.005);
end
if ~ok
    error('rigol:dho814:timeout', 'DHO814 单次触发超时（%.1f s）', cfg.acquire_timeout_s);
end

writeline(dev, ':STOP');

writeline(dev, sprintf(':WAVeform:SOURce %s', chan));
writeline(dev, ':WAVeform:MODE RAW');
writeline(dev, ':WAVeform:FORMat WORD');
writeline(dev, sprintf(':WAVeform:POINts %d', npts));
writeline(dev, ':WAVeform:STARt 1');
writeline(dev, sprintf(':WAVeform:STOP %d', npts));

yinc = str2double(rigol_visa_query(dev, ':WAVeform:YINCrement?'));
yor = str2double(rigol_visa_query(dev, ':WAVeform:YORigin?'));
yref = str2double(rigol_visa_query(dev, ':WAVeform:YREFerence?'));
xinc = str2double(rigol_visa_query(dev, ':WAVeform:XINCrement?'));

writeline(dev, ':WAVeform:DATA?');
payload = rigol_read_ieee_block_binary(dev);

if mod(numel(payload), 2) ~= 0
    error('rigol:dho814:waveform', 'WORD 波形字节数为奇数');
end
iv = typecast(uint8(payload), 'int16');
nv = numel(iv);
chA = (double(iv(:)).' - yor - yref) .* yinc;

if numel(chA) > npts
    chA = chA(1:npts);
elseif numel(chA) < npts
    tmp = zeros(1, npts);
    tmp(1:numel(chA)) = chA;
    chA = tmp;
end

realFs = 1 / xinc;
timeIntervalNanoSeconds = xinc * 1e9;

writeline(dev, ':RUN');
end
