function pfc_ui_push(fig, S)
%PFC_UI_PUSH 把一条命令推给网页界面。
%
%   传输优先走 sendEventToHTMLSource（事件名 'pfc'），不要每帧写 h.Data：
%   uihtml 的 Data 是单槽，连写会被后一次盖掉；更糟的是部分 MATLAB 版本
%   把大结构体 Data 赋值当成 HTMLSource 变更 —— 整页重载、弹出
%   「HTMLSource 可能引用不受支持的功能」警告、Alpine 重初始化（调试按钮消失）、
%   图表闪烁。HTMLSource 只在 pfc_ui_app 里设一次。
%
%   时域/频谱先攒在 figure appdata 里，遇到 status / trend / busy 再打成一条
%   cmd='frame' 发出去，每脉冲最多一次 drawnow（采集节奏本身已经限速）。
%
%   S 字段示例：
%       struct('cmd','status','text','采集中…')
%       struct('cmd','busy','on',true,'tab','debug'|'nomb'|'open'|'fb')
%       struct('cmd','waveform','ch','tx'|'pcd','dt_us',...,'y',...)
%       struct('cmd','trend','k',1,'sc',0.1,'ic',0.01,'volt',50,'xmax',40,'ymax',200)
if isempty(fig) || ~isvalid(fig)
    return;
end
h = getappdata(fig, 'pfc_html');
if isempty(h) || ~isvalid(h)
    return;
end
if ~(isstruct(S) && isfield(S, 'cmd'))
    return;
end
try
    cmd = char(string(S.cmd));
    switch cmd
        case 'waveform'
            stash_wave(fig, S);
            return;
        case 'trend'
            stash_field(fig, 'trend', S);
            deliver(h, fig, build_frame(fig), true);
            return;
        case 'status'
            stash_field(fig, 'text', char(string(S.text)));
            deliver(h, fig, build_frame(fig), true);
            return;
        case 'countdown'
            % 倒计时单独发：采集阻塞在 USB 读波形时 MATLAB 推不了，前端靠本地 1 Hz 补跳。
            deliver(h, fig, S, true);
            return;
        otherwise
            % busy / init / params / clearTrend / tab：先把攒着的波形发出去，
            % 再发本条。busy 尤其不能跟波形挤在同一槽里被盖掉。
            flush_pending(h, fig);
            forceDraw = any(strcmp(cmd, {'busy', 'init', 'params'}));
            deliver(h, fig, S, true, forceDraw);
    end
catch
    % 界面正在关闭等情况下静默忽略
end
end

function stash_wave(fig, S)
ch = 'tx';
if isfield(S, 'ch') && strcmpi(char(string(S.ch)), 'pcd')
    ch = 'pcd';
end
stash_field(fig, ch, S);
end

function stash_field(fig, name, val)
p = getappdata(fig, 'pfc_push_pend');
if ~isstruct(p)
    p = struct();
end
p.(name) = val;
setappdata(fig, 'pfc_push_pend', p);
end

function flush_pending(h, fig)
p = getappdata(fig, 'pfc_push_pend');
if ~isstruct(p) || (isempty(fieldnames(p)))
    return;
end
if ~isfield(p, 'tx') && ~isfield(p, 'pcd') && ~isfield(p, 'trend') && ~isfield(p, 'text')
    return;
end
deliver(h, fig, build_frame(fig), false);
end

function F = build_frame(fig)
p = getappdata(fig, 'pfc_push_pend');
setappdata(fig, 'pfc_push_pend', struct());
F = struct('cmd', 'frame');
if isstruct(p)
    if isfield(p, 'tx'),    F.tx = p.tx;       end
    if isfield(p, 'pcd'),   F.pcd = p.pcd;     end
    if isfield(p, 'trend'), F.trend = p.trend; end
    if isfield(p, 'text'),  F.text = p.text;   end
end
end

function deliver(h, fig, S, doDraw, forceDraw)
%DELIVER 事件通道为主；只有事件发不出去时才退回写 Data（启动瞬间页面未就绪）。
if nargin < 5, forceDraw = false; end
if ~(isstruct(S) && isfield(S, 'cmd'))
    return;
end
sent = false;
try
    sendEventToHTMLSource(h, 'pfc', S);
    sent = true;
catch
end
if ~sent
    try
        h.Data = S;
    catch
        return;
    end
end
if ~doDraw
    return;
end
% 每条脉冲最多一次完整 drawnow：让 STOP / 关窗进事件队列。
% 不能用 limitrate —— 关窗、STOP 会被合并掉，表现为「停不下来」。
% nocallbacks 同样会把 CloseRequestFcn 推迟，所以这里必须是完整 drawnow。
last = getappdata(fig, 'pfc_push_draw_t');
nowt = tic;
if forceDraw || isempty(last) || toc(last) > 0.04
    drawnow;
    setappdata(fig, 'pfc_push_draw_t', nowt);
end
end
