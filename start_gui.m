%START_GUI 打开 PCD 闭环控制 GUIDE 界面。
% 在 MATLAB 编辑器中打开本文件后点「运行」，或在命令窗口输入 start_gui。
thisdir = fileparts(mfilename('fullpath'));
if isempty(thisdir)
    thisdir = pwd;
end
cd(thisdir);
addpath(thisdir);
addpath(fullfile(thisdir, 'rigol'));

old = findall(0, 'Type', 'figure');
if ~isempty(old)
    names = get(old, 'Name');
    if ~iscell(names)
        names = {names};
    end
    for k = 1:numel(old)
        n = names{k};
        if contains(n, 'PFC') || contains(n, 'UTSW_FindGrid') || ...
                contains(n, 'MatlabScript_FeedbackControl')
            delete(old(k));
        end
    end
end

MatlabScript_FeedbackControl;
drawnow;
