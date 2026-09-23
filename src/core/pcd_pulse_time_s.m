function [t, mode, xlab] = pcd_pulse_time_s(S, n)
%PCD_PULSE_TIME_S  Fig.6 / pulse_sc_ic 横轴：入库墙钟秒，不是 pulse #。
% USB ~1 帧/s，PRF 常 5 Hz，序号不是实验时间。
%
%   [t, mode, xlab] = pcd_pulse_time_s(S, n)
%
% t     n×1 秒（从发生器 OUTPUT ON 起）
% mode  'toc' 有逐帧 toc；'elapsed' 用总墙钟估；'index' 只剩序号
% xlab  xlabel 用的字
%
% 新 run 写 t_pulse_s / TimeRecord。旧 run 没有则用 n_good 与 elapsed。
if nargin < 2 || ~(isfinite(n) && n >= 1)
    n = 1;
end
n = max(1, round(double(n)));
t = nan(n, 1);
mode = 'index';
xlab = 'Pulse #  (no timestamps; USB \neq PRF)';

raw = vec_named(S, {'t_pulse_s', 'TimeRecord'});
if numel(raw) >= 1 && any(isfinite(raw))
    t = fit_n(raw, n);
    mode = 'toc';
    xlab = 'Time (s)';
    return;
end

elapsed = elapsed_of(S);
ng = n;
if isstruct(S) && isfield(S, 'n_good') && isnumeric(S.n_good) && isscalar(S.n_good) ...
        && isfinite(S.n_good) && S.n_good >= 1
    ng = double(S.n_good);
end
if isfinite(elapsed) && elapsed > 0
    % 旧数据：mean_dt = 总墙钟 / 帧数，t = 帧序号 × mean_dt
    dt = elapsed / max(ng, n);
    t = (1:n).' * dt;
    mode = 'elapsed';
    xlab = sprintf('Time (s)  (approx. %.2f s/frame; no per-pulse toc)', dt);
    return;
end

t = (1:n).';
end

function t = fit_n(raw, n)
raw = double(raw(:));
t = nan(n, 1);
m = min(n, numel(raw));
t(1:m) = raw(1:m);
end

function v = vec_named(S, names)
v = [];
if ~isstruct(S)
    return;
end
for i = 1:numel(names)
    k = names{i};
    if isfield(S, k) && ~isempty(S.(k)) && isnumeric(S.(k))
        x = double(S.(k)(:));
        if any(isfinite(x))
            v = x;
            return;
        end
    end
end
end

function s = elapsed_of(S)
s = NaN;
if ~isstruct(S)
    return;
end
if isfield(S, 't_elapsed_s') && isnumeric(S.t_elapsed_s) && isscalar(S.t_elapsed_s) ...
        && isfinite(S.t_elapsed_s) && S.t_elapsed_s > 0
    s = double(S.t_elapsed_s);
    return;
end
s = wall_span(S);
if isfinite(s) && s > 0
    return;
end
if isfield(S, 'params') && isstruct(S.params)
    s = wall_span(S.params);
    if isfinite(s) && s > 0
        return;
    end
end
% 完成的 run 可用 duration_s（墙钟预算）估采集间隔
if isfield(S, 'duration_s') && isnumeric(S.duration_s) && isscalar(S.duration_s) ...
        && isfinite(S.duration_s) && S.duration_s > 0
    s = double(S.duration_s);
end
end

function s = wall_span(P)
s = NaN;
if ~isstruct(P)
    return;
end
a = str_of(P, 'started_at');
b = str_of(P, 'saved_at');
if strlength(a) < 8 || strlength(b) < 8
    return;
end
t1 = parse_iso(a);
t2 = parse_iso(b);
if isempty(t1) || isempty(t2)
    return;
end
s = seconds(t2 - t1);
if ~(isfinite(s) && s > 0)
    s = NaN;
end
end

function t = parse_iso(str)
t = [];
str = char(string(str));
try
    t = datetime(str, 'InputFormat', 'yyyy-MM-dd''T''HH:mm:ss');
    return;
catch
end
try
    t = datetime(str, 'InputFormat', 'yyyy-mm-ddTHH:MM:SS');
catch
    t = [];
end
end

function s = str_of(P, k)
s = '';
if isstruct(P) && isfield(P, k) && ~isempty(P.(k))
    s = strtrim(char(string(P.(k))));
end
end
