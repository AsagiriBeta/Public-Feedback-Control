function pfc_ui_push(fig, S)
%PFC_UI_PUSH 把一条命令推给网页界面（uihtml 的 Data 通道）。
%
%   MATLAB -> JS:  h.Data = S   ->  JS 里 addEventListener('DataChanged') 收到
%   S 必须是 jsonencode 能处理的结构体，字段示例：
%       struct('cmd','status','text','采集中…')
%       struct('cmd','busy','on',true)
%       struct('cmd','waveform','dt_us',...,'y',...,'f',...,'db',...,'marks',...)
%       struct('cmd','trend','k',1,'sc',0.1,'ic',0.01,'volt',50,'xmax',40,'ymax',200)
% 注意 Data 变更只单向触发：这里设值只到 JS，不会回头触发 DataChangedFcn。
h = getappdata(fig, 'pfc_html');
if isempty(h) || ~isvalid(h)
    return;
end
try
    h.Data = S;
    % 这里必须是完整的 drawnow，不能用 drawnow limitrate：
    % Data 是单槽属性，一次采集迭代里会连着推 waveform / trend / status 好几条，
    % limitrate 会合并刷新，后一次赋值把前一次盖掉 —— 表现就是点图在动、
    % 时域/频谱图卡住不更新。每条都真正落到浏览器只多花几毫秒，而推送频率
    % 本来就被采集节奏限住（闭环 ≈ 每发 3 条，调试 ≈ 每次循环 2 条）。
    drawnow;
catch
    % 界面正在关闭等情况下静默忽略
end
end
