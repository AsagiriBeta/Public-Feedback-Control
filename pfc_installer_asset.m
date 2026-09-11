function a = pfc_installer_asset(varargin)
%PFC_INSTALLER_ASSET 安装包的文件名与下载地址 —— 全项目唯一出处。
%
%   a = pfc_installer_asset()         当前版本
%   a = pfc_installer_asset('0.2.0')  指定版本
%   s = pfc_installer_asset('slug')   从 git remote 读出的「用户/仓库」，取不到返回 ''
%
% a 的字段：
%   version  '0.1.2'
%   tag      'v0.1.2'
%   base     'PFC_Installer_v0.1.2'        给 compiler.package.installer 的 InstallerName
%   name     'PFC_Installer_v0.1.2.exe'    最终文件名
%   url      Release 下载地址（见下）
%
% 为什么文件名带版本号：下载目录/共享盘里堆着好几个包时，能一眼看出是哪一个，
% 不用点开属性看时间。程序内部的程序名不带版本号 —— 否则每版在 Windows 眼里都是
% 另一个产品，覆盖安装会失效、「应用和功能」里还会堆一串旧条目。
%
% 为什么 url 用「指定版本」的 Release 地址而不是 releases/latest：
% 文件名带了版本号，latest 那条路会指向不存在的旧文件名（latest/download 要求
% 各版本的附件同名）。用 releases/download/v<版本>/<同名文件> 才是永久有效的。
%
% 取不到 git remote（比如没装 git）时 url 退化成相对文件名，按清单所在目录解析；
% 正常发版流程里 pfc_release 会补成完整地址。
if nargin >= 1 && (ischar(varargin{1}) || isstring(varargin{1})) ...
        && strcmpi(char(varargin{1}), 'slug')
    a = repo_slug();
    return;
end

ver = pfc_version();
if nargin >= 1 && ~isempty(varargin{1})
    ver = char(string(varargin{1}));
end

a = struct('version', ver, 'tag', ['v' ver], 'base', '', 'name', '', 'url', '');
a.base = sprintf('PFC_Installer_v%s', ver);
a.name = [a.base '.exe'];
slug = repo_slug();
if isempty(slug)
    a.url = a.name;   % 退化：按清单所在目录解析
else
    a.url = sprintf('https://github.com/%s/releases/download/%s/%s', ...
        slug, a.tag, a.name);
end
end

function slug = repo_slug()
% 只认 github.com 的 origin；取不到返回空串（离线、非 GitHub 仓库等）。
slug = '';
root = fileparts(mfilename('fullpath'));
% 注意 system 的第一个返回值是 exit status（0 = 成功），不是布尔 ok。
[st, out] = system(sprintf('%s -C "%s" remote get-url origin 2>&1', git_cmd(), root));
if st ~= 0
    return;
end
m = regexp(strtrim(out), 'github\.com[:/]+([^/]+)/(.+?)(\.git)?$', 'tokens', 'once');
if ~isempty(m)
    slug = sprintf('%s/%s', m{1}, m{2});
end
end

function g = git_cmd()
% MATLAB 的 PATH 里常常没有 git（尤其从 IDE / 快捷方式启动时），兜一下常见安装位置。
% 否则会读不到 remote，清单里的 url 就退化成相对文件名 —— 那种错要到目标机上才暴露。
g = 'git';
cands = { ...
    fullfile(char(getenv('ProgramFiles')), 'Git', 'cmd', 'git.exe'), ...
    fullfile(char(getenv('ProgramFiles(x86)')), 'Git', 'cmd', 'git.exe'), ...
    fullfile(char(getenv('LOCALAPPDATA')), 'Programs', 'Git', 'cmd', 'git.exe')};
for i = 1:numel(cands)
    if ~isempty(cands{i}) && isfile(cands{i})
        g = ['"' cands{i} '"'];
        return;
    end
end
end
