function [n, tag] = pfc_sc_harm(src)
%PFC_SC_HARM  SC 观测谐波倍数（相对驱动 f0）。
%
%   [n, tag] = pfc_sc_harm()           缺省 2（二次谐波）
%   [n, tag] = pfc_sc_harm(src)        读界面 / raw / params.sc_harm
%
% 本实验室 PCD ~3 MHz、f0=1.5 MHz → 选 2f。文献 PCD ~4.7 MHz → 选 3f。
% 换探头只改这一项，不要改 WORD/RAW。
n = 2;
tag = '2f';
raw = '';
if nargin >= 1 && ~isempty(src)
    if isstruct(src)
        if isfield(src, 'sc_harm') && ~isempty(src.sc_harm)
            raw = src.sc_harm;
        elseif isfield(src, 'params') && isstruct(src.params) && ...
                isfield(src.params, 'sc_harm') && ~isempty(src.params.sc_harm)
            raw = src.params.sc_harm;
        end
    else
        raw = src;
    end
end
if isnumeric(raw) && isscalar(raw) && isfinite(raw)
    n = double(raw);
    if abs(n - 3) < 1e-9, tag = '3f';
    elseif abs(n - 1.5) < 1e-9, tag = '1.5f';
    elseif abs(n - 0.5) < 1e-9, tag = '0.5f';
    elseif abs(n - 1) < 1e-9, tag = '1f';
    else, n = 2; tag = '2f';
    end
    return;
end
s = lower(strtrim(char(string(raw))));
s = strrep(s, ' ', '');
if isempty(s)
    return;
end
if any(strcmp(s, {'2f', 'h2', '2', 'second'}))
    n = 2; tag = '2f';
elseif any(strcmp(s, {'3f', 'h3', '3', 'third'}))
    n = 3; tag = '3f';
elseif any(strcmp(s, {'1.5f', '1.5', 'uh', 'ultraharmonic'}))
    n = 1.5; tag = '1.5f';
elseif any(strcmp(s, {'0.5f', '0.5', 'sub', 'subharmonic'}))
    n = 0.5; tag = '0.5f';
elseif any(strcmp(s, {'1f', '1', 'f0', 'fund'}))
    n = 1; tag = '1f';
end
end
