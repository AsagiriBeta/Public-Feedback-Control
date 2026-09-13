function varargout = pfc_version(cmd, varargin)
%PFC_VERSION 程序版本号的**唯一出处**。
%
%   v = pfc_version()            当前版本字符串，如 '0.1.0'
%   pfc_version('label')         带 v 前缀，如 'v0.1.0'（界面标题用）
%   tf = pfc_version('gt', a, b) a 比 b 新返回 true
%   tf = pfc_version('eq', a, b) 版本相同返回 true
%
% 发新版本时**只改下面这一行**：界面标题、更新检查的比较基准都从这里取，
% 服务端 update.json 里的 version 也要对应同一个号。
%
% 比较规则：只取每段开头的数字，'v' 前缀忽略，缺的段按 0 补。
% 所以 '1.2' 与 '1.2.0' 相同，'1.0.0-rc1' 按 '1.0.0' 处理。
v = '0.1.4';

if nargin < 1 || isempty(cmd)
    varargout{1} = v;
    return;
end

switch lower(char(cmd))
    case 'label'
        varargout{1} = ['v' v];
    case 'gt'
        varargout{1} = vcmp(varargin{1}, varargin{2}) > 0;
    case 'eq'
        varargout{1} = vcmp(varargin{1}, varargin{2}) == 0;
    otherwise
        error('pfc:version:cmd', '未知命令 %s', cmd);
end
end

function c = vcmp(a, b)
pa = parts(a);
pb = parts(b);
n = max(numel(pa), numel(pb));
pa(end+1:n) = 0;
pb(end+1:n) = 0;
c = 0;
for k = 1:n
    if pa(k) > pb(k)
        c = 1;
        return;
    elseif pa(k) < pb(k)
        c = -1;
        return;
    end
end
end

function p = parts(s)
s = strtrim(char(string(s)));
s = regexprep(s, '^[vV]', '');
toks = strsplit(s, '.');
p = zeros(1, numel(toks));
for k = 1:numel(toks)
    m = regexp(toks{k}, '^\d+', 'match', 'once');
    if ~isempty(m)
        p(k) = str2double(m);
    end
end
end
