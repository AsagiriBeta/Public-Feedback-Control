function pfc_plot_feedback(handles, pulse, sc, ic, volt, xmax, ymax)
%PFC_PLOT_FEEDBACK 刷新电压 / SC / IC 点图。
axBg = [0.09 0.11 0.15];
axFg = [0.82 0.86 0.90];
if nargin < 6 || isempty(xmax), xmax = max(40, pulse + 5); end
if nargin < 7 || isempty(ymax), ymax = max(50, volt * 1.2); end
style_dot(handles.realtimeSCplot, pulse, sc, [0.30 0.82 1.00], xmax, [], '稳态空化  SC · 2f (3 MHz)', axBg, axFg);
style_dot(handles.realtimeICplot, pulse, ic, [0.95 0.72 0.28], xmax, [], '惯性空化  IC · 3.3 MHz', axBg, axFg);
style_dot(handles.realtimeVplot, pulse, volt, [0.55 0.85 0.45], xmax, [0 ymax], '电压  Voltage', axBg, axFg);
end

function style_dot(ax, x, y, col, xmax, ylims, ttl, axBg, axFg)
hold(ax, 'on');
plot(ax, x, y, '.', 'Color', col, 'MarkerSize', 16);
set(ax, 'Color', axBg, 'XColor', axFg, 'YColor', axFg, ...
    'GridColor', [0.28 0.34 0.40], 'Box', 'on', 'XLim', [0 xmax]);
if ~isempty(ylims)
    set(ax, 'YLim', ylims);
end
title(ax, ttl, 'Color', axFg, 'FontSize', 11);
xlabel(ax, 'Pulse #', 'Color', axFg);
grid(ax, 'on');
end
