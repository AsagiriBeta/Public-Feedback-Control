function pfc_plot_feedback(handles, pulse, sc, ic, volt, xmax, ymax)
%PFC_PLOT_FEEDBACK 刷新电压 / SC / IC 点图。
C = pfc_ui_colors();
axBg = C.axBg; axFg = C.axFg; gridC = C.grid; accent = C.line;
if nargin < 6 || isempty(xmax), xmax = max(40, pulse + 5); end
if nargin < 7 || isempty(ymax), ymax = max(50, volt * 1.2); end
style_dot(handles.realtimeSCplot, pulse, sc, accent, xmax, [], '稳态空化  SC · 2f', axBg, axFg, gridC);
style_dot(handles.realtimeICplot, pulse, ic, accent, xmax, [], '惯性空化  IC · 3.3 MHz', axBg, axFg, gridC);
style_dot(handles.realtimeVplot, pulse, volt, accent, xmax, [0 ymax], '电压  Voltage (mVpp)', axBg, axFg, gridC);
end

function style_dot(ax, x, y, col, xmax, ylims, ttl, axBg, axFg, gridC)
hold(ax, 'on');
plot(ax, x, y, '.', 'Color', col, 'MarkerSize', 16);
set(ax, 'Color', axBg, 'XColor', axFg, 'YColor', axFg, ...
    'GridColor', gridC, 'GridAlpha', 0.5, 'GridLineStyle', ':', ...
    'Box', 'off', 'TickDir', 'out', 'XLim', [0 xmax]);
if ~isempty(ylims)
    set(ax, 'YLim', ylims);
end
title(ax, ttl, 'Color', axFg, 'FontSize', 10);
xlabel(ax, 'Pulse #', 'Color', axFg);
grid(ax, 'on');
end
