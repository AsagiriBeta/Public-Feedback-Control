function pfc_build_exe(varargin)
%PFC_BUILD_EXE 生成 Windows 独立程序（exe + 可选安装包）。
%
% 只在 Windows + MATLAB Compiler 环境下可用：MATLAB Compiler 不支持交叉编译，
% 因此 Windows 的 exe 必须在 Windows 上编译（macOS 上运行本脚本会直接报错）。
%
%   pfc_build_exe                 编译 exe，并打包含 MATLAB Runtime 的安装程序
%   pfc_build_exe('noinstaller')  只编译 exe
%
% 产物在 <项目根>/build/ 下：pfc_app.exe（程序本体）与
% PFC_Installer_v<版本>.exe（分发包，文件名带版本号以便区分）。目标机运行前需安装：
%   1) MATLAB Runtime（版本与编译用的 MATLAB 一致）
%   2) NI-VISA（或仪器厂商 VISA）——visadev 依赖它，且不在 Runtime 内
%
% 编译机需要（缺一不可）：
%   - MATLAB Compiler        （mcc / compiler.build.*）
%   - MATLAB Compiler SDK    （compiler.package.installer，只打安装包时需要）
%   - Instrument Control Toolbox（visadev，随 exe 一起打进 Runtime 侧依赖）
%
% 换仪器不必重新编译：运行后在界面点「仪器设置」填 VISA 地址即可。
noInstaller = any(strcmpi(varargin, 'noinstaller'));

% tools/ 的上一级就是项目根。这里刻意不用 pfc_root()：本脚本可能在没跑过
% pfc_setup 的会话里被调用，直接按自身位置推算最稳。
root = fileparts(fileparts(mfilename('fullpath')));
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
if isempty(which('compiler.build.standaloneWindowsApplication'))
    error('PFC:build', '未找到 MATLAB Compiler（需单独授权并安装），无法打包。');
end

% mcc 的依赖分析只认「编译时在路径上」的文件。src/ 或 rigol/ 不在路径上时编译不会报错，
% 但生成的 exe 运行时才报 Undefined function。这里与 pfc_app.m 的 pfc_setup 保持一致。
addpath(genpath(root));

if isempty(which('visadev'))
    error('PFC:build', ...
        ['未找到 Instrument Control Toolbox（visadev），本项目靠它跟示波器/信号源通信。\n' ...
         '编译时它用于收录该工具箱的依赖；运行时 exe 还需要目标机装 NI-VISA。']);
end

outDir = fullfile(root, 'build');

% web/ 是静态资源，不在 mcc 的依赖分析范围内，必须显式带上，
% 否则 exe 跑起来会「找不到 index.html」。
if ~isfile(fullfile(root, 'web', 'index.html'))
    error('PFC:build:web', '缺少前端资源：%s', fullfile(root, 'web', 'index.html'));
end

% 必须用 standaloneWindowsApplication，不能用 standaloneApplication：
% 后者生成的是控制台子系统程序，双击会先弹一个黑色 cmd 窗口（界面还没出来），
% 关掉窗口程序也一起没了。前者专门生成「不弹 Windows 命令行」的 GUI 程序，
% 参数完全一致。见 help compiler.build.standaloneWindowsApplication。
fprintf('[1/2] 编译入口 pfc_app.m （版本 %s）...\n', pfc_version('label'));
res = compiler.build.standaloneWindowsApplication('pfc_app.m', ...
    'AdditionalFiles', {'web'}, ...
    'OutputDir', outDir);
fprintf('      exe 已输出到：%s\n', outDir);

if noInstaller
    fprintf('已跳过安装包（noinstaller）。\n');
    return;
end

if isempty(which('compiler.package.installer'))
    warning('PFC:build:sdk', ...
        ['未找到 MATLAB Compiler SDK，无法生成安装包，exe 本身已可用。\n' ...
         '目标机仍需自行安装 MATLAB Runtime 与 NI-VISA。']);
    return;
end

% 先探测本机有没有 MATLAB Runtime 安装包，据此决定 Runtime 怎么交付：
%   installer —— 本机已有安装包，直接内嵌，产出可离线部署的大安装包；
%   web       —— 本机没有，产出的安装向导会在目标机上自动联网下载并安装 Runtime，
%                目标机双击装一次即可用（目标机需能上外网）。
hasLocalRuntime = false;
try
    evalc('mcrInst = mcrinstaller();');   % mcrinstaller 找不到时会自己打印提示，这里吞掉
    hasLocalRuntime = ~isempty(mcrInst);
catch
end
if hasLocalRuntime
    delivery = 'installer';
else
    delivery = 'web';
end

% Version 必须显式传：不给的话，安装包一律自称 1.0（跟真实版本无关），
% 于是每个版本的安装包在 Windows 眼里都是同一个 1.0 —— 覆盖安装时安装器分不清新旧，
% 会出现「装完新的，%ProgramFiles%\pfc_app\application\pfc_app.exe 还是旧的」。
% 传了之后注册表 DisplayVersion 与安装包版本都跟着 pfc_version 走。
% 发布者信息填在这里，会显示在 Windows「应用和功能」里。
publisher = 'AsagiriBeta';
appVer = pfc_version();
asset = pfc_installer_asset(appVer);   % 文件名带版本号，规则见该函数
fprintf('[2/2] 打包安装程序（RuntimeDelivery=%s，版本 %s）...\n', delivery, appVer);
if ~hasLocalRuntime
    fprintf('      本机无 MATLAB Runtime 安装包：目标机安装时自动联网下载 Runtime。\n');
    fprintf('      想改成断网也能装的离线包，先执行 compiler.runtime.download 再重跑本脚本。\n');
end
try
    compiler.package.installer(res, ...
        'RuntimeDelivery', delivery, ...
        'InstallerName', asset.base, ...
        'Version', appVer, ...
        'AuthorName', publisher, ...
        'AuthorCompany', publisher, ...
        'Summary', sprintf('Public Feedback Control %s', pfc_version('label')), ...
        'Description', sprintf(['Public Feedback Control %s ' ...
            '(DHO814 oscilloscope / DG2052 signal generator)'], pfc_version('label')), ...
        'OutputDir', outDir);
    fprintf('      完成：%s\n', fullfile(outDir, asset.name));
catch err
    warning('PFC:build:installer', ...
        ['生成安装包失败：%s\n' ...
         'exe 本身已可用，目标机手动装 MATLAB Runtime 即可；\n' ...
         '也可改用图形界面手动打包：命令窗口输入 applicationCompiler。'], err.message);
end

% 顺手刷新发布清单 update.json（在仓库根目录，目标机「检查更新」读的就是它）。
% version 直接取 pfc_version()，省掉「版本号改了但清单忘改」这个最容易漏的坑；
% url 沿用上一次的值 —— 那是 GitHub Release 的稳定地址，发新版不用改。
% 安装包没生成就不动清单，免得它指向不存在的文件。
write_release_manifest(root, outDir, asset);
end

function write_release_manifest(root, outDir, asset)
%WRITE_RELEASE_MANIFEST 刷新仓库根目录下的 update.json。
% 放在仓库根而不是 build/：它要跟着仓库走（目标机按 raw 链接取），
% 而 build/ 是可再生的临时目录。
% version 与 url 都从 asset 取：安装包文件名带版本号后，url 必须跟着版本走，
% 沿用上一次的地址会指向不存在的老文件名。
if ~isfile(fullfile(outDir, asset.name))
    return;
end
f = fullfile(root, 'update.json');
notes = read_prev_notes(f);
if isempty(notes)
    notes = '（发版时补更新说明）';
end
m = struct('version', asset.version, 'url', asset.url, 'notes', notes);
fid = fopen(f, 'w');
if fid < 0
    warning('PFC:build:manifest', '无法写入发布清单：%s', f);
    return;
end
fwrite(fid, jsonencode(m));
fclose(fid);
fprintf('      发布清单：%s\n', f);
fprintf('        version=%s\n        url=%s\n', m.version, m.url);
end

function n = read_prev_notes(f)
% 复用 pfc_update 的清单解析（含 BOM 容错），避免两处各写一套规则。
% 只沿用 notes（更新说明由你维护，不该被每次 build 冲掉）；
% url 反过来必须每次重算，因为文件名带版本号。
n = '';
if ~isfile(f)
    return;
end
try
    m = pfc_update('manifest', f);
    if isfield(m, 'notes')
        n = strtrim(char(string(m.notes)));
    end
catch
end
end
