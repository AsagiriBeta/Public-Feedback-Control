function m = pfc_ctrl_metric(src, mode)
%PFC_CTRL_METRIC 闭环盯哪一个 SC。
%
%   m = pfc_ctrl_metric()
%   m = pfc_ctrl_metric(src)           界面 / 新实验：缺省 = 2f 窗求和
%   m = pfc_ctrl_metric(src, 'recorded')  读旧 raw.mat：没写字段时按峰/底
%
% 取值：
%   '2f_window_sum'       2f±20 kHz 对 |FFT| 求和（缺省）
%   '2f_peak_over_floor'  2f 峰 / 参考底
% 不锁死目标 dB。不改 WORD/RAW。

if nargin >= 2 && strcmpi(char(string(mode)), 'recorded')
    m = '2f_peak_over_floor';
else
    m = '2f_window_sum';
end
raw = '';
if nargin >= 1 && ~isempty(src)
    if isstruct(src)
        if isfield(src, 'ctrl_metric') && ~isempty(src.ctrl_metric)
            raw = src.ctrl_metric;
        elseif isfield(src, 'params') && isstruct(src.params) && ...
                isfield(src.params, 'ctrl_metric') && ~isempty(src.params.ctrl_metric)
            raw = src.params.ctrl_metric;
        end
    else
        raw = src;
    end
end
s = lower(strtrim(char(string(raw))));
if isempty(s)
    return;
end
if any(strcmp(s, {'2f_peak_over_floor', 'peak', 'peak_floor', 'snr', ...
        'scctrl', '2f_peak'}))
    m = '2f_peak_over_floor';
elseif any(strcmp(s, {'2f_window_sum', 'sum', 'rampsc', 'chien', 'window_sum'}))
    m = '2f_window_sum';
end
end
