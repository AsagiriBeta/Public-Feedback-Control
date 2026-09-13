function pfc_instr_dialog()
%PFC_INSTR_DIALOG 仪器设置：自动扫描 + 选择 + 手动输入。
%
% 「仪器设置」按钮的实体。相比早先只有两个输入框的 inputdlg，这里可以：
%   1) 一键扫描本机 VISA 资源（visadevlist + *IDN?），列出型号与序列号；
%   2) 选中一行、点「设为示波器 / 设为信号源」直接指派，不用手抄 VISA 地址；
%   3) 扫描不到时（没装 NI-VISA、走 LAN 且未广播等）仍可手动输入地址兜底。
%
% 保存写入 <工作根>/rigol_config.ini 并断开现有连接，下次采集按新地址重连。
% 采集进行中不允许打开（调用方已用 pfc_visa('is_busy') 拦截，这里再兜一层）。
C = pfc_ui_colors();
W = 660;
H = 480;

if pfc_visa('is_busy')
    warndlg('采集进行中，请先 STOP。', 'PFC');
    return;
end

cfg = rigol_instr_config();
S = struct('devs', []);

% 宽度先算好：[] 里的 "W - 28" 会被当成 3 个元素（空格是分隔符），必须用变量
innerW = W - 28;
editX = 104;
editW = W - editX - 14;
statX = 142;
statW = W - statX - 14;

fig = figure('Name', '仪器设置 / Instruments', 'NumberTitle', 'off', ...
    'MenuBar', 'none', 'ToolBar', 'none', 'Resize', 'off', ...
    'Color', C.fig, 'Units', 'pixels', 'Position', [120 120 W H], ...
    'WindowStyle', 'modal', 'Visible', 'off');
movegui(fig, 'center');

mk_text(fig, C, [14 444 innerW 24], ...
    '点「扫描仪器」列出现有设备；选中一行后指派，或直接在下面输入地址。', C.muted);
mk_btn(fig, C, [14 406 120 30], '扫描仪器', C.btn, @do_scan);
stat = mk_text(fig, C, [statX 406 statW 30], '尚未扫描。', C.text);

list = uicontrol('Parent', fig, 'Style', 'listbox', 'Units', 'pixels', ...
    'Position', [14 196 innerW 200], 'String', {'（点「扫描仪器」开始）'}, ...
    'BackgroundColor', C.editBg, 'ForegroundColor', C.editFg, ...
    'FontName', ui_font(), 'FontSize', 10, 'Value', 1);

mk_btn(fig, C, [14 156 150 30], '↓ 设为示波器', C.btn2, @(~, ~) assign('scope'));
mk_btn(fig, C, [172 156 150 30], '↓ 设为信号源', C.btn2, @(~, ~) assign('awg'));

mk_text(fig, C, [14 116 86 22], '示波器', C.text);
scope_e = mk_edit(fig, C, [editX 112 editW 28], char(cfg.scope_visa));

mk_text(fig, C, [14 76 86 22], '信号源', C.text);
awg_e = mk_edit(fig, C, [editX 72 editW 28], char(cfg.awg_visa));

mk_btn(fig, C, [14 16 120 34], '保存', C.btn, @do_save);
mk_btn(fig, C, [142 16 120 34], '取消', C.btn2, @(~, ~) delete(fig));

set(fig, 'UserData', S);
set(fig, 'Visible', 'on');
uiwait(fig);

% ------------------------------------------------------------ 嵌套回调

    function do_scan(~, ~)
        set(stat, 'String', '正在扫描 VISA 资源…', 'ForegroundColor', C.text);
        drawnow;
        % 扫描会临时打开资源：先释放本程序占用的连接，否则示波器会被判成「资源被占用」
        pfc_visa('close');
        [devs, msg] = rigol_scan_instruments();
        S.devs = devs;
        set(fig, 'UserData', S);

        if isempty(devs)
            set(list, 'String', {'（没有发现 VISA 资源）'}, 'Value', 1);
            set(stat, 'String', msg, 'ForegroundColor', C.warn);
            return;
        end

        lines = cell(1, numel(devs));
        for i = 1:numel(devs)
            lines{i} = dev_line(devs(i));
        end
        set(list, 'String', lines, 'Value', 1);

        sc = pick(devs, 'scope');
        aw = pick(devs, 'awg');
        filled = {};
        if ~isempty(sc)
            set(scope_e, 'String', sc);
            filled{end + 1} = '示波器'; %#ok<AGROW>
        end
        if ~isempty(aw)
            set(awg_e, 'String', aw);
            filled{end + 1} = '信号源'; %#ok<AGROW>
        end

        txt = sprintf('扫描到 %d 个资源。', numel(devs));
        if isempty(filled)
            txt = [txt ' 未能自动判定型号，请选中后手动指派。'];
            set(stat, 'String', txt, 'ForegroundColor', C.warn);
        else
            txt = [txt ' 已自动填入：' strjoin(filled, ' / ') '。确认后点「保存」。'];
            set(stat, 'String', txt, 'ForegroundColor', C.text);
        end
    end

    function assign(role)
        if isempty(S.devs)
            warndlg('请先点「扫描仪器」。', 'PFC');
            return;
        end
        v = get(list, 'Value');
        v = max(1, min(numel(S.devs), v));
        addr = S.devs(v).visa;
        if strcmp(role, 'scope')
            set(scope_e, 'String', addr);
            who = '示波器';
        else
            set(awg_e, 'String', addr);
            who = '信号源';
        end
        set(stat, 'String', sprintf('已把 %s 指派给%s。', addr, who), ...
            'ForegroundColor', C.text);
    end

    function do_save(~, ~)
        s1 = strtrim(char(get(scope_e, 'String')));
        s2 = strtrim(char(get(awg_e, 'String')));
        if isempty(s1) || isempty(s2)
            warndlg('示波器与信号源的 VISA 地址都不能为空。', 'PFC');
            return;
        end
        if strcmp(s1, s2)
            warndlg('示波器与信号源填了同一个 VISA 地址，请确认。', 'PFC');
            return;
        end
        cfg.scope_visa = s1;
        cfg.awg_visa = s2;
        try
            rigol_instr_config('save', cfg);
            pfc_visa('close');     % 释放旧连接，下次采集按新地址重连
        catch err
            errordlg(err.message, '仪器设置');
            return;
        end
        delete(fig);
        msgbox(sprintf('已保存到：\n%s\n\n下次采集将按新地址连接。', ...
            rigol_instr_config('file')), '仪器设置');
    end
end

% ------------------------------------------------------------ 局部工具

function s = dev_line(d)
tag = upper(d.role);
if strcmp(d.role, 'unknown')
    tag = '?';
end
extra = d.idn;
if isempty(extra)
    extra = strtrim([d.vendor ' ' d.model]);
end
if isempty(extra)
    extra = '(未识别)';
    if ~isempty(d.error)
        extra = ['(打开失败) ' d.error];
    end
end
s = sprintf('%-6s | %s  |  %s', tag, d.visa, extra);
end

function v = pick(devs, role)
v = '';
for i = 1:numel(devs)
    if strcmp(devs(i).role, role)
        v = devs(i).visa;
        return;
    end
end
end

function h = mk_text(parent, C, pos, str, col)
if nargin < 5 || isempty(col)
    col = C.text;
end
h = uicontrol('Parent', parent, 'Style', 'text', 'Units', 'pixels', ...
    'Position', pos, 'String', str, 'BackgroundColor', C.fig, ...
    'ForegroundColor', col, 'HorizontalAlignment', 'left', ...
    'FontName', ui_font(), 'FontSize', 10);
end

function h = mk_edit(parent, C, pos, str)
h = uicontrol('Parent', parent, 'Style', 'edit', 'Units', 'pixels', ...
    'Position', pos, 'String', str, 'BackgroundColor', C.editBg, ...
    'ForegroundColor', C.editFg, 'HorizontalAlignment', 'left', ...
    'FontName', ui_font(), 'FontSize', 10);
end

function h = mk_btn(parent, C, pos, str, face, cb)
h = uicontrol('Parent', parent, 'Style', 'pushbutton', 'Units', 'pixels', ...
    'Position', pos, 'String', str, 'BackgroundColor', face, ...
    'ForegroundColor', C.btnFg, 'FontName', ui_font(), 'FontSize', 10.5, ...
    'FontWeight', 'bold', 'Callback', cb);
end

function n = ui_font()
if ismac
    n = 'PingFang SC';
else
    n = 'Microsoft YaHei UI';
end
end
