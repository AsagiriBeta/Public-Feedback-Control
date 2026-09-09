function [freq, volt] = pfc_gui_acquire_fv(handles)
%PFC_GUI_ACQUIRE_FV 读「1. 采集」框内的频率/电压（与 FUS 参数独立）。
freq = 1.5;
volt = 20;
if nargin < 1 || isempty(handles)
    return;
end
freq = read_pos(handles, 'debug_freq', freq);
volt = read_pos(handles, 'debug_volt', volt);
end

function v = read_pos(handles, tag, def)
v = def;
if ~isfield(handles, tag) || ~isgraphics(handles.(tag))
    o = findobj(gcbf, 'Tag', tag);
    if isempty(o)
        return;
    end
    h = o(1);
else
    h = handles.(tag);
end
x = str2double(get(h, 'String'));
if isfinite(x) && x > 0
    v = x;
end
end
