function varargout = pfc_update(cmd, varargin)
%PFC_UPDATE 检查更新 / 下载并启动新版本安装包。
%
%   info = pfc_update('check')        读更新清单，跟当前版本比
%          pfc_update('apply', info)  下载更新包并启动安装程序（装完即新版本）
%   s    = pfc_update('source')       当前生效的更新源
%   f    = pfc_update('file')         更新源配置文件路径（仅供运维覆盖）
%
% ── 更新源 ──────────────────────────────────────────────────────────
% 对用户完全透明：源写死在 default_source() 里，点「检查更新」直接用，
% 界面上没有也不需要任何配置入口：
%     https://raw.githubusercontent.com/jiaxuanli2504-cell/Public-Feedback-Control/main/update.json
%
% 只有运维需要换源时（内网服务器、局域网共享、隔离网无法回源）才用得上
% <工作根>/pfc_update.ini 覆盖，界面上不暴露、出错时也不提示它：
%     source=https://example.com/pfc/update.json    任意 HTTPS（Gitee、内网服务器同理）
%     source=\\server\share\pfc\update.json         局域网共享，目标机不必上网
%     source=none                                   关闭更新检查
%
% 发布端怎么摆：update.json 放仓库根目录（就几行文本）；安装包作为 GitHub Release
% 附件上传（不提交进仓库，免得每发一版给 git 历史永久加约 3 MB）。文件名与清单 url
% 都由 pfc_installer_asset 按版本生成，直接调 pfc_release 发版即可：
%     https://github.com/<用户>/<仓库>/releases/download/v0.2.0/PFC_Installer_v0.2.0.exe
%
% 注意：私有仓库的 raw 链接需要 access token，本模块不带鉴权，所以更新源得是公开仓库。
%
% 清单格式（url 可写相对清单的路径，或任意完整地址）：
%   {
%     "version": "0.2.0",
%     "url":     "https://github.com/me/pfc/releases/download/v0.2.0/PFC_Installer_v0.2.0.exe",
%     "notes":   "修复 XXX；新增仪器自动扫描"
%   }
%
% 更新源配置在 <工作根>/pfc_update.ini，跟 rigol_config.ini 一样是纯文本、不入库；
% 没有该文件就用 default_source() 里的默认源。发版流程见 README「软件更新」与 pfc_release。
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

function s = default_source()
%DEFAULT_SOURCE 出厂默认更新源 —— 本项目在 GitHub 上的发布仓库。
% 换仓库、换镜像只改这一处。想改用内网服务器 / 局域网共享，就在
% <工作根>/pfc_update.ini 里写 source=… 覆盖（和 rigol_config.ini 一个套路）。
s = 'https://raw.githubusercontent.com/jiaxuanli2504-cell/Public-Feedback-Control/main/update.json';
end

function s = read_source()
%READ_SOURCE 本地覆盖优先；没有配置文件就用默认源。
% 这样目标机装上就能直接「检查更新」，不必先手工配一遍 —— 默认源写在
% default_source() 里，跟 rigol_config「默认值 + 本地覆盖」保持一致。
% 只认白名单键 source；写成空值或 none/off 可显式关闭更新检查。
s = default_source();
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
        v = strtrim(strjoin(p(2:end), '='));
        if is_source_disabled(v)
            s = '';
        elseif ~isempty(v)
            s = v;
        end
    end
end
end

function tf = is_source_disabled(v)
tf = isempty(v) || any(strcmpi(v, {'none', 'off', 'disabled', '-'}));
end

% ---------------------------------------------------------------- 检查更新

function info = do_check()
info = struct('ok', false, 'available', false, ...
    'current', pfc_version(), 'latest', '', 'url', '', 'notes', '', ...
    'error', '', 'source', '');

% MATLAB 源码：本机仓库就是正在跑的版本，不连 GitHub、不弹超时。
if ~isdeployed
    info.ok = true;
    info.available = false;
    info.latest = info.current;
    info.source = 'local';
    info.notes = 'MATLAB 源码，本机即当前版本。';
    return;
end

src = read_source();
info.source = src;
if isempty(src)
    info.error = '更新检查已关闭。';
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
% 源码直接跑 MATLAB：读仓库里的 update.json，不访问外网。
% 实验室点「检查更新」卡 15 秒，是 raw.githubusercontent.com 被墙/超时，不是程序坏了。
if ~isdeployed
    local = fullfile(pfc_root(), 'update.json');
    if isfile(local)
        m = parse_manifest(fileread(local), local);
        return;
    end
end
if is_url(src)
    txt = http_get_text(src);
else
    if ~isfile(src)
        error('pfc:update:fetch', '找不到更新清单：%s', src);
    end
    txt = fileread(src);
end
m = parse_manifest(txt, src);
end

function txt = http_get_text(src)
% 国内经常访问不了 raw.githubusercontent.com；按镜像依次试，单次 8 秒。
urls = mirror_urls(src);
last = '';
for i = 1:numel(urls)
    try
        txt = webread(with_cache_buster(urls{i}), ...
            weboptions('ContentType', 'text', 'Timeout', 8));
        return;
    catch err
        last = char(string(err.message));
    end
end
error('pfc:update:fetch', '%s\n来源：%s', http_error_hint(last), src);
end

function urls = mirror_urls(src)
src = char(string(src));
urls = {src};
tok = regexp(src, 'github(?:usercontent)?\.com/([^/]+)/([^/]+)/(?:raw/)?(?:refs/heads/)?([^/]+)/(.+)$', 'tokens', 'once');
if isempty(tok)
    return;
end
user = tok{1};
repo = tok{2};
br = tok{3};
path = tok{4};
alts = {
    sprintf('https://github.com/%s/%s/raw/%s/%s', user, repo, br, path)
    sprintf('https://cdn.jsdelivr.net/gh/%s/%s@%s/%s', user, repo, br, path)
    sprintf('https://raw.githubusercontent.com/%s/%s/%s/%s', user, repo, br, path)
    };
urls = {};
seen = {};
for i = 1:numel(alts)
    u = alts{i};
    if ~any(strcmp(seen, u))
        seen{end+1} = u; %#ok<AGROW>
        urls{end+1} = u; %#ok<AGROW>
    end
end
if ~any(strcmp(seen, src))
    urls{end+1} = src; %#ok<AGROW>
end
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
%WITH_CACHE_BUSTER 给地址加一个一次性参数。
% 实测结论（别被名字误导）：raw.githubusercontent.com 的 CDN **忽略查询参数**，而且它有多台
% 边缘节点、各自缓存约 5 分钟，所以这个参数并不保证拿到最新清单 —— 发版后仍可能短暂读到旧内容。
% 保留它只是为了规避某些中间代理/本地缓存按完整 URL 缓存的情况。真正可靠的办法是等几分钟。
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
%HTTP_ERROR_HINT 把底层报错翻译成人话。
msg = regexprep(msg, '[?&]_pfc=[\d.]+', '');
if contains(msg, '404')
    s = sprintf(['更新服务器上找不到更新清单，请稍后重试。\n' ...
        '（若持续出现，请联系维护人员。）']);
else
    s = sprintf(['无法连接 GitHub 更新源（国内访问 raw.githubusercontent.com 经常超时）。\n' ...
        '用 MATLAB 源码做实验不必点「检查更新」，关对话框继续即可；代码以本机仓库为准。\n' ...
        '（技术细节：%s）'], msg);
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
% 延迟 5 秒再启动：给本程序留出退出的时间（调用方下完包就会自己关窗）。
% 正在运行的 exe 不能被覆盖 —— 安装器起得太早会替换不掉主程序，装完还是旧版。
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
    fprintf(fid, 'timeout /t 5 /nobreak >nul\r\n');
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
