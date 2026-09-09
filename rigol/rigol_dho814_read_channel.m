function [y, xinc] = rigol_dho814_read_channel(dev, ch, npts, wavemode)
%RIGOL_DHO814_READ_CHANNEL STOP 后读取通道。BYTE 更稳；不把短波形补零（避免假 FFT 峰）。
if nargin < 4 || isempty(wavemode)
    wavemode = 'RAW';
end
chan = sprintf('CHANnel%d', ch);
writeline(dev, sprintf(':WAVeform:SOURce %s', chan));
writeline(dev, sprintf(':WAVeform:MODE %s', wavemode));
writeline(dev, ':WAVeform:FORMat BYTE');
if strcmpi(wavemode, 'RAW')
    writeline(dev, sprintf(':WAVeform:POINts %d', npts));
    writeline(dev, ':WAVeform:STARt 1');
    writeline(dev, sprintf(':WAVeform:STOP %d', npts));
end

nact = str2double(rigol_visa_query(dev, ':WAVeform:POINts?'));
if ~(isfinite(nact) && nact >= 256)
    error('rigol:dho814:npts', 'CH%d 缓冲只有 %g 点，跳过本帧', ch, nact);
end
yinc = str2double(rigol_visa_query(dev, ':WAVeform:YINCrement?'));
yor = str2double(rigol_visa_query(dev, ':WAVeform:YORigin?'));
yref = str2double(rigol_visa_query(dev, ':WAVeform:YREFerence?'));
xinc = str2double(rigol_visa_query(dev, ':WAVeform:XINCrement?'));

if ~(isfinite(yinc) && yinc ~= 0)
    error('rigol:dho814:yinc', 'CH%d YINCrement 无效（%.4g）。通道可能未打开或未采到波形。', ch, yinc);
end
if ~(isfinite(xinc) && xinc > 0)
    error('rigol:dho814:xinc', 'CH%d XINCrement 无效', ch);
end

writeline(dev, ':WAVeform:DATA?');
payload = rigol_read_ieee_block_binary(dev);
if isempty(payload)
    error('rigol:dho814:waveform', '未读到 CH%d 波形', ch);
end

raw = double(payload(:)).';
y = (raw - yor - yref) .* yinc;
if isfinite(nact) && nact > 0 && numel(y) > nact
    y = y(1:nact);
end
if numel(y) > npts
    y = y(1:npts);
end
end
