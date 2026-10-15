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
% 通道关着时 :WAVeform:SOURce 会回 -200，屏幕每一帧闪「远程指令执行错误」。
writeline(dev, sprintf(':CHANnel%d:DISPlay ON', ch));
writeline(dev, sprintf(':WAVeform:SOURce %s', chan));
writeline(dev, sprintf(':WAVeform:MODE %s', wavemode));
writeline(dev, sprintf(':WAVeform:FORMat %s', FMT));
if strcmpi(wavemode, 'RAW')
    % 不要从内存第 1 点读。XORigin 为负时，开头是触发前的空档，
    % 6.7 ms 脉冲会从窗中间才开始，后半段被切掉。从触发点往后再取 npts。
    [i0, nread] = raw_from_trigger(dev, npts);
    % 先拉高 STOP 再移动 START，避免 START 大于当前 STOP 时示波器报执行错误。
    writeline(dev, sprintf(':WAVeform:STOP %d', i0 + nread - 1));
    writeline(dev, sprintf(':WAVeform:STARt %d', i0));
    writeline(dev, sprintf(':WAVeform:POINts %d', nread));
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

function [i0, nread] = raw_from_trigger(dev, npts)
% 触发点在内存中的位置。预留 50 µs，避免上升沿被切掉。
i0 = 1;
nread = npts;
nmem = mdepth_points(dev);
% 先回到内存第 1 点再问 XORigin。有的固件会把 XORigin 改成当前 START 的时间，
% 不复位的话下一帧会把触发点算错，又读回触发前的空档。
try, writeline(dev, ':WAVeform:STARt 1'); catch, end
xorigin = str2double(rigol_visa_query(dev, ':WAVeform:XORigin?'));
xinc = str2double(rigol_visa_query(dev, ':WAVeform:XINCrement?'));
if ~(isfinite(nmem) && nmem >= 256 && isfinite(xorigin) && isfinite(xinc) && xinc > 0)
    return
end
i_trig = round((-xorigin) / xinc) + 1;
i0 = i_trig - round(50e-6 / xinc);
i0 = max(1, min(nmem, i0));
nread = min(npts, nmem - i0 + 1);
if nread < 256
    i0 = 1;
    nread = min(npts, nmem);
end
end

function n = mdepth_points(dev)
n = NaN;
try
    s = upper(strtrim(rigol_visa_query(dev, ':ACQuire:MDEPth?')));
catch
    return
end
s = regexprep(s, '\s', '');
if endsWith(s, 'M')
    n = str2double(extractBefore(s, strlength(s))) * 1e6;
elseif endsWith(s, 'K')
    n = str2double(extractBefore(s, strlength(s))) * 1e3;
else
    n = str2double(s);
end
end
