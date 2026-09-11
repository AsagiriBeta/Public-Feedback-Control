function info = pfc_release(varargin)
%PFC_RELEASE 一条命令发版：打包 → 上传 GitHub Release → 推送更新清单。
%
%   pfc_release                        打包 exe、建 v<版本> 的 Release 并上传安装包，
%                                      然后提交并推送 update.json
%   pfc_release('notes', '更新说明…')   指定这一版的更新说明（写进 update.json 与 Release）
%   pfc_release('dryrun')              只打包并报告，不建 Release、不动 git
%   pfc_release('force')               v<版本> 的 tag 已存在时也继续（改走 --clobber 覆盖上传）
%
% 发版前唯一要手工做的事：改 pfc_version.m 里的版本号。它同时用作提交说明、Release 的
% tag 和清单里的 version，不会出现「包是新的、清单还是旧的」。
%
% 前置条件（各一次）：
%   1) 安装并登录 GitHub CLI：gh auth login
%   2) git 能访问 GitHub；走代理时先 git config --global http.proxy http://127.0.0.1:7890
%
% 为什么安装包走 Release 附件而不是提交进仓库：安装包约 3 MB，提交进仓库会永久留在
% git 历史里、每次 clone 都得拉。Release 附件由 gh 自动上传，仓库只多一个几行的清单。
% 目标机读的是 releases/latest/download/<文件名> 这个稳定地址 —— 它永远指向最新
% Release 的同名附件，所以发新版时清单里只有 version 和 notes 需要改。
root = fileparts(mfilename('fullpath'));
if isempty(root)
    root = pwd;
end
old = cd(root);
restoreDir = onCleanup(@() cd(old)); %#ok<NASGU>

[dryRun, force, notes] = parse_args(varargin);
ver = pfc_version();

% git 必须可用：否则 remote_slug 会返回空，清单里的 url 就被静默写成相对文件名，
% 而不是 Release 地址 —— 那种错误在目标机上才暴露，很难查。宁可这里直接报错。
[gitOk, gitVer] = run_cmd('git --version');
if ~gitOk
    error('PFC:release:noGit', ...
        ['没找到 git。pfc_release 需要 git 与 gh 都在 PATH 上。\n' ...
         '刚装完 git 的话，重开一次终端 / MATLAB 让新 PATH 生效。']);
end
fprintf('使用 %s\n', strtrim(gitVer));

installerName = 'PFC_Installer.exe';
installer = fullfile(root, 'build', installerName);
manifest = fullfile(root, 'update.json');

% ---- 前置：仓库来源与 gh 登录（dryrun 跳过，便于离线只验证打包）----
gh = '';
slug = remote_slug(root);
if ~dryRun
    gh = gh_exe();
    [ok, out] = run_cmd(sprintf('"%s" auth status', gh));
    if ~ok
        error('PFC:release:ghAuth', ...
            'GitHub CLI 还没登录，先在终端执行：\n  gh auth login\n\n%s', out);
    end
    if isempty(slug)
        error('PFC:release:remote', ...
            ['没能从 origin 识别出 GitHub 仓库。\n' ...
             '请确认 git remote -v 里是 https://github.com/<用户>/<仓库>.git']);
    end
    fprintf('仓库：%s\n', slug);
end

% ---- 版本号守卫：同一版本发两次，目标机不会认为有更新 ----
run_git(root, 'fetch --tags --quiet');   % 尽力而为，失败不影响继续
[tagExists, ~] = run_git(root, sprintf('rev-parse -q --verify refs/tags/v%s', ver));
if tagExists && ~force && ~dryRun
    fprintf(['tag v%s 已经存在 —— 这一版发过了。\n' ...
        '要继续发同版本请加 ''force''（覆盖上传安装包），或先改 pfc_version.m。\n'], ver);
    info = struct('ok', false, 'version', ver, 'released', false, 'reason', 'tag-exists');
    return;
end

% ---- 打包前先读一次旧清单：打包会重写它，notes 的沿用要以这里读到的为准 ----
prev = read_manifest(manifest);

% ---- 打包 ----
fprintf('=== 发版 %s ===\n', ver);
pfc_build_exe();
if ~isfile(installer)
    error('PFC:release:noInstaller', '没找到安装包：%s', installer);
end

% ---- 刷新清单：url 固定指向 Release 的稳定地址；notes 按参数 / 沿用 / 兜底 ----
if isempty(notes)
    notes = prev.notes;
end
if isempty(notes) || contains(notes, '发版时补更新说明')
    notes = sprintf('发布 %s', ver);
    fprintf('提示：这一版还没有更新说明，Release 里会写「%s」。\n', notes);
    fprintf('      下次可以用 pfc_release(''notes'', ''…'') 指定。\n');
end
url = sprintf('https://github.com/%s/releases/latest/download/%s', slug, installerName);
if isempty(slug)
    url = prev.url;
    if isempty(url)
        url = installerName;
    end
end
write_manifest(manifest, ver, url, notes);
fprintf('清单：%s\n  version=%s\n  url=%s\n  notes=%s\n', manifest, ver, url, notes);

if dryRun
    fprintf('\n[dryrun] 已打包，未建 Release、未动 git。\n');
    info = struct('ok', true, 'version', ver, 'released', false, 'reason', 'dryrun');
    return;
end

% ---- 先推清单再建 Release：tag 才会指向含本次版本号的提交 ----
files = {'pfc_version.m', 'update.json'};
[~, porcelain] = run_git(root, 'status --porcelain');
stray = stray_changes(porcelain, files);
if ~isempty(stray)
    fprintf(['\n注意：以下改动不在本次提交范围内，推送后仓库源码会和 exe 不一致：\n%s' ...
        '建议先把它们提交掉。\n\n'], stray);
end
commit_and_push(root, ver, files);

% ---- 建 Release 并上传安装包 ----
notesFile = fullfile(tempdir, 'pfc_release_notes.md');
fid = fopen(notesFile, 'w', 'n', 'UTF-8');
fprintf(fid, '%s\n', notes);
fclose(fid);

tag = ['v' ver];
[exists, ~] = run_cmd(sprintf('"%s" release view %s --repo %s', gh, tag, slug));
if exists && force
    fprintf('Release %s 已存在（force）：覆盖上传安装包…\n', tag);
    [ok, out] = run_cmd(sprintf('"%s" release upload %s "%s" --repo %s --clobber', ...
        gh, tag, installer, slug));
elseif exists
    error('PFC:release:exists', 'Release %s 已存在。要覆盖请加 ''force''。', tag);
else
    fprintf('创建 Release %s 并上传安装包…\n', tag);
    [ok, out] = run_cmd(sprintf( ...
        '"%s" release create %s "%s" --repo %s --title "%s" --notes-file "%s"', ...
        gh, tag, installer, slug, tag, notesFile));
end
if ~ok
    error('PFC:release:gh', ...
        ['gh 创建/上传 Release 失败：\n%s\n' ...
         '清单已经推上去了但安装包还没到位；修好问题后重跑 pfc_release(''force'') 即可。'], out);
end
fprintf('%s\n', out);

src = sprintf('https://raw.githubusercontent.com/%s/%s/update.json', ...
    slug, default_branch(root));
fprintf(['\n完成 %s。\n目标机的更新源填：\n  %s\n' ...
    '（GitHub raw 有约 5 分钟 CDN 缓存，刚发完可能短暂读到旧清单）\n'], ver, src);
info = struct('ok', true, 'version', ver, 'released', true, 'reason', 'ok', ...
    'source', src, 'asset', installer);
end

% ---------------------------------------------------------------- 步骤

function commit_and_push(root, ver, files)
run_git(root, sprintf('add -- %s', strjoin(files, ' ')));
[~, staged] = run_git(root, sprintf('status --porcelain -- %s', strjoin(files, ' ')));
if isempty(staged)
    fprintf('清单与版本号没有变化，跳过提交。\n');
    return;
end
[ok, out] = run_git(root, sprintf('commit -m "chore(release): v%s"', ver));
if ~ok
    error('PFC:release:commit', '提交失败：\n%s', out);
end
fprintf('%s\n', out);

[~, branch] = run_git(root, 'rev-parse --abbrev-ref HEAD');
branch = strtrim(branch);
[ok, out] = run_git(root, 'push');
if ~ok
    % 全新仓库第一次推送时分支还没有上游，直接 push 会失败，这里补一次 -u
    fprintf('直接推送未成功，尝试为分支 %s 建立上游跟踪后重推…\n', branch);
    [ok2, out2] = run_git(root, sprintf('push -u origin %s', branch));
    if ok2
        ok = true;
        out = out2;
    else
        out = sprintf('%s\n%s', out, out2);
    end
end
if ~ok
    error('PFC:release:push', ...
        ['推送失败：\n%s\n' ...
         '若是网络问题，先设置代理：git config --global http.proxy http://127.0.0.1:7890'], out);
end
fprintf('%s\n', out);
end

function [dryRun, force, notes] = parse_args(args)
dryRun = false;
force = false;
notes = '';
k = 1;
while k <= numel(args)
    a = args{k};
    if ischar(a) || isstring(a)
        switch lower(char(a))
            case 'dryrun'
                dryRun = true;
            case 'force'
                force = true;
            case 'notes'
                if k + 1 <= numel(args)
                    notes = char(string(args{k + 1}));
                    k = k + 1;
                end
        end
    end
    k = k + 1;
end
end

function m = read_manifest(f)
m = struct('version', '', 'url', '', 'notes', '');
if ~isfile(f)
    return;
end
try
    d = pfc_update('manifest', f);   % 含 BOM 容错
    for fn = fieldnames(m)'
        if isfield(d, fn{1}) && ~isempty(d.(fn{1}))
            m.(fn{1}) = strtrim(char(string(d.(fn{1}))));
        end
    end
catch
end
end

function write_manifest(f, ver, url, notes)
m = struct('version', ver, 'url', url, 'notes', notes);
fid = fopen(f, 'w');
if fid < 0
    error('PFC:release:manifest', '无法写入清单：%s', f);
end
fwrite(fid, jsonencode(m));
fclose(fid);
end

function slug = remote_slug(root)
slug = '';
[ok, url] = run_git(root, 'remote get-url origin');
if ~ok
    return;
end
m = regexp(strtrim(url), 'github\.com[:/]+([^/]+)/(.+?)(\.git)?$', 'tokens', 'once');
if ~isempty(m)
    slug = sprintf('%s/%s', m{1}, m{2});
end
end

function br = default_branch(root)
br = 'main';
[ok, out] = run_git(root, 'symbolic-ref --quiet --short refs/remotes/origin/HEAD');
if ok && ~isempty(out)
    p = strsplit(strtrim(out), '/');
    br = p{end};
end
end

function exe = gh_exe()
exe = 'gh';
cands = { ...
    fullfile(char(getenv('ProgramFiles')), 'GitHub CLI', 'gh.exe'), ...
    fullfile(char(getenv('ProgramFiles(x86)')), 'GitHub CLI', 'gh.exe'), ...
    fullfile(char(getenv('LOCALAPPDATA')), 'Programs', 'GitHub CLI', 'gh.exe')};
for i = 1:numel(cands)
    if ~isempty(cands{i}) && isfile(cands{i})
        exe = cands{i};
        return;
    end
end
end

% ---------------------------------------------------------------- 底层

function [ok, out] = run_git(root, args)
[ok, out] = run_cmd(sprintf('git -C "%s" %s', root, args));
end

function [ok, out] = run_cmd(cmd)
[st, out] = system([cmd ' 2>&1']);
ok = (st == 0);
out = strtrim(out);
end

function s = stray_changes(porcelain, files)
% 挑出不在 files 里的改动，拼成一段缩进清单（文件多时只显示前 8 条）
lines = splitlines(strtrim(porcelain));
keep = {};
for i = 1:numel(lines)
    ln = strtrim(lines{i});
    if isempty(ln)
        continue;
    end
    parts = strsplit(ln, ' ', 'CollapseDelimiters', true);
    if numel(parts) < 2
        continue;
    end
    p = strrep(strjoin(parts(2:end), ' '), '/', filesep);
    if ~any(strcmpi(p, strrep(files, '/', filesep)))
        keep{end + 1} = ['  ' ln]; %#ok<AGROW>
    end
end
if isempty(keep)
    s = '';
    return;
end
if numel(keep) > 8
    keep = [keep(1:8), sprintf('  …还有 %d 项', numel(keep) - 8)];
end
s = [strjoin(keep, newline), newline];
end
