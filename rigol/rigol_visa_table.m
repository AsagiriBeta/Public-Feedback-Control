function [names, meta] = rigol_visa_table(raw)
%RIGOL_VISA_TABLE 把 visadevlist 的返回值解析成统一格式。
%
%   [names, meta] = rigol_visa_table(raw)
%
%   names  1×N cellstr      资源名（去空、去重、保持原有顺序）
%   meta   1×N struct 数组  字段 vendor / model / serial，取不到时为空串
%
% visadevlist 在不同 MATLAB 版本/配置下会返回 table、string、cellstr 或对象数组，
% 界面直接吃原始返回值很容易在换版本时崩掉，所以这里统一收口。
%
% 单独成一个文件是为了能脱离 VISA 硬件做单元测试（构造 table 直接调即可）。
% 输入为空返回空，不报错。
names = {};
meta = blank_meta();
meta(1) = [];          % 0×0 结构体数组，字段保持完整

if isempty(raw)
    return;
end

T = [];
col = {};
if istable(raw)
    T = raw;
    k = col_index(T, 'ResourceName');
    if isempty(k)
        k = find(contains(lower(T.Properties.VariableNames), 'resource'), 1);
    end
    if isempty(k)
        k = 1;
    end
    col = T{:, k};
elseif isstruct(raw)
    if isfield(raw, 'ResourceName')
        col = {raw.ResourceName};
    else
        fn = fieldnames(raw);
        col = {raw.(fn{1})};
    end
elseif iscell(raw)
    col = raw;
elseif isa(raw, 'string')
    col = cellstr(raw);
elseif ischar(raw)
    col = {raw};
else
    % 对象数组（例如 visadev 句柄）：按属性取
    for i = 1:numel(raw)
        try
            col{end + 1} = char(string(raw(i).ResourceName)); %#ok<AGROW>
        catch
        end
    end
end

for i = 1:numel(col)
    s = strtrim(char(string(col{i})));
    if isempty(s) || any(strcmp(names, s))
        continue;
    end
    names{end + 1} = s; %#ok<AGROW>
    m = blank_meta();
    [m.vendor, m.model, m.serial] = row_meta(T, s);
    meta(end + 1) = m; %#ok<AGROW>
end
end

function [vendor, model, serial] = row_meta(T, name)
vendor = '';
model = '';
serial = '';
if isempty(T) || ~istable(T)
    return;
end
k = col_index(T, 'ResourceName');
if isempty(k)
    return;
end
idx = find(strcmpi(string(T{:, k}), string(name)), 1);
if isempty(idx)
    return;
end
vendor = cell_str(T, 'Vendor', idx);
model = cell_str(T, 'Model', idx);
serial = cell_str(T, 'SerialNumber', idx);
if isempty(serial)
    serial = cell_str(T, 'Serial', idx);
end
end

function k = col_index(T, name)
k = find(strcmpi(T.Properties.VariableNames, name), 1);
end

function s = cell_str(T, varName, idx)
s = '';
k = col_index(T, varName);
if isempty(k)
    return;
end
try
    sv = string(T{idx, k});
    if ismissing(sv)
        return;
    end
    s = strtrim(char(sv));
catch
end
end

function m = blank_meta()
m = struct('vendor', '', 'model', '', 'serial', '');
end
