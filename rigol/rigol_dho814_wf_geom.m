function varargout = rigol_dho814_wf_geom(cmd, dev, ch)
%RIGOL_DHO814_WF_GEOM 缓存 :WAVeform 的波形几何，避免每帧重复查询。
%
% 为什么值得单独做一层：实测（DHO814 / USB VISA）**查询类命令约 31 ms/条，
% :WAVeform:* 那几条更慢，6 条合计 561 ms**，而写命令只要 1.4 ms。一帧要读两路，
% 每路 6 条几何查询 —— 光这些查询就占了整帧 732 ms 的一大半，而它们帧间根本不变。
% 缓存后整帧时间从 ~0.73 s 掉到 ~0.17 s，5 Hz 才有可能跑得动。
%
% 哪些会变、哪些不会：
%   POINts / XINCrement / XORigin  —— 由存储深度与时基决定，一轮实验里定死（setup 时 reset）。
%   YORigin / YREFerence / YINCrement —— 由**竖直量程**决定，set_ranges 换档时会变，
%                                        所以换档处必须调用 'stale'。这是本缓存唯一的正确性前提：
%                                        漏调一次，之后所有帧的电压换算就都是错的。
%
%   G = rigol_dho814_wf_geom('get', dev, ch)   取该通道几何（命中缓存则不查仪器）
%       rigol_dho814_wf_geom('stale')          竖直量程变了，下次 get 重新查 Y 部分
%       rigol_dho814_wf_geom('reset')          全清（setup / 换时基 / 换深度后调用）
persistent C
if isempty(C)
    C = struct('key', {}, 'poins', {}, 'xinc', {}, 'xorigin', {}, 'yinc', {}, 'yor', {}, 'yref', {}, 'y_ok', {});
end
if nargin < 1 || isempty(cmd)
    cmd = 'get';
end

switch lower(char(cmd))
    case 'reset'
        C = C([]);
        return
    case 'stale'
        for i = 1:numel(C)
            C(i).y_ok = false;
        end
        return
    case 'get'
        if nargin < 3 || isempty(ch)
            ch = 1;
        end
        key = sprintf('%s|%d', res_name(dev), double(ch));
        i = find(strcmp({C.key}, key), 1, 'first');
        if isempty(i)
            C(end+1) = struct('key', key, 'poins', NaN, 'xinc', NaN, 'xorigin', NaN, ...
                'yinc', NaN, 'yor', NaN, 'yref', NaN, 'y_ok', false);
            i = numel(C);
        end
        % 水平几何：深度/时基不变就一直有效
        if ~(isfinite(C(i).poins) && C(i).poins >= 256)
            C(i).poins   = qnum(dev, ':WAVeform:POINts?');
            C(i).xinc    = qnum(dev, ':WAVeform:XINCrement?');
            C(i).xorigin = qnum(dev, ':WAVeform:XORigin?');
        end
        % 竖直几何：只有量程换过才重查
        if ~C(i).y_ok
            C(i).yinc = qnum(dev, ':WAVeform:YINCrement?');
            C(i).yor  = qnum(dev, ':WAVeform:YORigin?');
            C(i).yref = qnum(dev, ':WAVeform:YREFerence?');
            C(i).y_ok = isfinite(C(i).yinc) && C(i).yinc ~= 0;
        end
        G = struct('poins', C(i).poins, 'xinc', C(i).xinc, 'xorigin', C(i).xorigin, ...
            'yinc', C(i).yinc, 'yor', C(i).yor, 'yref', C(i).yref);
        if nargout > 0
            varargout{1} = G;
        end
    otherwise
        error('rigol:wfgeom:cmd', '未知命令 %s', cmd);
end
end

function s = res_name(dev)
%RES_NAME 用 VISA 资源名做缓存键；取不到就用类名兜底（单台示波器场景够用）
s = '';
try
    s = char(string(dev.ResourceName));
catch
    s = class(dev);
end
end

function v = qnum(dev, cmd)
v = NaN;
try
    v = str2double(rigol_visa_query(dev, cmd));
catch
end
end
