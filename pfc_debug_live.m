function varargout = pfc_debug_live(cmd, handles, fdef, vdef)
%PFC_DEBUG_LIVE 调试采集运行中：从 GUI 改频率/电压并立刻下发到 DG2052。
persistent active freq volt

if isempty(active), active = false; end
if nargin < 2, handles = []; end
if nargin < 3 || isempty(fdef), fdef = 1.5; end
if nargin < 4 || isempty(vdef), vdef = 20; end

switch lower(cmd)
    case 'start'
        [freq, volt] = read_fv(handles, fdef, vdef);
        active = true;
        push_cw(freq, volt);
        varargout = {freq, volt};
    case 'stop'
        active = false;
    case 'active'
        varargout{1} = logical(active);
    case 'apply'
        if ~active
            return;
        end
        [f, v] = read_fv(handles, freq, volt);
        if abs(f - freq) < 1e-9 && abs(v - volt) < 1e-9
            return;
        end
        freq = f;
        volt = v;
        push_cw(freq, volt);
    case 'get'
        if nargout >= 1, varargout{1} = freq; end
        if nargout >= 2, varargout{2} = volt; end
    otherwise
        error('pfc_debug_live:cmd', '未知命令 %s', cmd);
end
end

function [f, v] = read_fv(handles, f0, v0)
f = f0;
v = v0;
if isempty(handles)
    return;
end
hf = [];
hv = [];
if isfield(handles, 'debug_freq') && isgraphics(handles.debug_freq)
    hf = handles.debug_freq;
end
if isfield(handles, 'debug_volt') && isgraphics(handles.debug_volt)
    hv = handles.debug_volt;
end
if ~isempty(hf)
    x = str2double(get(hf, 'String'));
    if isfinite(x) && x > 0
        f = x;
    end
end
if ~isempty(hv)
    x = str2double(get(hv, 'String'));
    if isfinite(x) && x > 0
        v = x;
    end
end
end

function push_cw(freq, volt)
cfg = rigol_instr_config();
dev = pfc_visa('fgen');
rigol_dg2052_cw(dev, cfg.awg_channel, freq, volt);
rigol_dg2052_output_set(dev, true);
end
