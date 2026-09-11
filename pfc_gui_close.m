function pfc_gui_close(fig)
%PFC_GUI_CLOSE 关闭主界面：先把当前参数存盘，再删除窗口。
try
    pfc_gui_params('save', guidata(fig));
catch
end
delete(fig);
end
