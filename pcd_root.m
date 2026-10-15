function root = pcd_root()
%PCD_ROOT 返回本项目"可写工作根目录"，兼容源码调试与打包成 exe 两种运行方式。
%
%   源码运行：返回本文件所在目录（项目根），行为与以前一致。
%   编译打包：返回用户可写目录，优先级如下
%       1) 环境变量 PCD_HOME（兼容旧名 PFC_HOME）
%       2) Windows: %LOCALAPPDATA%\PCD（若只有旧的 PFC 目录会自动沿用）
%       3) ~/.pcd（若只有旧的 ~/.pfc 会自动沿用）
%       4) tempdir/PCD
%
% 参数存档（pcd_prefs.mat）、默认数据目录（data/）、仪器配置（rigol_config.ini）
% 都放在该目录下，避免编译后写入只读的 MCR 临时目录导致丢失。
persistent cached
if ~isempty(cached)
    root = cached;
    return;
end

envHome = strtrim(getenv('PCD_HOME'));
if isempty(envHome)
    envHome = strtrim(getenv('PFC_HOME'));
end
if ~isempty(envHome)
    root = envHome;
elseif isdeployed
    if ispc && ~isempty(getenv('LOCALAPPDATA'))
        root = migrated_dir(fullfile(getenv('LOCALAPPDATA'), 'PCD'), ...
            fullfile(getenv('LOCALAPPDATA'), 'PFC'));
    elseif ~isempty(getenv('HOME'))
        root = migrated_dir(fullfile(getenv('HOME'), '.pcd'), ...
            fullfile(getenv('HOME'), '.pfc'));
    else
        root = migrated_dir(fullfile(tempdir, 'PCD'), fullfile(tempdir, 'PFC'));
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

function d = migrated_dir(newDir, oldDir)
% 对外目录改叫 PCD 后，如果机器上还只有旧的 PFC 数据，先沿用，避免参数/存档丢了。
if isfolder(oldDir) && ~isfolder(newDir)
    d = oldDir;
else
    d = newDir;
end
end
