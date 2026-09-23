function varargout = pcd_visa(cmd, varargin)
%PCD_VISA 示波器/信号源 visadev 单例 + 全局采集会话锁。
%  scope = pcd_visa('scope')
%  fgen  = pcd_visa('fgen')
%  pcd_visa('rf_off')
%  pcd_visa('rf_off_if', token)   % 只关自己这一轮，别把后来那一轮的射频也掐了
%  pcd_visa('close')              % 断开当前连接（改了 VISA 地址后调用，下次采集重连）
%  pcd_visa('reset_busy')
%  tf    = pcd_visa('is_busy')
%  [ok, token] = pcd_visa('try_busy', fig)  % 抢到运行权为 true；fig 是主人窗口
%  pcd_visa('end_busy', token)    % token 对不上说明已经是别人的会话，不要解
%  token = pcd_visa('token')
%  tf    = pcd_visa('alive', token)        % 本轮是否还该继续（STOP / 关窗 / 被顶替）
%  tf    = pcd_visa('owns', token)
%  pcd_visa('abort_run')          % 关窗：置中止、关射频、释放 visadev 打断阻塞读

global pcd_visa_state fgen
pcd_visa_state = ensure_state(pcd_visa_state);

switch lower(cmd)
    case 'scope'
        pcd_visa_state.scope = reuse_visadev(pcd_visa_state.scope, ...
            rigol_instr_config().scope_visa);
        varargout{1} = pcd_visa_state.scope;
    case 'fgen'
        pcd_visa_state.fgen = reuse_visadev(pcd_visa_state.fgen, ...
            rigol_instr_config().awg_visa);
        fgen = pcd_visa_state.fgen;
        varargout{1} = pcd_visa_state.fgen;
    case 'rf_off'
        rf_off_now();
    case 'rf_off_if'
        token = [];
        if ~isempty(varargin), token = varargin{1}; end
        if owns_token(token)
            rf_off_now();
        end
    case 'close'
        release_dev(pcd_visa_state.scope);
        release_dev(pcd_visa_state.fgen);
        pcd_visa_state.scope = [];
        pcd_visa_state.fgen = [];
        pcd_visa_state.busy = false;
        pcd_visa_state.fig = [];
        pcd_visa_state.gen = pcd_visa_state.gen + 1;
        clear global fgen
        sync_appdata();
    case 'is_busy'
        varargout{1} = logical(pcd_visa_state.busy);
    case 'try_busy'
        fig = [];
        if ~isempty(varargin), fig = varargin{1}; end
        % 旧窗口已经删了、循环还卡在 visadev 上：锁没有合法主人，允许新界面接手，
        % 同时 gen+1 让旧循环的 token 立刻失效，避免两路抢同一台示波器。
        if pcd_visa_state.busy && ~owner_alive()
            pcd_visa_state.busy = false;
            pcd_visa_state.fig = [];
            pcd_visa_state.gen = pcd_visa_state.gen + 1;
            release_dev(pcd_visa_state.scope);
            pcd_visa_state.scope = [];
        end
        if pcd_visa_state.busy
            varargout{1} = false;
            varargout{2} = snapshot_token();
            return;
        end
        pcd_visa_state.busy = true;
        pcd_visa_state.fig = fig;
        pcd_visa_state.gen = pcd_visa_state.gen + 1;
        sync_appdata();
        varargout{1} = true;
        varargout{2} = snapshot_token();
    case 'end_busy'
        token = [];
        if ~isempty(varargin), token = varargin{1}; end
        if ~isempty(token) && ~owns_token(token)
            return;
        end
        pcd_visa_state.busy = false;
        pcd_visa_state.fig = [];
        rf_off_now();
        sync_appdata();
    case 'reset_busy'
        pcd_visa_state.busy = false;
        pcd_visa_state.fig = [];
        sync_appdata();
    case 'token'
        varargout{1} = snapshot_token();
    case 'alive'
        token = [];
        if ~isempty(varargin), token = varargin{1}; end
        varargout{1} = session_alive(token);
    case 'owns'
        token = [];
        if ~isempty(varargin), token = varargin{1}; end
        varargout{1} = owns_token(token);
    case 'abort_run'
        % 关窗路径：不能在 CloseRequestFcn 里等循环结束（它嵌在 drawnow 里，会死锁）。
        % 置中止、清主人窗口、关掉 visadev 让正在阻塞的 :WAVeform:DATA? 立刻失败。
        global pcd_abort %#ok<GVMIS>
        pcd_abort = true;
        pcd_visa_state.fig = [];
        rf_off_now();
        release_dev(pcd_visa_state.scope);
        pcd_visa_state.scope = [];
        sync_appdata();
    otherwise
        error('pcd_visa:cmd', '未知命令 %s', cmd);
end
end

function S = ensure_state(S)
if isempty(S) || ~isstruct(S)
    S = struct('scope', [], 'fgen', [], 'busy', false, 'fig', [], 'gen', 0);
    return;
end
if ~isfield(S, 'busy'),  S.busy = false; end
if ~isfield(S, 'fig'),   S.fig = []; end
if ~isfield(S, 'gen') || isempty(S.gen), S.gen = 0; end
if ~isfield(S, 'scope'), S.scope = []; end
if ~isfield(S, 'fgen'),  S.fgen = []; end
end

function tok = snapshot_token()
global pcd_visa_state
pcd_visa_state = ensure_state(pcd_visa_state);
tok = struct('gen', double(pcd_visa_state.gen), 'fig', pcd_visa_state.fig);
end

function tf = owns_token(token)
global pcd_visa_state
pcd_visa_state = ensure_state(pcd_visa_state);
tf = false;
if ~isstruct(token) || ~isfield(token, 'gen')
    return;
end
tf = double(pcd_visa_state.gen) == double(token.gen);
end

function tf = owner_alive()
global pcd_visa_state
pcd_visa_state = ensure_state(pcd_visa_state);
fig = pcd_visa_state.fig;
if isempty(fig)
    tf = false;
    return;
end
try
    tf = isvalid(fig);
catch
    tf = false;
end
end

function tf = session_alive(token)
% 本轮采集还该继续：没按 STOP、窗口还在、没被新一轮 try_busy 顶替。
global pcd_abort pcd_visa_state %#ok<GVMIS>
pcd_visa_state = ensure_state(pcd_visa_state);
tf = false;
if ~isempty(pcd_abort) && logical(pcd_abort)
    return;
end
if ~pcd_visa_state.busy
    return;
end
if ~isempty(token) && ~owns_token(token)
    return;
end
if ~owner_alive()
    return;
end
tf = true;
end

function rf_off_now()
global pcd_visa_state fgen
try
    if is_open(pcd_visa_state.fgen)
        rigol_dg2052_output_set(pcd_visa_state.fgen, false);
    elseif is_open(fgen)
        rigol_dg2052_output_set(fgen, false);
    end
catch
end
end

function sync_appdata()
% 挂在 groot 上：关掉 uifigure 之后还能查到「有没有一轮采集没退干净」。
global pcd_visa_state
try
    setappdata(0, 'pcd_run', snapshot_token());
    setappdata(0, 'pcd_run_busy', logical(pcd_visa_state.busy));
catch
end
end

function release_dev(dev)
%RELEASE_DEV 显式关闭 visadev 连接。
% 只把句柄置空是不够的：连接的真正释放要等 MATLAB 回收对象，而仪器设置里
% 「先释放再扫描」的时序很紧 —— 回收没跟上就会误判资源被占用（visadevfind 仍列它），
% 或者 *IDN? 直接失败。delete 是同步关闭，随后 visadevfind 就不会再看到它。
if isempty(dev)
    return;
end
try
    delete(dev);
catch
    % 已经无效 / 已经关掉了，忽略
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
addr = strtrim(char(string(addr)));
if isempty(addr)
    error('pcd_visa:noAddr', ...
        ['尚未配置仪器地址。\n请在界面点「仪器设置 → 扫描仪器」后保存。\n配置文件：%s'], ...
        rigol_instr_config('file'));
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
error('pcd_visa:open', ...
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
