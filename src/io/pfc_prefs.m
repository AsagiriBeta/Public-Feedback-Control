function varargout = pfc_prefs(cmd, arg)
%PFC_PREFS 界面可调参数的持久化：存盘后下次启动自动恢复，不用每次重新调参。
%
%   S = pfc_prefs()              读取生效值（出厂默认 + 存档）
%   S = pfc_prefs('defaults')    只要出厂默认值（前端首次渲染用）
%       pfc_prefs('save', S)     合并写盘：空 / 非法字段不会覆盖旧值
%       pfc_prefs('reset')       删除存档，下次启动回到出厂默认
%
% 字段名清单见 default_S()，与前端 web/app.js 里的键名一一对应；
% 增删一个可调参数，只需同时改 default_S() 与 prefs_defaults()。
%
% 存档位置 <可写工作根>/pfc_prefs.mat —— 工作根由 pfc_root() 决定
% （源码模式=项目根，打包后=用户可写目录），.gitignore 已忽略 *.mat，不入库。
if nargin < 1 || isempty(cmd)
    varargout{1} = prefs_effective();
    return;
end
if nargin < 2
    arg = [];
end

switch lower(char(cmd))
    case 'get'
        varargout{1} = prefs_effective();
    case 'defaults'
        varargout{1} = prefs_defaults();
    case 'save'
        write_merged(arg);
    case 'reset'
        f = prefs_file();
        if isfile(f)
            delete(f);
        end
    otherwise
        error('PFC:prefs:cmd', '未知命令 %s', cmd);
end
end

% ---------------------------------------------------------------- 存档路径

function f = prefs_file()
f = fullfile(pfc_root(), 'pfc_prefs.mat');
end

% ---------------------------------------------------------------- 字段定义

function S = default_S()
% 所有可持久化字段（数值字段默认 []，文本字段默认 ''）——同时充当字段名清单
S = struct( ...
    'freq_mhz', [], 'volt_mVpp', [], 'prf_hz', [], 'n_cycle', [], ...
    'duration_s', [], 'npts', [], 'target_db', [], 'max_mVpp', [], ...
    'mb_load_s', [], 'studyID', '', 'directory', '', 'dbg_freq', [], 'dbg_volt', []);
end

function S = prefs_defaults()
% 出厂默认值（前端首次渲染 / 存档缺失时用）
S = struct( ...
    'freq_mhz', 1.5, 'volt_mVpp', 50, 'prf_hz', 2, 'n_cycle', 400, ...
    'duration_s', 120, 'npts', 40000, 'target_db', 2, 'max_mVpp', 120, ...
    'mb_load_s', 15, 'studyID', '', 'directory', '', 'dbg_freq', 1.5, 'dbg_volt', 20);
end

% ---------------------------------------------------------------- 读写

function S = prefs_load()
% 读取原始存档（字段缺失或损坏时退回空字段结构，调用方决定怎么用）
S = default_S();
f = prefs_file();
if ~isfile(f)
    return;
end
try
    D = load(f);
    fn = fieldnames(S);
    for i = 1:numel(fn)
        if isfield(D, fn{i})
            S.(fn{i}) = D.(fn{i});
        end
    end
catch
    S = default_S();
end
end

function S = prefs_effective()
% 默认值 + 存档：只让存档里的有效值覆盖默认值
S = prefs_defaults();
L = prefs_load();
fn = fieldnames(S);
for i = 1:numel(fn)
    v = L.(fn{i});
    if isnumeric(v)
        if ~isempty(v) && isscalar(v) && isfinite(v)
            S.(fn{i}) = double(v);
        end
    elseif (ischar(v) || isstring(v)) && ~isempty(v)
        S.(fn{i}) = char(v);
    end
end
end

function write_merged(S)
% 结构体合并落盘：以旧存档为底，只写入本次的有效值，空/非法值不覆盖旧值。
% 前端每敲一下键就会调一次本函数，所以最后多一道「没变化就不写盘」的判断，
% 避免一次输入触发十几次磁盘写。
if ~isstruct(S)
    return;
end
D0 = prefs_load();
D = D0;
fn = fieldnames(D);
for i = 1:numel(fn)
    k = fn{i};
    if ~isfield(S, k)
        continue;
    end
    v = S.(k);
    if isnumeric(v)
        if isscalar(v) && isfinite(v) && v > 0
            D.(k) = double(v);
        end
    elseif ischar(v) || isstring(v)
        s = strtrim(char(v));
        if ~isempty(s)
            D.(k) = s;
        end
    end
end
if isequal(D, D0)
    return;   % 值没变（例如前端重复推同一份），不必写盘
end
try
    save(prefs_file(), '-struct', 'D');
catch
end
end
