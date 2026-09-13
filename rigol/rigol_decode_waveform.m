function raw = rigol_decode_waveform(payload, fmt)
%RIGOL_DECODE_WAVEFORM 把 SCPI 二进制块解成有符号采样码（纯函数，便于自检）。
%
%   raw = rigol_decode_waveform(payload, 'WORD')
%   raw = rigol_decode_waveform(payload, 'BYTE')
%
% WORD：每样点 2 字节、小端、有符号 int16 —— 对应 :WAVeform:BYTeorder LSBFirst
% BYTE：每样点 1 字节、无符号 0–255
%
% 手写字节拼装而不是 typecast，是为了不依赖 MATLAB 宿主机的字节序 ——
% 用 typecast 在大端机器上会把字节目序搞反，波形整体失真（很难查）。
b = uint8(payload(:));
if strcmpi(fmt, 'WORD')
    if mod(numel(b), 2) ~= 0
        b = b(1:end-1);            % 半个样本解不出来，直接丢掉
    end
    raw = double(b(1:2:end-1)) + 256 * double(b(2:2:end));
    neg = raw >= 32768;
    raw(neg) = raw(neg) - 65536;
    raw = raw(:).';
else
    raw = double(b(:)).';
end
end
