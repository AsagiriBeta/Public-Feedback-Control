function varargout = pfc_update(cmd, varargin)
%PFC_UPDATE 检查更新 / 下载并启动新版本安装包。
%
%   info = pfc_update('check')        读更新清单，跟当前版本比
%          pfc_update('apply', info)  下载更新包并启动安装程序（装完即新版本）
%   s    = pfc_update('source')       当前更新源（空串表示未配置）
%          pfc_update('set_source')   弹框让用户填更新源
%          pfc_update('set_source', s) 直接设置
%          pfc_update('clear_source') 清除更新源（关闭更新检查）
%   f    = pfc_update('file')         更新源配置文件路径
%
% ── GitHub 用法（推荐：不用自己搭服务器）────────────────────────────
%   1) 建一个**公开**仓库，把 update.json 放进去；
%   2) 把 PFC_Installer.exe 作为 Release 附件上传（不用提交进仓库，免得仓库越滚越大）；
%   3) 清单里 url 写 release 的稳定地址，这个地址发新版本时**不用改**：
%        https://github.com/<用户>/<仓库>/releases/latest/download/PFC_Installer.exe
%
%   更新源就填这个文件的 raw 地址：
%        https://raw.githubusercontent.com/<用户>/<仓库>/main/update.json
%
%   注意：私有仓库的 raw 链接需要 access token，本模块不带鉴权，所以更新源得是公开仓库。
%
% ── 其它更新源 ──────────────────────────────────────────────────────
%   https://example.com/pfc/update.json    任意 HTTPS（Gitee、内网服务器同理）
%   \\server\share\pfc\update.json         局域网共享，目标机不必上网
%
% 清单格式（url 可写相对清单的路径，或任意完整地址）：
%   {
%     "version": "0.2.0",
%     "url":     "https://github.com/me/pfc/releases/latest/download/PFC_Installer.exe",
%     "notes":   "修复 XXX；新增仪器自动扫描"
%   }
%
% 更新源存在 <工作根>/pfc_update.ini，跟 rigol_config.ini 一样是纯文本、不入库。
% 删掉该文件即关闭更新检查。
%
% 安全性说明：本模块只做「下载 + 启动安装程序」，不做静默覆盖也不会自动执行命令。
% 装不装由用户在弹窗里确认；安装包来源由更新源决定，请把更新源指向自己受控的仓库。
if nargin < 1 || isempty(cmd)
    cmd = 'check';
end

switch lower(char(cmd))
    case 'check'
        varargout{1} = do_check();
    case 'apply'
        varargout{1} = do_apply(varargin{:});
    case 'source'
        varargout{1} = read_source();
    case 'set_source'
        varargout{1} = do_set_source(varargin{:});
    case 'clear_source'
        do_clear_source();
    case 'file'
        varargout{1} = source_file();
    case 'manifest'
        varargout{1} = read_manifest_file(varargin{1});
    otherwise
        error('pfc:update:cmd', '未知命令 %s', cmd);
end
end

% ---------------------------------------------------------------- 更新源配置

function f = source_file()
f = fullfile(pfc_root(), 'pfc_update.ini');
end

function s = read_source()
% 只认白名单键 source，避免配置文件被改坏后影响行为
s = '';
f = source_file();
if ~isfile(f)
    return;
end
try
    lines = splitlines(fileread(f));
catch
    return;
end
for i = 1:numel(lines)
    ln = strtrim(lines{i});
    if isempty(ln) || startsWith(ln, '#') || startsWith(ln, ';')
        continue;
    end
    p = strsplit(ln, '=', 'CollapseDelimiters', false);
    if numel(p) >= 2 && strcmpi(strtrim(p{1}), 'source')
        s = strtrim(strjoin(p(2:end), '='));
    end
end
end

function s = do_set_source(varargin)
s = '';
if nargin >= 1 && ~isempty(varargin{1})
    s = strtrim(char(string(varargin{1})));
else
    d = inputdlg( ...
        {'更新源地址（HTTPS 网址，或局域网共享上的 update.json 路径）'}, ...
        '设置更新源 / Update source', [1 72], {read_source()});
    if isempty(d)
        return;
    end
    s = strtrim(d{1});
end
if isempty(s)
    return;
end
f = source_file();
fid = fopen(f, 'w');
if fid < 0
    error('pfc:update:write', '无法写入更新配置文件：%s', f);
end
fprintf(fid, ['# PFC 更新源（本地覆盖，不入 git）\n' ...
    '# 指向服务端或共享盘上的 update.json；删除本文件即关闭更新检查。\n' ...
    'source=%s\n'], s);
fclose(fid);
end

function do_clear_source()
f = source_file();
if isfile(f)
    delete(f);
end
end

% ---------------------------------------------------------------- 检查更新

function info = do_check()
info = struct('ok', false, 'available', false, ...
    'current', pfc_version(), 'latest', '', 'url', '', 'notes', '', ...
    'error', '', 'source', '');

src = read_source();
info.source = src;
if isempty(src)
    info.error = sprintf(['未配置更新源。\n' ...
        '点「设置更新源」，填入服务器或共享盘上的 update.json 地址。']);
    return;
end

try
    m = fetch_manifest(src);
catch err
    info.error = err.message;
    return;
end

info.latest = strtrim(char(string(getfld(m, 'version', ''))));
info.notes = strtrim(char(string(getfld(m, 'notes', ''))));
info.url = strtrim(char(string(getfld(m, 'url', ''))));

if isempty(info.latest)
    info.error = '更新清单里缺少 version 字段。';
    return;
end
if isempty(info.url)
    info.error = '更新清单里缺少 url 字段。';
    return;
end

info.url = resolve_relative(src, info.url);
info.ok = true;
info.available = pfc_version('gt', info.latest, info.current);
end

function m = fetch_manifest(src)
% 支持两种来源：http(s) 网址 与 本地/局域网共享路径
if is_url(src)
    try
        % 追加一次性参数绕开 CDN 缓存。raw.githubusercontent.com 会缓存约 5 分钟，
        % 刚 push 完 update.json 就点「检查更新」，不加这个很可能拿到旧清单。
        txt = webread(with_cache_buster(src), ...
            weboptions('ContentType', 'text', 'Timeout', 15));
    catch err
        error('pfc:update:fetch', '%s\n来源：%s', ...
            http_error_hint(char(string(err.message))), src);
    end
else
    if ~isfile(src)
        error('pfc:update:fetch', '找不到更新清单：%s', src);
    end
    txt = fileread(src);
end

m = parse_manifest(txt, src);
end

function m = read_manifest_file(f)
% 供别处（如 pfc_build_exe 读上一次的清单）复用，保证只有一套解析规则
if ~isfile(f)
    error('pfc:update:manifest', '找不到更新清单：%s', f);
end
m = parse_manifest(fileread(f), f);
end

function m = parse_manifest(txt, where)
txt = strip_bom(txt);
try
    m = jsondecode(txt);
catch
    error('pfc:update:json', '更新清单不是合法 JSON：%s', where);
end
if ~isstruct(m) || numel(m) ~= 1
    error('pfc:update:json', '更新清单格式不对（应为单个 JSON 对象）：%s', where);
end
end

function s = strip_bom(s)
%STRIP_BOM 剥掉开头的 UTF-8 BOM。
% Windows 上很常见：PowerShell 的 Set-Content -Encoding utf8（PS 5.1）会写入 EF BB BF，
% 部分编辑器也会。而 fileread 不会剥它、jsondecode 见到它直接报「第 1 行第 1 列语法错误」，
% 报错完全看不出真正原因，所以统一在这里处理。
s = char(string(s));
if ~isempty(s) && double(s(1)) == 65279
    s = s(2:end);
end
end

function v = getfld(s, name, def)
v = def;
if isstruct(s) && isfield(s, name)
    v = s.(name);
end
end

function tf = is_url(s)
tf = ~isempty(regexp(char(string(s)), '^\w+://', 'once'));
end

function u = with_cache_buster(url)
%WITH_CACHE_BUSTER 给地址加一个一次性参数，绕开服务器/CDN 的清单缓存。
% 只在取清单时用；解析相对路径用的仍是原始地址，不受影响。
u = char(string(url));
if contains(u, '?')
    sep = '&';
else
    sep = '?';
end
u = sprintf('%s%s_pfc=%.3f', u, sep, posixtime(datetime('now')));
end

function s = http_error_hint(msg)
%HTTP_ERROR_HINT 给 HTTP 报错补上最常见的排查方向（原始报错看不出这些）。
msg = regexprep(msg, '[?&]_pfc=[\d.]+', '');   % 抹掉内部加的缓存参数，别让用户以为自己写错了
s = ['读取更新清单失败：' msg];
if contains(msg, '404')
    s = [s, newline, ...
        '  常见原因：① 更新源指向了私有仓库 —— raw 链接需要 token，本工具不带鉴权，', ...
        newline, ...
        '              请改成公开仓库；② 仓库/分支/文件名拼错，或文件还没 push 上去。'];
end
end

function u = resolve_relative(src, url)
% 清单里的 url 写相对路径时，按清单自身位置解析，方便整个目录一起挪
u = char(string(url));
if is_url(u) || startsWith(u, '\\') || ~isempty(regexp(u, '^[A-Za-z]:', 'once'))
    return;
end
if is_url(src)
    k = find(src == '/', 1, 'last');
    if ~isempty(k)
        u = [src(1:k) u];
    end
else
    u = fullfile(fileparts(src), u);
end
end

% ---------------------------------------------------------------- 下载并安装

function out = do_apply(info)
out = struct('ok', false, 'file', '', 'launched', false, 'error', '');
if ~isstruct(info) || ~isfield(info, 'url') || isempty(info.url)
    out.error = '没有可用的更新包地址。';
    return;
end

dstDir = fullfile(tempdir, 'PFC_update');
if ~isfolder(dstDir)
    mkdir(dstDir);
end
[~, base, ext] = fileparts(info.url);
if isempty(base)
    base = 'PFC_Installer';
end
if isempty(ext)
    ext = '.exe';
end
dst = fullfile(dstDir, [base ext]);

try
    if is_url(info.url)
        websave(dst, info.url, weboptions('Timeout', 300));
    else
        copyfile(info.url, dst, 'f');
    end
catch err
    out.error = sprintf('下载更新包失败：%s', char(string(err.message)));
    return;
end

out.file = dst;
out.ok = true;
out.launched = launch_installer(dst);
if ~out.launched
    out.error = '更新包已下载，但启动安装程序失败，请手动运行它。';
end
end

function tf = launch_installer(path)
% 延迟 2 秒再启动：给本程序留出退出的时间。正在运行的 exe 不能被覆盖，
% 所以调用方应当提示用户先关闭程序（或直接退出），安装器才装得进去。
tf = false;
if ispc
    dirp = fileparts(path);
    if isempty(dirp)
        dirp = tempdir;
    end
    bat = fullfile(dirp, 'pfc_launch_update.cmd');
    fid = fopen(bat, 'w');
    if fid < 0
        return;
    end
    fprintf(fid, '@echo off\r\n');
    fprintf(fid, 'timeout /t 2 /nobreak >nul\r\n');
    fprintf(fid, 'start "" "%s"\r\n', path);
    fclose(fid);
    try
        system(['start "" /min "' bat '"']);
        tf = true;
    catch
    end
else
    try
        system(['"' path '" &']);
        tf = true;
    catch
    end
end
end
