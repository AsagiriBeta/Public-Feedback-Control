function s = pfc_ui_scale(h)
%PFC_UI_SCALE 返回包含 h 的窗口当前的界面缩放系数（取不到则 1）。
%  运行时绘图（pfc_update_signal_fft / pfc_plot_feedback）用它统一字号：
%  窗口被放大/缩小后，图内标题与刻度跟着一起缩放，避免大图小字或小图大字。
%  缩放系数由 pfc_layout_scale 写入 figure 的 appdata('pfcScale')。
s = 1;
try
    if strcmp(get(h, 'Type'), 'figure')
        fig = h;
    else
        fig = ancestor(h, 'figure');
    end
    if isempty(fig)
        return;
    end
    v = getappdata(fig, 'pfcScale');
    if isscalar(v) && isnumeric(v) && isfinite(v) && v > 0
        s = v;
    end
catch
end
end
