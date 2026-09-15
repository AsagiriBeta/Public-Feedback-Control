function fig = pfc_ui_app()
%PFC_UI_APP 新版界面宿主：uifigure + uihtml（前端 Alpine.js + uPlot）。
%
% 界面本体是 web/ 下的静态页面，通过 uihtml 嵌进 uifigure；MATLAB 只负责仪器与算法，
% 两者用 uihtml 的通道通信：
%   MATLAB -> JS : h.Data = struct('cmd',...)      （见 pfc_ui_push）
%   JS -> MATLAB : sendEventToMATLAB('action'|'params', ...)  -> pfc_ui_event
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
h.HTMLSource = src;

S = pfc_prefs('get');
setappdata(fig, 'pfc_html', h);
setappdata(fig, 'pfc_params', S);

h.HTMLEventReceivedFcn = @(src, evt) pfc_ui_event(fig, evt);
set(fig, 'CloseRequestFcn', @(s, ~) pfc_ui_close(s));

pfc_ui_push(fig, struct('cmd', 'init', 'params', S));
end

% ---------------------------------------------------------------- 关闭
function pfc_ui_close(fig)
% 关窗 = 停一切：先置中止标志、关射频，再存参数、删窗口。
% 采集循环只看 pfc_abort，不设它的话关掉窗口后实验会继续跑、射频一直开着
% （只是碰巧在下一次 ui.status 处因句柄失效报错才停），而用户按了 X 会以为已经停了。
global pfc_abort %#ok<GVMIS>
pfc_abort = true;
try, pfc_visa('rf_off'); catch, end
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
fn = fieldnames(D);
for i = 1:numel(fn)
    k = fn{i};
    if ~isfield(S, k)
        continue;
    end
    v = D.(k);
    if isnumeric(v)
        if isscalar(v) && isfinite(v)
            S.(k) = double(v);
        end
    elseif ischar(v) || isstring(v)
        S.(k) = char(v);
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
        % STOP 任何时候都要能按：不抢锁，直接停
        global pfc_abort %#ok<GVMIS>
        pfc_abort = true;
        pfc_visa('rf_off');
        return;
    case 'browse'
        act_browse(fig);
        return;
    case 'instr'
        if pfc_visa('is_busy')
            warndlg('采集进行中，请先 STOP。', 'PFC');
        else
            pfc_instr_dialog();
        end
        return;
    case 'update'
        pfc_update_flow(fig);
        return;
end

% 以下动作要独占仪器：先抢运行锁，锁住前端按钮，结束（含出错）自动解锁
if ~pfc_visa('try_busy')
    warndlg('已有采集在运行。请等待结束，或按 STOP FUS。', 'PFC');
    return;
end
pfc_ui_push(fig, struct('cmd', 'busy', 'on', true));
cleanup = onCleanup(@() unbusy(fig)); %#ok<NASGU>

try
    switch act
        case 'oneshot',  pfc_oneshot(ui);
        case 'debug',    pfc_debug_run(ui);
        case 'noMB',     pfc_run_experiment('before', ui);
        case 'openMB',   pfc_run_experiment('open_mb', ui);
        case 'feedback', pfc_run_experiment('feedback', ui);
    end
catch err
    errordlg(err.message, 'PFC 运行出错');
end
end

function unbusy(fig)
pfc_visa('end_busy');
if ~isempty(fig) && isvalid(fig)
    pfc_ui_push(fig, struct('cmd', 'busy', 'on', false));
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
