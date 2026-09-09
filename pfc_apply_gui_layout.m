function pfc_apply_gui_layout(fig)
%PFC_APPLY_GUI_LAYOUT 对齐 GUIDE 控件、中英标签，并套深色样式。

C = pfc_ui_colors();
scr = get(0, 'ScreenSize');
W = min(1580, max(1280, scr(3) - 48));
H = min(940, max(860, scr(4) - 90));
set(fig, 'Units', 'pixels', 'Position', [40 50 W H], ...
    'Color', C.fig, 'Resize', 'off', 'Visible', 'on', ...
    'Name', 'PFC  ·  DHO814 / DG2052', ...
    'MenuBar', 'none', 'ToolBar', 'none', 'NumberTitle', 'off');
try
    set(fig, 'AutoResizeChildren', 'off');
catch
end
movegui(fig, 'onscreen');
set(fig, 'Units', 'pixels');
fp = get(fig, 'Position');
W = fp(3); H = fp(4);

L = 18; LW = 520; G = 5; top_clear = 56; bot = 14;
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
style_panel(getp(fig,'uibuttongroup5'), C, '实时 / Realtime');

% --- file ---
f1 = getp(fig,'uibuttongroup1');
labw = 118; editx = 14+labw+8; editw = LW - editx - 14;
id_y = max(44, file_h - 54);
place(getp(f1,'text42'), 14, id_y + 4, labw, 22);
place(getp(f1,'studyID'), editx, id_y, editw, 26);
place(getp(f1,'Choose_file'), 14, 10, labw, 26);
place(getp(f1,'directory'), editx, 10, editw, 26);
style_label(getp(f1,'text42'), C, '文件名  ID');
style_edit(getp(f1,'studyID'), C);
style_edit(getp(f1,'directory'), C);
set(getp(f1,'directory'), 'FontSize', 10);
style_btn(getp(f1,'Choose_file'), C, '浏览  Browse');

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
style_btn(getp(f3,'Sonication'), C, '4. 开始闭环  Feedback');

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
style_btn(getp(f4,'PCDcontrol'), C, '2. 无微泡');
style_btn(getp(f4,'OpenMB'), C, '3. 有微泡开环');

% --- stage 1 ---
style_btn(getp(acq,'OneshotFFT'), C, '单次  One-shot');
style_btn(getp(acq,'DebugRun'), C, '连续调试  Debug');

% --- plots ---
g5 = getp(fig,'uibuttongroup5');
gap = 22;
row_gap = 48;
top_pad = 28;
bot_block = 100;
xL = 50;
axw = floor((RW - xL - 16 - gap) / 2);
axh = floor((RH - top_pad - bot_block - 2 * row_gap) / 3);
axh = max(140, min(210, axh));
xR = xL + axw + gap;
yT = RH - top_pad - axh;
yM = yT - row_gap - axh;
yB = bot_block;
place(getp(g5,'Signal_plot'), xL, yT, axw, axh);
place(getp(g5,'FFT_plot'), xR, yT, axw, axh);
place(getp(g5,'realtimeVplot'), xL, yM, axw, axh);
place(getp(g5,'realtimeSCplot'), xR, yM, axw, axh);
place(getp(g5,'realtimeICplot'), xL, yB, axw, axh);
style_axes(getp(g5,'Signal_plot'), '时域  Time');
style_axes(getp(g5,'FFT_plot'), '频谱  FFT');
style_axes(getp(g5,'realtimeVplot'), '电压  Voltage');
style_axes(getp(g5,'realtimeSCplot'), '稳态空化  SC · 2f (3 MHz)');
style_axes(getp(g5,'realtimeICplot'), '惯性空化  IC · 3.3 MHz');

place(getp(g5,'PulseNum'), xR, yB + axh - 38, axw, 34);
place(getp(g5,'stop'), xR, yB, axw, 72);
style_label(getp(g5,'PulseNum'), C, '脉冲  Pulse #');
set(getp(g5,'PulseNum'), 'HorizontalAlignment', 'center', 'FontSize', 12, ...
    'BackgroundColor', C.panel);
st = getp(g5,'stop');
style_btn(st, C, '停止超声  STOP FUS');
set(st, 'BackgroundColor', C.danger, 'ForegroundColor', [1 1 1], 'FontSize', 15);
end

function C = pfc_ui_colors()
C.fig    = [0.11 0.12 0.14];
C.panel  = [0.16 0.17 0.20];
C.text   = [0.93 0.94 0.96];
C.muted  = [0.70 0.73 0.78];
C.editBg = [0.08 0.09 0.10];
C.editFg = [0.95 0.96 0.97];
C.btn    = [0.82 0.64 0.28];
C.btnFg  = [0.10 0.10 0.10];
C.danger = [0.70 0.22 0.22];
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
cb = @(src, ~) pfc_debug_live('apply', guidata(ancestor(src, 'figure')));
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
    'FontSize', 11, 'FontWeight', 'bold', 'Title', title);
try
    set(obj, 'BorderColor', [0.38 0.40 0.44]);
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

function style_btn(obj, C, str)
set(obj, 'String', str, 'BackgroundColor', C.btn, 'ForegroundColor', C.btnFg, ...
    'FontSize', 12, 'FontWeight', 'bold', 'FontName', ui_font());
end

function style_axes(ax, ttl)
set(ax, 'Units', 'pixels', 'Color', [0.09 0.11 0.15], 'ColorMode', 'manual', ...
    'XColor', [0.82 0.86 0.90], 'YColor', [0.82 0.86 0.90], ...
    'GridColor', [0.32 0.38 0.44], 'Box', 'on', 'FontSize', 9);
title(ax, ttl, 'Color', [0.90 0.93 0.95], 'FontSize', 10, 'FontWeight', 'normal');
xlabel(ax, '', 'Color', [0.82 0.86 0.90], 'FontSize', 9);
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
