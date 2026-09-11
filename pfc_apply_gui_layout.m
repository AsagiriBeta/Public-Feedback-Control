function pfc_apply_gui_layout(fig)
%PFC_APPLY_GUI_LAYOUT 对齐 GUIDE 控件、中英标签，并套深色样式。

C = pfc_ui_colors();
scr = get(0, 'ScreenSize');
W = min(1580, max(1280, scr(3) - 48));
H = min(940, max(860, scr(4) - 90));
set(fig, 'Units', 'pixels', 'Position', [40 50 W H], ...
    'Color', C.fig, 'Resize', 'off', 'Visible', 'on', ...
    'Name', ['PFC  ·  DHO814 / DG2052  ·  ' pfc_version('label')], ...
    'MenuBar', 'none', 'ToolBar', 'none', 'NumberTitle', 'off');
try
    set(fig, 'AutoResizeChildren', 'off');
catch
end
movegui(fig, 'onscreen');
set(fig, 'Units', 'pixels');
fp = get(fig, 'Position');
W = fp(3); H = fp(4);

L = 18; LW = 520; G = 8; top_clear = 56; bot = 14;
file_h = 88; acq_h = 118; fus_h = 154; pcd_h = 112; fb_h = 132;

mot = getp(fig,'motor_controls');
set(mot, 'Visible', 'off');
place(mot, -2400, 0, 10, 10);

acq = ensure_acquire_panel(fig, C);

% 栏间距保持紧凑；窗口多出来的高度加到各框内部，而不是拉开框距
avail = H - top_clear - bot;
need = file_h + acq_h + fus_h + pcd_h + fb_h + 4 * G;
extra = max(0, avail - need);
add = floor(extra / 5);
file_h = file_h + add;
acq_h  = acq_h  + add;
fus_h  = fus_h  + add;
pcd_h  = pcd_h  + add;
fb_h   = fb_h   + (extra - 4 * add);

y = bot;
place(getp(fig,'uibuttongroup3'), L, y, LW, fb_h);  y = y + fb_h + G;
place(getp(fig,'uibuttongroup4'), L, y, LW, pcd_h); y = y + pcd_h + G;
place(getp(fig,'uibuttongroup2'), L, y, LW, fus_h); y = y + fus_h + G;
place(acq, L, y, LW, acq_h); y = y + acq_h + G;
place(getp(fig,'uibuttongroup1'), L, y, LW, file_h);

col1 = 14; lw = 112; ew = 72; uw = 48;
xE1 = col1+lw+4; xU1 = xE1+ew+4;
col2 = 272; xE2 = col2+lw+4; xU2 = xE2+ew+4;
pair(acq, 'debug_freq_lab','debug_freq','debug_freq_unit', ...
    col1, xE1, xU1, 52, lw, ew, uw, C, '频率  Freq', 'MHz');
pair(acq, 'debug_volt_lab','debug_volt','debug_volt_unit', ...
    col2, xE2, xU2, 52, lw, ew, uw, C, '电压  Volt', 'mVpp');
bw = floor((LW - 28 - 8) / 2);
place(getp(acq,'OneshotFFT'), 14, 10, bw, 34);
place(getp(acq,'DebugRun'), 14 + bw + 8, 10, bw, 34);
hide_help = findobj(acq, 'Tag', 'pfc_acquire_help');
if ~isempty(hide_help)
    set(hide_help, 'Visible', 'off', 'String', '');
    place(hide_help(1), -400, -400, 10, 10);
end

Rx = L + LW + 12;
RW = max(640, W - Rx - 14);
RH = H - bot - top_clear;
place(getp(fig,'uibuttongroup5'), Rx, bot, RW, RH);

style_panel(getp(fig,'uibuttongroup1'), C, '0.  文件 / File');
style_panel(acq, C, '1.  CH1 回读 / Readback · FFT');
style_panel(getp(fig,'uibuttongroup2'), C, '超声参数（2 / 3 / 4 共用）');
style_panel(getp(fig,'uibuttongroup4'), C, '2–3.  开环 CH2');
style_panel(getp(fig,'uibuttongroup3'), C, '4.  闭环反馈 / Feedback');
style_panel(getp(fig,'uibuttongroup5'), C, '实时  Realtime');

% --- file ---
f1 = getp(fig,'uibuttongroup1');
ensure_instr(fig, f1);
ensure_update(fig, f1);
labw = 118; editx = 14+labw+8;
ubw = 92;                                   % 「检查更新」摆在 ID 行右端，不挤占下面一行
editw = LW - editx - 14 - ubw - 8;
id_y = max(44, file_h - 54);
place(getp(f1,'text42'), 14, id_y + 4, labw, 22);
place(getp(f1,'studyID'), editx, id_y, editw, 26);
place(getp(f1,'CheckUpdate'), editx + editw + 8, id_y, ubw, 26);
bw = 92;
place(getp(f1,'Choose_file'), 14, 10, bw, 26);
place(getp(f1,'InstrSetup'), 14 + bw + 8, 10, bw, 26);
dx = 14 + bw + 8 + bw + 8;
place(getp(f1,'directory'), dx, 10, LW - dx - 14, 26);
style_label(getp(f1,'text42'), C, '文件名  ID');
style_edit(getp(f1,'studyID'), C);
style_edit(getp(f1,'directory'), C);
set(getp(f1,'directory'), 'FontSize', 10);
square_btn(getp(f1,'Choose_file'), C, '浏览  Browse', C.btn2);
square_btn(getp(f1,'InstrSetup'), C, '仪器设置', C.btn2);
square_btn(getp(f1,'CheckUpdate'), C, '检查更新', C.btn2);

% --- shared FUS params (stages 2–4) ---
f2 = getp(fig,'uibuttongroup2');
col1 = 14; lw = 112; ew = 72; uw = 48;
xE1 = col1+lw+4; xU1 = xE1+ew+4;
col2 = 272; xE2 = col2+lw+4; xU2 = xE2+ew+4;
row = [fus_h-52, fus_h-94, 12];
row = max(row, [96 54 12]);
pair(f2, 'text43','frequency','text44', col1, xE1, xU1, row(1), lw, ew, uw, C, '频率  Freq', 'MHz');
pair(f2, 'text45','voltage','text46',   col2, xE2, xU2, row(1), lw, ew, uw, C, '电压  Volt', 'mVpp');
pair(f2, 'text47','PRF','text48',       col1, xE1, xU1, row(2), lw, ew, uw, C, 'PRF', 'Hz');
pair(f2, 'text49','BurstCount','text50', col2, xE2, xU2, row(2), lw, ew, uw, C, '周期数  Burst', 'cyc');
set(getp(fig,'sampleNum'), 'Parent', f2);
set(getp(fig,'text58'), 'Parent', f2);
set(getp(fig,'text59'), 'Parent', f2);
pair(f2, 'text51','duration','text52',  col1, xE1, xU1, row(3), lw, ew, uw, C, '时长  Dur', 's');
pair(f2, 'text58','sampleNum','text59', col2, xE2, xU2, row(3), lw, ew, uw, C, '采样点', 'pts');
ini = getp(fig,'IniFgen');
set(ini, 'Visible', 'off');
place(ini, -2400, 0, 10, 10);

% --- stage 4 feedback：按钮与电压上限错开 ---
f3 = getp(fig,'uibuttongroup3');
lw = 168; ew = 90; uw = 56;
xE = 14+lw+8; xU = xE+ew+6;
pair(f3, 'text53','ControllerTarget','text54', 14, xE, xU, 86, lw, ew, uw, C, '目标  Target', 'dB');
pair(f3, 'text55','MaxV','text56',             14, xE, xU, 52, lw, ew, uw, C, '闭环上限  Max V', 'mVpp');
set(getp(fig,'Sonication'), 'Parent', f3);
place(getp(f3,'Sonication'), 14, 8, LW-28, 36);
square_btn(getp(f3,'Sonication'), C, '4. 开始闭环  Feedback');

% --- stages 2–3 open-loop CH2 ---
f4 = getp(fig,'uibuttongroup4');
ensure_openmb(fig, f4);
set(getp(fig,'PCDcontrol'), 'Parent', f4);
lw = 150; ew = 90; uw = 48;
xE = 14+lw+8; xU = xE+ew+6;
for tg = {'text60', 'MBLoadTime', 'text61'}
    h = getp(fig, tg{1});
    if ~isempty(h), set(h, 'Visible', 'off'); end
end
bw = floor((LW - 28 - 8) / 2);
place(getp(f4,'PCDcontrol'), 14, 8, bw, 36);
place(getp(f4,'OpenMB'), 14 + bw + 8, 8, bw, 36);
square_btn(getp(f4,'PCDcontrol'), C, '2. 无微泡');
square_btn(getp(f4,'OpenMB'), C, '3. 有微泡开环');

% --- stage 1 ---
square_btn(getp(acq,'OneshotFFT'), C, '单次  One-shot');
square_btn(getp(acq,'DebugRun'), C, '连续调试  Debug');

% --- plots ---
g5 = getp(fig,'uibuttongroup5');
gap = 26;
top_pad = 52;      % 净空：面板标题 + 坐标轴标题，避免“实时/Realtime”压住“时域/频谱”
bot_block = 96;
xL = 52;
axw = floor((RW - xL - 16 - gap) / 2);
row_gap = 46;
axh = floor((RH - top_pad - bot_block - 2 * row_gap) / 3);
if axh < 112          % 窗口偏矮时压缩行距，保证三行仍放得下
    row_gap = max(26, floor((RH - top_pad - bot_block - 3 * 112) / 2));
    axh = floor((RH - top_pad - bot_block - 2 * row_gap) / 3);
end
axh = max(96, min(axh, 200));
xR = xL + axw + gap;
yT = RH - top_pad - axh;
yM = yT - row_gap - axh;
yB = bot_block;
place(getp(g5,'Signal_plot'), xL, yT, axw, axh);
place(getp(g5,'FFT_plot'), xR, yT, axw, axh);
place(getp(g5,'realtimeVplot'), xL, yM, axw, axh);
place(getp(g5,'realtimeSCplot'), xR, yM, axw, axh);
place(getp(g5,'realtimeICplot'), xL, yB, axw, axh);
style_axes(getp(g5,'Signal_plot'), C, '时域  Time');
style_axes(getp(g5,'FFT_plot'), C, '频谱  FFT');
style_axes(getp(g5,'realtimeVplot'), C, '电压  Voltage (mVpp)');
style_axes(getp(g5,'realtimeSCplot'), C, '稳态空化  SC · 2f');
style_axes(getp(g5,'realtimeICplot'), C, '惯性空化  IC · 3.3 MHz');

place(getp(g5,'PulseNum'), xR, yB + axh - 36, axw, 32);
place(getp(g5,'stop'), xR, yB, axw, 68);
style_label(getp(g5,'PulseNum'), C, '脉冲  Pulse #');
set(getp(g5,'PulseNum'), 'HorizontalAlignment', 'center', 'FontSize', 12, ...
    'BackgroundColor', C.panel);
square_btn(getp(g5,'stop'), C, '停止超声  STOP FUS', C.danger, 15);

watch_params(fig);
end

function watch_params(fig)
%WATCH_PARAMS 改完参数、焦点离开编辑框时立刻存盘，避免只在关闭时才保存。
tags = {'frequency', 'voltage', 'PRF', 'BurstCount', 'duration', 'sampleNum', ...
    'ControllerTarget', 'MaxV', 'MBLoadTime', 'studyID', 'directory'};
for i = 1:numel(tags)
    o = findobj(fig, 'Tag', tags{i}, '-depth', inf);
    if ~isempty(o)
        set(o(1), 'Callback', @(src, ~) pfc_gui_params('save', guidata(ancestor(src, 'figure'))));
    end
end
end

function edit_debug_cb(src)
%EDIT_DEBUG_CB 调试框：运行中即时下发频率/电压，同时把最新值存盘。
h = guidata(ancestor(src, 'figure'));
try, pfc_debug_live('apply', h); catch, end
try, pfc_gui_params('save', h); catch, end
end

function pair(parent, tLab, tEdit, tUnit, xL, xE, xU, y, lw, ew, uw, C, lab, unit)
place(getp(parent,tLab), xL, y+2, lw, 22);
place(getp(parent,tEdit), xE, y, ew, 26);
place(getp(parent,tUnit), xU, y+2, uw, 22);
style_label(getp(parent,tLab), C, lab);
style_edit(getp(parent,tEdit), C);
style_label(getp(parent,tUnit), C, unit);
set(getp(parent,tUnit), 'ForegroundColor', C.muted);
end

function acq = ensure_acquire_panel(fig, C)
acq = findobj(fig, 'Tag', 'pfc_acquire_panel');
if isempty(acq)
    acq = uibuttongroup('Parent', fig, 'Tag', 'pfc_acquire_panel', ...
        'Title', '1.  采集 / Acquire · FFT', 'Units', 'pixels', ...
        'ForegroundColor', C.text, 'BackgroundColor', C.panel);
    uicontrol('Parent', acq, 'Style', 'pushbutton', 'Tag', 'OneshotFFT', ...
        'Units', 'pixels', ...
        'Callback', @(src, ~) MatlabScript_FeedbackControl('OneshotFFT_Callback', src, [], guidata(fig)));
    uicontrol('Parent', acq, 'Style', 'pushbutton', 'Tag', 'DebugRun', ...
        'Units', 'pixels', ...
        'Callback', @(src, ~) MatlabScript_FeedbackControl('DebugRun_Callback', src, [], guidata(fig)));
else
    acq = acq(1);
    if isempty(findobj(acq, 'Tag', 'DebugRun'))
        uicontrol('Parent', acq, 'Style', 'pushbutton', 'Tag', 'DebugRun', ...
            'Units', 'pixels', ...
            'Callback', @(src, ~) MatlabScript_FeedbackControl('DebugRun_Callback', src, [], guidata(fig)));
    end
end
cb = @(src, ~) edit_debug_cb(src);
ensure_txt(acq, 'debug_freq_lab');
ensure_edit(acq, 'debug_freq', '1.5', cb);
ensure_txt(acq, 'debug_freq_unit');
ensure_txt(acq, 'debug_volt_lab');
ensure_edit(acq, 'debug_volt', '20', cb);
ensure_txt(acq, 'debug_volt_unit');
end

function ensure_openmb(fig, parent)
if isempty(findobj(fig, 'Tag', 'OpenMB'))
    uicontrol('Parent', parent, 'Style', 'pushbutton', 'Tag', 'OpenMB', ...
        'Units', 'pixels', ...
        'Callback', @(src, ~) MatlabScript_FeedbackControl('OpenMB_Callback', src, [], guidata(fig)));
else
    set(findobj(fig, 'Tag', 'OpenMB', '-depth', inf), 'Parent', parent);
end
end

function ensure_instr(fig, parent)
% 「仪器设置」按钮：打包后用它改 VISA 地址，不用改源码。
if isempty(findobj(fig, 'Tag', 'InstrSetup'))
    uicontrol('Parent', parent, 'Style', 'pushbutton', 'Tag', 'InstrSetup', ...
        'Units', 'pixels', ...
        'Callback', @(src, ~) MatlabScript_FeedbackControl('InstrSetup_Callback', src, [], guidata(fig)));
else
    set(findobj(fig, 'Tag', 'InstrSetup', '-depth', inf), 'Parent', parent);
end
end

function ensure_update(fig, parent)
% 「检查更新」按钮：读更新源清单，有新版本就下载并启动安装程序。
if isempty(findobj(fig, 'Tag', 'CheckUpdate'))
    uicontrol('Parent', parent, 'Style', 'pushbutton', 'Tag', 'CheckUpdate', ...
        'Units', 'pixels', ...
        'Callback', @(src, ~) MatlabScript_FeedbackControl('CheckUpdate_Callback', src, [], guidata(fig)));
else
    set(findobj(fig, 'Tag', 'CheckUpdate', '-depth', inf), 'Parent', parent);
end
end

function ensure_txt(parent, tag)
if isempty(findobj(parent, 'Tag', tag))
    uicontrol('Parent', parent, 'Style', 'text', 'Tag', tag, 'Units', 'pixels');
end
end

function ensure_edit(parent, tag, def, cb)
o = findobj(parent, 'Tag', tag);
if isempty(o)
    o = uicontrol('Parent', parent, 'Style', 'edit', 'Tag', tag, ...
        'Units', 'pixels', 'String', def, 'Callback', cb);
else
    set(o(1), 'Callback', cb);
    if isempty(strtrim(char(get(o(1), 'String'))))
        set(o(1), 'String', def);
    end
end
end

function style_panel(obj, C, title)
set(obj, 'ForegroundColor', C.text, 'BackgroundColor', C.panel, ...
    'FontSize', 10.5, 'FontWeight', 'bold', 'Title', title);
try
    set(obj, 'BorderColor', C.border);
catch
end
end

function style_label(obj, C, str)
set(obj, 'Style', 'text', 'BackgroundColor', C.panel, 'ForegroundColor', C.text, ...
    'FontSize', 11, 'HorizontalAlignment', 'left', 'FontName', ui_font());
if ~isempty(str)
    set(obj, 'String', str);
end
end

function style_edit(obj, C)
set(obj, 'BackgroundColor', C.editBg, 'ForegroundColor', C.editFg, ...
    'FontSize', 12, 'HorizontalAlignment', 'left', 'FontName', ui_font());
end

function square_btn(obj, C, str, face, fs)
%SQUARE_BTN 直角按钮。macOS 原生 pushbutton 一定是圆角且无半径属性，
% 这里用「无边框 uipanel（直角填充）+ 垂直居中文本」替换它，与直角面板统一。
% 可点性靠 ButtonDownFcn；面/字色与回调存进 UserData 供 pfc_gui_busy 使用。
if nargin < 4 || isempty(face)
    face = C.btn;
end
if nargin < 5 || isempty(fs)
    fs = 12;
end
tag = get(obj, 'Tag');
cb  = get(obj, 'Callback');
pos = get(obj, 'Position');
par = get(obj, 'Parent');
delete(obj);

p = uipanel('Parent', par, 'Units', 'pixels', 'Position', pos, ...
    'BackgroundColor', face, 'BorderType', 'none', 'Tag', tag);
lh = min(pos(4), round(fs * 1.7));
lab = uicontrol('Parent', p, 'Style', 'text', 'Units', 'pixels', ...
    'Position', [1, round((pos(4) - lh) / 2), max(1, pos(3) - 2), lh], ...
    'String', str, 'BackgroundColor', face, 'ForegroundColor', C.btnFg, ...
    'HorizontalAlignment', 'center', 'FontSize', fs, 'FontWeight', 'bold', ...
    'Enable', 'inactive', 'FontName', ui_font());
set(p, 'UserData', struct('face', face, 'fg', C.btnFg, 'cb', cb, 'label', lab));
if ~isempty(cb)
    set(p, 'ButtonDownFcn', cb);
    set(lab, 'ButtonDownFcn', cb);
end
end

function style_axes(ax, C, ttl)
set(ax, 'Units', 'pixels', 'Color', C.axBg, 'ColorMode', 'manual', ...
    'XColor', C.axFg, 'YColor', C.axFg, 'GridColor', C.grid, ...
    'GridAlpha', 0.5, 'GridLineStyle', ':', 'Box', 'off', ...
    'XGrid', 'on', 'YGrid', 'on', ...
    'TickDir', 'out', 'TickLength', [0.012 0.012], 'FontSize', 9);
title(ax, ttl, 'Color', C.text, 'FontSize', 10, 'FontWeight', 'normal');
xlabel(ax, '', 'Color', C.axFg, 'FontSize', 9);
ylabel(ax, '', 'Color', C.axFg, 'FontSize', 9);
end

function n = ui_font()
if ismac
    n = 'PingFang SC';
else
    n = 'Microsoft YaHei UI';
end
end

function o = getp(parent, tag)
o = findobj(parent, 'Tag', tag, '-depth', inf);
if isempty(o)
    error('pfc_apply_gui_layout:missingTag', 'missing tag %s', tag);
end
o = o(1);
end

function place(obj, x, y, w, ht)
set(obj, 'Units', 'pixels', 'Position', [x y w ht]);
end
