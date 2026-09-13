function [y, xinc] = rigol_dho814_read_channel(dev, ch, npts, wavemode)
%RIGOL_DHO814_READ_CHANNEL STOP 后读取通道。
%
% 用 WORD（16 位）而不是 BYTE（8 位）：DHO814 是 12 位 ADC，BYTE 读回来只剩 8 位，
% 白扔 24 dB 动态范围。实测某轮数据里 IC 频带（3.3 MHz 一带）的信号只有 20–95 µV，
% 而 BYTE 的量化噪声 RMS 就有约 72 µV —— 那时测到的全是量化本底，不是空化宽带。
%
% 不把短波形补零（避免假 FFT 峰）。
%
% 注意 DHO800 的 :WAVeform:* 一共 14 条命令，**没有** :WAVeform:BYTeorder
% （手册 3.28 各节），所以字节序不能靠发命令声明，只能按约定解析 —— 见下面的
% YREFerence 判断。
if nargin < 4 || isempty(wavemode)
    wavemode = 'RAW';
end
FMT = 'WORD';                          % 想退回 8 位就改这里（decode 两条分支都在）

chan = sprintf('CHANnel%d', ch);
writeline(dev, sprintf(':WAVeform:SOURce %s', chan));
writeline(dev, sprintf(':WAVeform:MODE %s', wavemode));
writeline(dev, sprintf(':WAVeform:FORMat %s', FMT));
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
if ~isfinite(yor), yor = 0; end
if ~isfinite(yref), yref = 0; end

writeline(dev, ':WAVeform:DATA?');
payload = rigol_read_ieee_block_binary(dev);
if isempty(payload)
    error('rigol:dho814:waveform', '未读到 CH%d 波形', ch);
end

% 按 YREFerence 判定二进制约定（详见 rigol_decode_waveform 的说明）
raw = rigol_decode_waveform(payload, FMT, yref);

y = (raw - yor - yref) .* yinc;
if isfinite(nact) && nact > 0 && numel(y) > nact
    y = y(1:nact);
end
if numel(y) > npts
    y = y(1:npts);
end
end
