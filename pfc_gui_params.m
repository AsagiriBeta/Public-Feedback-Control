function varargout = pfc_gui_params(cmd, handles)
%PFC_GUI_PARAMS 界面可调参数的持久化：存盘后下次启动自动恢复，不用重新调参。
%
%   s = pfc_gui_params('load')        读取存档（无存档则返回空字段结构）
%       pfc_gui_params('save', handles)  合并写盘（只写入有效值，空/非法值不覆盖旧值）
%       pfc_gui_params('apply', handles) 把存档写回界面控件
%       pfc_gui_params('reset')          删除存档（下次启动回到默认值）
%
% 存档位置：<项目根>/pfc_gui_params.mat（.gitignore 已忽略 *.mat，不入库）
if nargin < 2
    handles = [];
end

switch lower(cmd)
    case 'load'
        varargout{1} = prefs_load();
    case 'save'
        prefs_save(handles);
    case 'apply'
        prefs_apply(handles);
    case 'reset'
        f = prefs_file();
        if isfile(f)
            delete(f);
        end
    otherwise
        error('pfc_gui_params:cmd', '未知命令 %s', cmd);
end
end

function f = prefs_file()
% 放在可写工作根下：源码模式=项目根，打包模式=用户目录，避免写进只读的 MCR 临时目录
f = fullfile(pfc_root(), 'pfc_gui_params.mat');
end

function S = default_S()
% 所有可持久化字段（数值字段默认 []，文本字段默认 ''）
S = struct( ...
    'freq_mhz', [], 'volt_mVpp', [], 'prf_hz', [], 'n_cycle', [], ...
    'duration_s', [], 'npts', [], 'target_db', [], 'max_mVpp', [], ...
    'mb_load_s', [], 'studyID', '', 'directory', '', 'dbg_freq', [], 'dbg_volt', []);
end

function map = tag_map()
% {界面控件 Tag, 存档字段, 'num'|'str'}
map = { ...
    'frequency',        'freq_mhz',   'num'; ...
    'voltage',          'volt_mVpp',  'num'; ...
    'PRF',              'prf_hz',     'num'; ...
    'BurstCount',       'n_cycle',    'num'; ...
    'duration',         'duration_s', 'num'; ...
    'sampleNum',        'npts',       'num'; ...
    'ControllerTarget', 'target_db',  'num'; ...
    'MaxV',             'max_mVpp',   'num'; ...
    'MBLoadTime',       'mb_load_s',  'num'; ...
    'studyID',          'studyID',    'str'; ...
    'directory',        'directory',  'str'; ...
    'debug_freq',       'dbg_freq',   'num'; ...
    'debug_volt',       'dbg_volt',   'num'};
end

function S = prefs_load()
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

function prefs_save(handles)
if isempty(handles)
    return;
end
S = prefs_load();   % 以旧存档为底，只覆盖本次读到的有效值
map = tag_map();
for i = 1:size(map, 1)
    tag = map{i, 1};
    fld = map{i, 2};
    kind = map{i, 3};
    if ~isfield(handles, tag) || ~isgraphics(handles.(tag))
        continue;
    end
    s = strtrim(char(get(handles.(tag), 'String')));
    if strcmp(kind, 'num')
        v = str2double(s);
        if ~isempty(v) && isfinite(v) && v > 0
            S.(fld) = v;
        end
    elseif ~isempty(s)
        S.(fld) = s;
    end
end
try
    save(prefs_file(), '-struct', 'S');
catch
end
end

function prefs_apply(handles)
if isempty(handles)
    return;
end
S = prefs_load();
map = tag_map();
for i = 1:size(map, 1)
    tag = map{i, 1};
    fld = map{i, 2};
    kind = map{i, 3};
    if ~isfield(handles, tag) || ~isgraphics(handles.(tag))
        continue;
    end
    v = S.(fld);
    if strcmp(kind, 'num')
        if ~isempty(v) && isfinite(v) && v > 0
            set(handles.(tag), 'String', fmt_num(v));
        end
    elseif ischar(v) && ~isempty(v)
        set(handles.(tag), 'String', v);
    end
end
end

function s = fmt_num(v)
if abs(v - round(v)) < 1e-9 && abs(v) < 1e9
    s = sprintf('%d', round(v));
else
    s = sprintf('%.10g', v);
end
end
