function raw = rigol_decode_waveform(payload, fmt, yref)
%RIGOL_DECODE_WAVEFORM 把 SCPI 二进制块解成「可直接代入 (raw-yor-yref)*yinc 的采样码」。
%
%   raw = rigol_decode_waveform(payload, 'WORD', yref)
%   raw = rigol_decode_waveform(payload, 'BYTE')
%
% WORD：每样点 2 字节、小端。BYTE：每样点 1 字节、无符号 0–255。
%
% 字节序不能靠命令声明 —— DHO800 的 :WAVeform:* 一共 14 条命令，**没有**
% :WAVeform:BYTeorder（手册 3.28）。所以按约定解析（小端），并用 YREFerence 判断
% WORD 发的是有符号补码还是偏移二进制：手册 3.28.11 只说「YREFerence 的值与
% :WAVeform:FORMat 的配置有关」，没写是哪种，所以两种都得能吃：
%   参考位置在 0 附近     -> 有符号补码，原样返回
%   参考位置在 32768 附近 -> 偏移二进制，负值要加回 65536
% 手写字节拼装而不是 typecast，是为了不依赖 MATLAB 宿主机的字节序。
if nargin < 3 || isempty(yref)
    yref = 0;
end
b = uint8(payload(:));
if strcmpi(fmt, 'WORD')
    if mod(numel(b), 2) ~= 0
        b = b(1:end-1);            % 半个样本解不出来，直接丢掉
    end
    raw = double(b(1:2:end-1)) + 256 * double(b(2:2:end));
    neg = raw >= 32768;
    raw(neg) = raw(neg) - 65536;
    if yref > 16384                % 偏移二进制约定：还原成无符号再参与公式
        raw(raw < 0) = raw(raw < 0) + 65536;
    end
    raw = raw(:).';
else
    raw = double(b(:)).';
end
end
