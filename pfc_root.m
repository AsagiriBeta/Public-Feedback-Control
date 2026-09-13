function root = pfc_root()
%PFC_ROOT 返回本项目"可写工作根目录"，兼容源码调试与打包成 exe 两种运行方式。
%
%   源码运行：返回本文件所在目录（项目根），行为与以前一致。
%   编译打包：返回用户可写目录，优先级如下
%       1) 环境变量 PFC_HOME
%       2) Windows: %LOCALAPPDATA%\PFC
%       3) ~/.pfc
%       4) tempdir/PFC
%
% 参数存档（pfc_prefs.mat）、默认数据目录（data/）、仪器配置（rigol_config.ini）
% 都放在该目录下，避免编译后写入只读的 MCR 临时目录导致丢失。
persistent cached
if ~isempty(cached)
    root = cached;
    return;
end

envHome = strtrim(getenv('PFC_HOME'));
if ~isempty(envHome)
    root = envHome;
elseif isdeployed
    if ispc && ~isempty(getenv('LOCALAPPDATA'))
        root = fullfile(getenv('LOCALAPPDATA'), 'PFC');
    elseif ~isempty(getenv('HOME'))
        root = fullfile(getenv('HOME'), '.pfc');
    else
        root = fullfile(tempdir, 'PFC');
    end
else
    root = fileparts(mfilename('fullpath'));
    if isempty(root)
        root = pwd;
    end
end

if ~isfolder(root)
    try
        mkdir(root);
    catch
    end
end
cached = root;
end
