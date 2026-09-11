function varargout = pfc_visa(cmd, varargin)
%PFC_VISA 示波器/信号源 visadev 单例，避免重复打开同一 USB 资源。
%  scope = pfc_visa('scope')
%  fgen  = pfc_visa('fgen')
%  pfc_visa('rf_off')
%  pfc_visa('close')       % 断开当前连接（改了 VISA 地址后调用，下次采集重连）
%  pfc_visa('reset_busy')
%  tf    = pfc_visa('is_busy')
%  ok    = pfc_visa('try_busy')     % 抢到运行权为 true
%  pfc_visa('end_busy')

global pfc_visa_state fgen
if isempty(pfc_visa_state) || ~isstruct(pfc_visa_state)
    pfc_visa_state = struct('scope', [], 'fgen', [], 'busy', false);
end

switch lower(cmd)
    case 'scope'
        pfc_visa_state.scope = reuse_visadev(pfc_visa_state.scope, ...
            rigol_instr_config().scope_visa);
        varargout{1} = pfc_visa_state.scope;
    case 'fgen'
        pfc_visa_state.fgen = reuse_visadev(pfc_visa_state.fgen, ...
            rigol_instr_config().awg_visa);
        fgen = pfc_visa_state.fgen;
        varargout{1} = pfc_visa_state.fgen;
    case 'rf_off'
        try
            if is_open(pfc_visa_state.fgen)
                rigol_dg2052_output_set(pfc_visa_state.fgen, false);
            elseif is_open(fgen)
                rigol_dg2052_output_set(fgen, false);
            end
        catch
        end
    case 'close'
        pfc_visa_state.scope = [];
        pfc_visa_state.fgen = [];
        pfc_visa_state.busy = false;
        clear global fgen
    case 'is_busy'
        varargout{1} = logical(pfc_visa_state.busy);
    case 'try_busy'
        if pfc_visa_state.busy
            varargout{1} = false;
        else
            pfc_visa_state.busy = true;
            varargout{1} = true;
        end
    case 'end_busy'
        pfc_visa_state.busy = false;
        pfc_visa('rf_off');
    case 'reset_busy'
        pfc_visa_state.busy = false;
    otherwise
        error('pfc_visa:cmd', '未知命令 %s', cmd);
end
end

function tf = is_open(dev)
tf = ~isempty(dev);
if ~tf, return; end
try
    tf = isvalid(dev);
catch
    tf = false;
end
end

function dev = reuse_visadev(dev, addr)
if is_open(dev)
    try, dev.Timeout = 60; catch, end
    return;
end
cands = visa_candidates(addr);
for i = 1:numel(cands)
    found = find_existing(cands{i});
    if ~isempty(found)
        dev = found;
        try, dev.Timeout = 60; catch, end
        return;
    end
end
lastErr = [];
for i = 1:numel(cands)
    try
        dev = visadev(cands{i});
        dev.Timeout = 60;
        return;
    catch err
        lastErr = err;
        found = find_existing(cands{i});
        if ~isempty(found)
            dev = found;
            try, dev.Timeout = 60; catch, end
            return;
        end
    end
end
if ~isempty(lastErr)
    rethrow(lastErr);
end
error('pfc_visa:open', ...
    ['无法打开 %s\n请在界面「仪器设置」中确认 VISA 地址（配置文件：%s）'], ...
    addr, rigol_instr_config('file'));
end

function cands = visa_candidates(addr)
a = string(addr);
cands = {char(a)};
if contains(a, '::0::INSTR')
    cands{end+1} = char(replace(a, '::0::INSTR', '::INSTR'));
else
    cands{end+1} = char(replace(a, '::INSTR', '::0::INSTR'));
end
end

function dev = find_existing(addr)
dev = [];
if exist('visadevfind', 'file') ~= 2 && exist('visadevfind', 'builtin') ~= 5
    return;
end
try
    allDev = visadevfind;
catch
    return;
end
if isempty(allDev)
    return;
end
for k = 1:numel(allDev)
    try
        rn = string(allDev(k).ResourceName);
        if contains(rn, string(addr)) || contains(string(addr), rn)
            dev = allDev(k);
            return;
        end
    catch
    end
end
end
