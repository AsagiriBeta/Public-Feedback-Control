function ok = pfc_gui_busy(handles, running)
%PFC_GUI_BUSY 运行中锁定按钮，避免连点打开第二路 visadev。
ok = true;
if running
    if ~pfc_visa('try_busy')
        ok = false;
        warndlg('已有采集在运行。请等待结束，或按 STOP FUS。', 'PFC');
        return;
    end
    en = 'off';
    msg = '运行中… 请勿重复点击。STOP FUS 可停止。';
else
    pfc_visa('end_busy');
    en = 'on';
    msg = '';
end

tags = {'OneshotFFT', 'DebugRun', 'PCDcontrol', 'OpenMB', 'Sonication', 'IniFgen', 'Choose_file'};
for i = 1:numel(tags)
    t = tags{i};
    if isfield(handles, t) && isgraphics(handles.(t))
        set(handles.(t), 'Enable', en);
    else
        o = findobj(gcbf, 'Tag', t);
        if ~isempty(o)
            set(o(1), 'Enable', en);
        end
    end
end
if isfield(handles, 'PulseNum') && isgraphics(handles.PulseNum) && ~isempty(msg)
    set(handles.PulseNum, 'String', msg);
end
drawnow;
end
