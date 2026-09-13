function s = pfc_layout_scale(fig, dw, dh)
%PFC_LAYOUT_SCALE 界面整体等比自适应：把「设计尺寸」的布局缩放到当前窗口。
%
%   pfc_layout_scale(fig, DW, DH)  首次调用：记录各控件的设计坐标（画布 DW x DH）
%   pfc_layout_scale(fig)          按当前窗口大小重新缩放（挂到 SizeChangedFcn）
%   s = pfc_layout_scale(...)      返回本次缩放系数
%
% 原理：布局代码按固定设计像素一次排好；本函数把每个控件的 Position 与 FontSize
% 乘以 s = min(窗口宽/设计宽, 窗口高/设计高)。于是任意分辨率、任意显示缩放(DPI)、
% 任意窗口大小下内容都完整可见，且比例不变。
% 等比缩放只有一个方向能刚好填满，另一个方向会剩空白；因此这里把整块内容在窗口内
% 居中（顶层控件统一偏移），避免"偏左下、右侧/上方空一条"。
% 坐标轴标题/图例的位置是数据坐标，只缩字号、不动位置。
%
% 缩放系数存在 figure 的 appdata('pfcScale')，供运行时绘图统一字号（pfc_ui_scale）。

SMIN = 0.5;   % 最小缩放，同时作为窗口最小尺寸（再小就会裁内容）
SMAX = 2.0;   % 最大缩放，仅作上限保护（大屏上允许内容跟着放大）

s = 1;
if ~isgraphics(fig) || ~strcmp(get(fig, 'Type'), 'figure')
    return;
end

D = getappdata(fig, 'pfcDesign');
if nargin >= 3 && ~isempty(dw) && ~isempty(dh)
    % 传入画布尺寸 → 现在就按当前（设计尺寸）状态重新记录，保证坐标最新
    D = record_design(fig, dw, dh);
    setappdata(fig, 'pfcDesign', D);
elseif isempty(D)
    return;   % 还没记录过设计坐标，没法缩放
end

% 防重入：应用缩放会改控件位置，可能再次触发 SizeChangedFcn
if isappdata(fig, 'pfcScalingBusy')
    v = getappdata(fig, 'pfcScale');
    if ~isempty(v), s = v; end
    return;
end
setappdata(fig, 'pfcScalingBusy', 1);

try
    fp = get(fig, 'Position');

    % 约束窗口最小尺寸：否则再缩放也放不下，内容会被裁掉
    minW = round(D.W * SMIN);
    minH = round(D.H * SMIN);
    if fp(3) < minW || fp(4) < minH
        fp(3) = max(fp(3), minW);
        fp(4) = max(fp(4), minH);
        set(fig, 'Position', fp);
    end

    s = min(fp(3) / D.W, fp(4) / D.H);
    s = max(SMIN, min(s, SMAX));
    apply_scale(D, s, fig);
    setappdata(fig, 'pfcScale', s);
catch
    % 缩放失败也不能影响主流程
end

rmappdata(fig, 'pfcScalingBusy');
end

function D = record_design(fig, dw, dh)
% 记录「设计坐标」：像素位置 + 字号。标题/图例只记字号（位置是数据坐标）。
posTypes  = {'uicontrol', 'uipanel', 'uibuttongroup', 'axes'};
fontTypes = {'text', 'legend'};

D = struct('W', dw, 'H', dh, 'bbox', [0 0 dw dh], ...
    'handles', {{}}, 'pos', zeros(0, 4), 'font', [], 'hasFont', [], ...
    'scalePos', [], 'isTop', []);

x0 = inf; y0 = inf; x1 = -inf; y1 = -inf;
kids = findall(fig);
for k = 1:numel(kids)
    h = kids(k);
    if ~isgraphics(h) || isequal(h, fig)
        continue;
    end
    typ = get(h, 'Type');
    doPos = any(strcmp(typ, posTypes));
    if ~doPos && ~any(strcmp(typ, fontTypes))
        continue;
    end

    if doPos
        try
            p = double(get(h, 'Position'));
        catch
            continue;
        end
        if numel(p) ~= 4
            continue;
        end
    else
        p = [NaN NaN NaN NaN];
    end

    f = NaN;
    hasF = false;
    if isprop(h, 'FontSize')
        try
            f = double(get(h, 'FontSize'));
            hasF = isscalar(f) && isfinite(f) && f > 0;
        catch
        end
    end

    D.handles{end+1}    = h;      %#ok<AGROW>
    D.pos(end+1, :)     = p;      %#ok<AGROW>
    D.font(end+1, 1)    = f;      %#ok<AGROW>
    D.hasFont(end+1, 1) = hasF;   %#ok<AGROW>
    D.scalePos(end+1, 1) = doPos; %#ok<AGROW>
    isTop = isequal(get(h, 'Parent'), fig);
    D.isTop(end+1, 1)   = isTop;  %#ok<AGROW>

    % 顶级可见内容的实际包围盒（用于居中；跳过被挪到屏幕外的隐藏控件）
    if doPos && isTop && strcmp(get(h, 'Visible'), 'on') && p(1) > -1000
        x0 = min(x0, p(1));       y0 = min(y0, p(2));
        x1 = max(x1, p(1) + p(3)); y1 = max(y1, p(2) + p(4));
    end
end
if all(isfinite([x0 y0 x1 y1])) && x1 > x0 && y1 > y0
    D.bbox = [x0 y0 x1 y1];
end
end

function apply_scale(D, s, fig)
% 只对"顶层控件"加偏移即可移动整块内容（子控件跟着父级走）。
% 偏移量按内容实际包围盒算，使四周留白相等（不按画布算，否则顶部会偏大）。
fp = double(get(fig, 'Position'));
bb = D.bbox;
if numel(bb) == 4 && all(isfinite(bb)) && bb(3) > bb(1) && bb(4) > bb(2)
    dx = (fp(3) - s * (bb(1) + bb(3))) / 2;
    dy = (fp(4) - s * (bb(2) + bb(4))) / 2;
else
    dx = (fp(3) - D.W * s) / 2;
    dy = (fp(4) - D.H * s) / 2;
end
dx = max(0, dx);
dy = max(0, dy);

for k = 1:numel(D.handles)
    h = D.handles{k};
    if ~isgraphics(h)
        continue;
    end
    try
        if D.scalePos(k)
            p = D.pos(k, :);
            x = p(1) * s;
            y = p(2) * s;
            if D.isTop(k)
                x = x + dx;
                y = y + dy;
            end
            set(h, 'Position', [x, y, p(3) * s, p(4) * s]);
        end
        if D.hasFont(k)
            set(h, 'FontSize', max(7, D.font(k) * s));
        end
    catch
    end
end
end
