function pcd_app()
%PCD_APP 启动入口（开发调试与打包成 exe 共用）。
%
% 界面：uifigure + uihtml，本体是 web/ 下的静态页面（Alpine.js + uPlot）。
% MATLAB Compiler 需要以函数作为入口点，因此打包时入口选本文件。
thisdir = fileparts(mfilename('fullpath'));
if isempty(thisdir)
    thisdir = pwd;
end
if ~isdeployed
    pcd_setup();   % 把 src/ rigol/ tools/ 一次全部加入搜索路径
end

close_old_windows();
pcd_ui_app();
drawnow;
end

function close_old_windows()
% 重复启动时先关掉上一次残留的窗口，避免越叠越多
old = findall(0, 'Type', 'figure');
if isempty(old)
    return;
end
names = get(old, 'Name');
if ~iscell(names)
    names = {names};
end
for k = 1:numel(old)
    n = names{k};
    if ischar(n) && (contains(n, 'PCD') || contains(n, 'PCD') || contains(n, 'UTSW_FindGrid'))
        % 用 close 而不是 delete：走 CloseRequestFcn，旧窗口里若还在跑采集
        % 会被中止、射频被关掉；delete 会绕过它，超声可能一直开着。
        try
            close(old(k));
        catch
            delete(old(k));
        end
    end
end
end
