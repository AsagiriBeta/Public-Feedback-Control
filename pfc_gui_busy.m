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

tags = {'OneshotFFT', 'DebugRun', 'PCDcontrol', 'OpenMB', 'Sonication', 'IniFgen', ...
    'Choose_file', 'InstrSetup', 'CheckUpdate'};
for i = 1:numel(tags)
    t = tags{i};
    if isfield(handles, t) && isgraphics(handles.(t))
        set_btn(handles.(t), en);
    else
        o = findobj(gcbf, 'Tag', t);
        if ~isempty(o)
            set_btn(o(1), en);
        end
    end
end
if isfield(handles, 'PulseNum') && isgraphics(handles.PulseNum) && ~isempty(msg)
    set(handles.PulseNum, 'String', msg);
end
drawnow;
end

function set_btn(h, en)
%SET_BTN 直角按钮是「uipanel + 居中文本」：锁定靠清空 ButtonDownFcn 并压暗配色，
% 解锁则还原回调与配色；普通控件（如隐藏的 IniFgen）仍走 Enable。
if ~isgraphics(h)
    return;
end
if ~strcmp(get(h, 'Type'), 'uipanel')
    set(h, 'Enable', en);
    return;
end
ud = get(h, 'UserData');
if ~isstruct(ud) || ~isfield(ud, 'face')
    return;
end
lab = [];
if isfield(ud, 'label') && isgraphics(ud.label)
    lab = ud.label;
end
if strcmp(en, 'on')
    bg = ud.face; fg = ud.fg; bd = ud.cb;
else
    bg = 0.45 * ud.face; fg = [0.50 0.53 0.57]; bd = [];
end
set(h, 'BackgroundColor', bg, 'ButtonDownFcn', bd);
if ~isempty(lab)
    set(lab, 'BackgroundColor', bg, 'ForegroundColor', fg, 'ButtonDownFcn', bd);
end
end
