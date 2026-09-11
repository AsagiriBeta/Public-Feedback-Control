function pfc_app()
%PFC_APP 启动入口（开发调试与打包成 exe 共用）。
%   MATLAB Compiler 需要以函数作为入口点，因此打包时入口选本文件；
%   开发时在命令窗口输入 pfc_app 或 start_gui 均可。
thisdir = fileparts(mfilename('fullpath'));
if isempty(thisdir)
    thisdir = pwd;
end
if ~isdeployed
    addpath(thisdir);
    addpath(fullfile(thisdir, 'rigol'));
end

% 关掉上一次残留的窗口（同名/同工程）
old = findall(0, 'Type', 'figure');
if ~isempty(old)
    names = get(old, 'Name');
    if ~iscell(names)
        names = {names};
    end
    for k = 1:numel(old)
        n = names{k};
        if ischar(n) && (contains(n, 'PFC') || contains(n, 'UTSW_FindGrid') || ...
                contains(n, 'MatlabScript_FeedbackControl'))
            delete(old(k));
        end
    end
end

MatlabScript_FeedbackControl;
drawnow;
end
