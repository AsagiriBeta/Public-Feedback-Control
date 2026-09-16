function fig = pfc_ui_app()
%PFC_UI_APP 新版界面宿主：uifigure + uihtml（前端 Alpine.js + uPlot）。
%
% 界面本体是 web/ 下的静态页面，通过 uihtml 嵌进 uifigure；MATLAB 只负责仪器与算法，
% 两者用 uihtml 的通道通信：
%   MATLAB -> JS : sendEventToHTMLSource(h,'pfc',S)  （启动瞬间可写一次 h.Data）
%   JS -> MATLAB : sendEventToMATLAB('action'|'params'|'ready', ...)  -> pfc_ui_event
% 相比 GUIDE：布局交给 CSS（自适应/DPI/圆角全不用手写），图表交给 uPlot。
root = pfc_web_root();
src = fullfile(root, 'index.html');
if ~isfile(src)
    error('PFC:ui:noWeb', '找不到前端资源：%s', src);
end

C = pfc_ui_colors();
scr = get(0, 'ScreenSize');
% 先按「舒服的默认尺寸」估，再钳进当前屏，避免高 DPI / 小笔记本上窗口伸出屏幕，
% 把右下角 STOP 裁到任务栏下面。
availW = max(640, scr(3) - 40);
availH = max(480, scr(4) - 80);
W = min([1500, max(1080, scr(3) - 80), availW]);
H = min([940, max(700, scr(4) - 130), availH]);
left = max(10, min(60, scr(3) - W - 10));
bottom = max(10, min(60, scr(4) - H - 10));

fig = uifigure('Name', ['PFC  ·  DHO814 / DG2052  ·  ' pfc_version('label')], ...
    'Color', C.fig, 'Position', [left bottom W H]);

try
    g = uigridlayout(fig, [1 1]);
    g.Padding = [0 0 0 0];
    g.BackgroundColor = C.fig;
    h = uihtml(g);
catch
    h = uihtml(fig);
    h.Position = [1 1 W - 2 H - 2];
end
% HTMLSource 只设这一次。之后只走 Data / sendEventToHTMLSource；
% 再赋值 HTMLSource（含清空再设）会整页重载，MATLAB 弹出
% 「HTMLSource 可能引用不受支持的功能」警告，Alpine 状态丢失。
h.HTMLSource = src;
try, h.Scrollable = 'off'; catch, end
% 首次加载时 MATLAB 可能仍提示「HTMLSource 可能引用不受支持的功能」：
% Alpine 用 new Function 解析 x-model / 表达式，属于 uihtml 已知限制，不是运行时 JS 错误。
% 不要为此重设 HTMLSource（清空再赋值会整页闪烁、按钮状态丢失）。

S = pfc_prefs('get');
setappdata(fig, 'pfc_html', h);
setappdata(fig, 'pfc_params', S);

h.HTMLEventReceivedFcn = @(src, evt) pfc_ui_event(fig, evt);
set(fig, 'CloseRequestFcn', @(s, ~) pfc_ui_close(s));

% 页面未就绪时 sendEventToHTMLSource 会丢；Data 会由 JS setup() 补读一次。
% 这里故意不 drawnow，避免 CEF 还没跑 setup 就刷一遍空页。
try
    h.Data = struct('cmd', 'init', 'params', S);
catch
end
end

% ---------------------------------------------------------------- 关闭
function pfc_ui_close(fig)
% 关窗 = 停一切：置中止、关射频、释放 visadev（打断正在阻塞的波形读），再存参数、删窗口。
% 不能在这里 wait 采集循环 —— CloseRequestFcn 是从循环里的 drawnow 嵌进来的，一等就死锁。
% 循环用 pfc_visa('alive', token) 看到窗口没了 / abort 就会自己退。
try, pfc_visa('abort_run'); catch, end
try
    pfc_prefs('save', getappdata(fig, 'pfc_params'));
catch
end
delete(fig);
end

% ---------------------------------------------------------------- 事件分发
function pfc_ui_event(fig, evt)
if isempty(fig) || ~isvalid(fig)
    return;
end
name = '';
data = [];
try, name = char(string(evt.HTMLEventName)); catch, end
try, data = evt.HTMLEventData; catch, end

switch name
    case 'params'   % 前端改了参数
        % 负载形如 struct('params', p, 'live', 0|1)。
        % live=true 表示用户「确认」了这次输入（回车 / 失焦），只有这时才把新的
        % 采集频率/电压下发给信号源；逐键输入只落盘不下发 —— 否则在调试中打
        % 「150」会先输出 1 mVpp、再 15、再 150，等于对着样品乱扫。
        D = data;
        live = false;
        if isstruct(data) && isfield(data, 'params')
            D = data.params;
            if isfield(data, 'live')
                live = logical(data.live);
            end
        end
        apply_params(fig, D, live);

    case 'action'   % 前端点了按钮
        act = '';
        if isstruct(data) && isfield(data, 'name')
            act = char(string(data.name));
        end
        % 动作事件自带点击那一刻的表单值：先合并进来，保证「界面上看到什么就跑什么」，
        % 不必依赖 params 事件是否已经先到（见 web/app.js 的 action）。
        if isstruct(data) && isfield(data, 'params')
            apply_params(fig, data.params, false);
        end
        pfc_ui_action(fig, act);

    case 'ready'    % JS setup() 完成，再推一次 MATLAB 存档，避免页面先显示 JS 缺省 2 dB
        % 不要在这里吞 JS 表单：setup 瞬间 Alpine 还是出厂缺省（target_db=2），
        % 若先 merge 会把上次 prefs 里的 3 盖成 2，界面闪 2、实验却按错的数跑。
        S = getappdata(fig, 'pfc_params');
        if isstruct(S)
            pfc_ui_push(fig, struct('cmd', 'init', 'params', S));
        end
end
end

function S = apply_params(fig, D, live)
%APPLY_PARAMS 合并前端送来的参数 -> 更新缓存 -> 落盘 ->（可选）下发到信号源。
if nargin < 3
    live = false;
end
S = merge_params(getappdata(fig, 'pfc_params'), D);
setappdata(fig, 'pfc_params', S);
pfc_prefs('save', S);
if live
    % 调试采集正在跑时把新频率/电压立刻下发；没在跑时 pfc_debug_live 会直接返回。
    pfc_debug_live('apply', pfc_ui_html(fig));
end
end

function S = merge_params(S, D)
if ~isstruct(D) || ~isstruct(S)
    return;
end
allow = {};
try
    allow = fieldnames(pfc_prefs('defaults'));
catch
end
extra = {'cav_pct', 'amp_gain', 'ctrl_metric', 'target_db'};
fn = fieldnames(D);
for i = 1:numel(fn)
    k = fn{i};
    % 允许网页新增字段写进缓存；target_db 必须总能合并，不能因为旧缓存缺字段就丢掉。
    if ~isfield(S, k) && ~any(strcmp(k, allow)) && ~any(strcmp(k, extra))
        continue;
    end
    v = D.(k);
    if iscell(v) && isscalar(v)
        v = v{1};
    end
    if isnumeric(v)
        if isscalar(v) && isfinite(v)
            S.(k) = double(v);
        end
    elseif ischar(v) || isstring(v)
        s = strtrim(char(v));
        n = str2double(s);
        % 数字框经 uihtml 变成字符串时（「2」「3.0」）仍按数值写入，否则闭环会退回缺省 2 dB。
        if isfinite(n) && ~strcmpi(k, 'studyID') && ~strcmpi(k, 'directory') && ~strcmpi(k, 'ctrl_metric')
            S.(k) = n;
        else
            S.(k) = s;
        end
    end
end
end

% ---------------------------------------------------------------- 按钮动作
function pfc_ui_action(fig, act)
if isempty(act)
    return;
end
ui = pfc_ui_html(fig);

% 不需要独占仪器的动作，先处理掉
switch act
    case 'stop'
        % STOP 任何时候都要能按：不抢锁，直接停。不弹窗。
        global pfc_abort %#ok<GVMIS>
        pfc_abort = true;
        pfc_visa('rf_off');
        pfc_ui_push(fig, struct('cmd', 'countdown', 'on', false));
        pfc_ui_push(fig, struct('cmd', 'status', 'text', '正在停止…'));
        return;
    case 'browse'
        act_browse(fig);
        return;
    case 'instr'
        if pfc_visa('is_busy')
            pfc_ui_push(fig, struct('cmd', 'status', 'text', '采集进行中，请先 STOP FUS。'));
        else
            pfc_instr_dialog();
        end
        return;
    case 'update'
        pfc_update_flow(fig);
        return;
end

% 以下动作要独占仪器：先抢运行锁，锁住前端按钮，结束（含出错）自动解锁。
% 已经在跑就只切到该步骤 / 写状态行，绝不 warndlg —— 连点 + 旧循环 drawnow
% 会把对话框堆成风暴，电脑像死机，STOP 也被挡住。
[ok, token] = pfc_visa('try_busy', fig);
if ~ok
    t = step_tab(act);
    sameFig = false;
    try
        sameFig = isstruct(token) && isfield(token, 'fig') && ...
            ~isempty(token.fig) && isvalid(token.fig) && token.fig == fig;
    catch
    end
    if sameFig
        % 本窗口已经在跑：把 busy 钉回去（页面刷新会把乐观锁弄丢）
        busyS = struct('cmd', 'busy', 'on', true);
        if ~isempty(t), busyS.tab = t; end
        pfc_ui_push(fig, busyS);
    else
        % 别的窗口/旧循环还在：本页不要卡在「假 busy」，否则 STOP 键会变成死锁
        pfc_ui_push(fig, struct('cmd', 'busy', 'on', false));
        if ~isempty(t)
            pfc_ui_push(fig, struct('cmd', 'tab', 'tab', t));
        end
    end
    pfc_ui_push(fig, struct('cmd', 'status', 'text', '已有采集在运行。请按 STOP FUS。'));
    return;
end
% 实验一开始就把前端切到该步骤页（页签按步骤分，不是按时域/趋势分）。
busyS = struct('cmd', 'busy', 'on', true);
t = step_tab(act);
if ~isempty(t)
    busyS.tab = t;
end
pfc_ui_push(fig, busyS);
cleanup = onCleanup(@() unbusy(fig, token)); %#ok<NASGU>

try
    switch act
        case 'oneshot',  pfc_oneshot(ui);
        case 'debug',    pfc_debug_run(ui);
        case 'noMB'
            warn_amp(fig);
            pfc_run_experiment('before', ui);
        case 'openMB'
            warn_amp(fig);
            pfc_run_experiment('open_mb', ui);
        case 'feedback'
            warn_amp(fig);
            pfc_run_experiment('feedback', ui);
    end
catch err
    % 关窗 / STOP 引起的 visadev 失败不是用户要看的错误
    if ~is_stop_noise(err)
        pfc_ui_push(fig, struct('cmd', 'status', 'text', err.message));
        if isvalid(fig)
            errordlg(err.message, 'PFC 运行出错');
        end
    end
end
end

function unbusy(fig, token)
if nargin < 2, token = []; end
% 先看是不是自己这一轮：end_busy 会把 gen 清掉主人，之后就分不清了。
owned = isempty(token) || pfc_visa('owns', token);
pfc_visa('end_busy', token);
if owned && ~isempty(fig) && isvalid(fig)
    pfc_ui_push(fig, struct('cmd', 'busy', 'on', false));
end
end

function tf = is_stop_noise(err)
global pfc_abort %#ok<GVMIS>
if ~isempty(pfc_abort) && logical(pfc_abort)
    tf = true;
    return;
end
msg = '';
try, msg = err.message; catch, end
tf = contains(msg, 'invalid', 'IgnoreCase', true) || ...
    contains(msg, 'deleted', 'IgnoreCase', true) || ...
    contains(msg, 'closed', 'IgnoreCase', true);
end

function warn_amp(fig)
%WARN_AMP 2/3/4 起步时一行状态提醒开功放。不要弹窗——连点会堆成风暴。
S = getappdata(fig, 'pfc_params');
g = 40;
if isstruct(S) && isfield(S, 'amp_gain') && isnumeric(S.amp_gain) && isfinite(S.amp_gain)
    g = double(S.amp_gain);
end
if g >= 40
    pfc_ui_push(fig, struct('cmd', 'status', 'text', sprintf('确认功放已开 ×%.4g', g)));
end
end

function t = step_tab(act)
% 前端步骤页签名：调试 / 2 无微泡 / 3 开环 / 4 闭环
switch act
    case {'oneshot', 'debug'}
        t = 'debug';
    case 'noMB'
        t = 'nomb';
    case 'openMB'
        t = 'open';
    case 'feedback'
        t = 'fb';
    otherwise
        t = '';
end
end

function act_browse(fig)
S = getappdata(fig, 'pfc_params');
cur = '';
if isstruct(S) && isfield(S, 'directory')
    cur = strtrim(char(string(S.directory)));
end
if isempty(cur) || ~isfolder(cur)
    cur = pwd;
end
d = uigetdir(cur, '选择保存目录 / Choose save folder');
% uigetdir 取消返回 0；此时保持原目录，否则会被写成字符串 "0" 并新建 ./0 目录
if ~ischar(d) || isempty(d)
    return;
end
S.directory = d;
setappdata(fig, 'pfc_params', S);
pfc_prefs('save', S);
pfc_ui_push(fig, struct('cmd', 'params', 'params', S));
end
