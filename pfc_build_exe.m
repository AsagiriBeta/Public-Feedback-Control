function pfc_build_exe(varargin)
%PFC_BUILD_EXE 生成 Windows 独立程序（exe + 可选安装包）。
%
% 只在 Windows + MATLAB Compiler 环境下可用：MATLAB Compiler 不支持交叉编译，
% 因此 Windows 的 exe 必须在 Windows 上编译（macOS 上运行本脚本会直接报错）。
%
%   pfc_build_exe                 编译 exe，并打包含 MATLAB Runtime 的安装程序
%   pfc_build_exe('noinstaller')  只编译 exe
%
% 产物在 <项目根>/build/ 下。目标机运行前需安装：
%   1) MATLAB Runtime（版本与编译用的 MATLAB 一致）
%   2) NI-VISA（或仪器厂商 VISA）——visadev 依赖它，且不在 Runtime 内
%
% 换仪器不必重新编译：运行后在界面点「仪器设置」填 VISA 地址即可。
noInstaller = any(strcmpi(varargin, 'noinstaller'));

root = fileparts(mfilename('fullpath'));
if isempty(root)
    root = pwd;
end
old = cd(root);
restoreDir = onCleanup(@() cd(old)); %#ok<NASGU>

if ~ispc
    error('PFC:build', ...
        ['MATLAB Compiler 不支持交叉编译：Windows 的 exe 必须在 Windows 上编译。\n' ...
         '请把本仓库拷到装了 MATLAB + MATLAB Compiler 的 Windows 机器上再运行 pfc_build_exe。']);
end
if isempty(which('compiler.build.standaloneApplication'))
    error('PFC:build', '未找到 MATLAB Compiler（需单独授权并安装），无法打包。');
end

outDir = fullfile(root, 'build');

fprintf('[1/2] 编译入口 pfc_app.m ...\n');
res = compiler.build.standaloneApplication('pfc_app.m', ...
    'AdditionalFiles', {'MatlabScript_FeedbackControl.fig'}, ...
    'OutputDir', outDir);
fprintf('      exe 已输出到：%s\n', outDir);

if noInstaller
    fprintf('已跳过安装包（noinstaller）。\n');
    return;
end

fprintf('[2/2] 打包安装程序（含 MATLAB Runtime）...\n');
try
    compiler.package.installer(res, ...
        'RuntimeDelivery', 'installer', ...
        'InstallerName', 'PFC_Installer', ...
        'OutputDir', outDir);
    fprintf('      完成：%s\n', outDir);
catch err
    warning('PFC:build:installer', ...
        ['生成安装包失败：%s\n' ...
         '可改用图形界面手动打包：命令窗口输入 applicationCompiler，\n' ...
         '勾选 "Runtime included in package" 后按向导操作。'], err.message);
end
end
