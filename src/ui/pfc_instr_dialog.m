function pfc_instr_dialog()
%PFC_INSTR_DIALOG 仪器设置：扫描、指派、试连接、保存到 rigol_config.ini。
%
% 用 uifigure（不是 figure），避免钻到主窗口后面。
% 扫描只填空栏，已有地址要用「设为示波器 / 设为信号源」才会覆盖。
C = pfc_ui_colors();

if pfc_visa('is_busy')
    warndlg('采集进行中，请先 STOP。', 'PFC');
    return;
end

cfg = rigol_instr_config();
S = struct('devs', []);
fn = ui_font();

fig = uifigure('Name', '仪器设置 / Instruments', ...
    'Color', C.fig, 'Position', [100 80 760 560], ...
    'Resize', 'on', 'WindowStyle', 'modal', 'Visible', 'off');
fig.CloseRequestFcn = @(src, ~) delete(src);

g = uigridlayout(fig, [8 1]);
g.BackgroundColor = C.fig;
g.Padding = [14 12 14 12];
g.RowSpacing = 8;
g.RowHeight = {28, 36, '1x', 36, 34, 34, 34, 40};

hint = uilabel(g, 'Text', ...
    '先「扫描仪器」；空栏会自动填入识别到的型号。已有地址请选中后点「设为」。', ...
    'FontColor', C.muted, 'FontName', fn, 'FontSize', 11, 'WordWrap', 'on'); %#ok<NASGU>
hint.Layout.Row = 1;

row2 = uigridlayout(g, [1 3]);
row2.Layout.Row = 2;
row2.BackgroundColor = C.fig;
row2.ColumnWidth = {110, 90, '1x'};
row2.Padding = [0 0 0 0];
row2.ColumnSpacing = 8;
mk_btn(row2, C, fn, '扫描仪器', C.btn, @(~, ~) do_scan());
mk_btn(row2, C, fn, '试连接', C.btn2, @(~, ~) do_test());
stat = uilabel(row2, 'Text', '尚未扫描。', 'FontColor', C.text, ...
    'FontName', fn, 'FontSize', 11, 'WordWrap', 'on');

list = uilistbox(g, 'Items', {'（点「扫描仪器」开始）'}, ...
    'FontName', fn, 'FontSize', 11, ...
    'BackgroundColor', C.editBg, 'FontColor', C.editFg);
list.Layout.Row = 3;

row4 = uigridlayout(g, [1 2]);
row4.Layout.Row = 4;
row4.BackgroundColor = C.fig;
row4.Padding = [0 0 0 0];
row4.ColumnSpacing = 8;
mk_btn(row4, C, fn, '↓ 设为示波器', C.btn2, @(~, ~) assign('scope'));
mk_btn(row4, C, fn, '↓ 设为信号源', C.btn2, @(~, ~) assign('awg'));

[scope_e] = mk_addr_row(g, C, fn, 5, '示波器', char(cfg.scope_visa));
[awg_e]   = mk_addr_row(g, C, fn, 6, '信号源', char(cfg.awg_visa));

row7 = uigridlayout(g, [1 6]);
row7.Layout.Row = 7;
row7.BackgroundColor = C.fig;
row7.Padding = [0 0 0 0];
row7.ColumnWidth = {70, 70, 70, 70, 80, 70};
row7.ColumnSpacing = 8;
uilabel(row7, 'Text', '回读 CH', 'FontColor', C.text, 'FontName', fn, 'FontSize', 11);
tx_sp = mk_spin(row7, C, fn, cfg.scope_tx_channel, [1 4]);
uilabel(row7, 'Text', 'PCD CH', 'FontColor', C.text, 'FontName', fn, 'FontSize', 11);
pcd_sp = mk_spin(row7, C, fn, cfg.scope_pcd_channel, [1 4]);
uilabel(row7, 'Text', '信号源 CH', 'FontColor', C.text, 'FontName', fn, 'FontSize', 11);
awg_sp = mk_spin(row7, C, fn, cfg.awg_channel, [1 2]);

row8 = uigridlayout(g, [1 3]);
row8.Layout.Row = 8;
row8.BackgroundColor = C.fig;
row8.Padding = [0 0 0 0];
row8.ColumnWidth = {110, 110, '1x'};
row8.ColumnSpacing = 8;
mk_btn(row8, C, fn, '保存', C.btn, @(~, ~) do_save());
mk_btn(row8, C, fn, '取消', C.btn2, @(~, ~) delete(fig));
uilabel(row8, 'Text', ['配置文件：' rigol_instr_config('file')], ...
    'FontColor', C.muted, 'FontName', fn, 'FontSize', 10, 'WordWrap', 'on');

fig.Visible = 'on';
uiwait(fig);

% ------------------------------------------------------------ 回调

    function do_scan()
        stat.Text = '正在扫描 VISA 资源…';
        stat.FontColor = C.text;
        drawnow;
        pfc_visa('close');
        [devs, msg] = rigol_scan_instruments();
        S.devs = devs;

        if isempty(devs)
            set_list_items(list, {'（没有发现 VISA 资源）'});
            stat.Text = msg;
            stat.FontColor = C.warn;
            return;
        end

        lines = cell(1, numel(devs));
        for i = 1:numel(devs)
            lines{i} = dev_line(devs(i));
        end
        set_list_items(list, lines);

        sc = pick(devs, 'scope');
        aw = pick(devs, 'awg');
        filled = {};
        skipped = {};
        if ~isempty(sc)
            if isempty(edit_str(scope_e))
                scope_e.Value = sc;
                filled{end + 1} = '示波器'; %#ok<AGROW>
            else
                skipped{end + 1} = '示波器'; %#ok<AGROW>
            end
        end
        if ~isempty(aw)
            if isempty(edit_str(awg_e))
                awg_e.Value = aw;
                filled{end + 1} = '信号源'; %#ok<AGROW>
            else
                skipped{end + 1} = '信号源'; %#ok<AGROW>
            end
        end

        txt = sprintf('扫描到 %d 个资源。', numel(devs));
        if ~isempty(filled)
            txt = [txt ' 空栏已填：' strjoin(filled, ' / ') '。'];
        end
        if ~isempty(skipped)
            txt = [txt ' 已有地址未改（' strjoin(skipped, ' / ') '），要用列表「设为」才覆盖。'];
        end
        if isempty(filled) && isempty(skipped)
            txt = [txt ' 未能自动判定型号，请选中后点「设为」。'];
            stat.FontColor = C.warn;
        else
            stat.FontColor = C.text;
        end
        stat.Text = txt;
    end

    function assign(role)
        if isempty(S.devs)
            uialert(fig, '请先点「扫描仪器」。', 'PFC', 'Icon', 'warning');
            return;
        end
        idx = selected_index(list, S.devs);
        if isempty(idx)
            uialert(fig, '请先在列表里选中一台仪器。', 'PFC', 'Icon', 'warning');
            return;
        end
        addr = S.devs(idx).visa;
        if strcmp(role, 'scope')
            scope_e.Value = addr;
            who = '示波器';
        else
            awg_e.Value = addr;
            who = '信号源';
        end
        stat.Text = sprintf('已把 %s 指派给%s。', addr, who);
        stat.FontColor = C.text;
    end

    function do_test()
        s1 = edit_str(scope_e);
        s2 = edit_str(awg_e);
        if isempty(s1) && isempty(s2)
            uialert(fig, '请先扫描或填写地址。', 'PFC', 'Icon', 'warning');
            return;
        end
        if ~isempty(s1) && ~isempty(s2) && visa_same(s1, s2)
            uialert(fig, '两个地址指向同一台仪器，请分开指派后再试。', 'PFC', 'Icon', 'warning');
            return;
        end
        stat.Text = '正在试连接…';
        stat.FontColor = C.text;
        drawnow;
        pfc_visa('close');
        parts = {};
        allok = true;
        if ~isempty(s1)
            [ok, m] = probe_one(s1, '示波器');
            parts{end + 1} = m; %#ok<AGROW>
            allok = allok && ok;
        end
        if ~isempty(s2)
            [ok, m] = probe_one(s2, '信号源');
            parts{end + 1} = m; %#ok<AGROW>
            allok = allok && ok;
        end
        stat.Text = strjoin(parts, '  |  ');
        if allok
            stat.FontColor = C.text;
        else
            stat.FontColor = C.warn;
        end
    end

    function do_save()
        s1 = edit_str(scope_e);
        s2 = edit_str(awg_e);
        if isempty(s1) || isempty(s2)
            uialert(fig, '示波器与信号源的 VISA 地址都不能为空。请先扫描。', 'PFC', 'Icon', 'warning');
            return;
        end
        if visa_same(s1, s2)
            uialert(fig, '示波器与信号源是同一台仪器（地址写法可能不同），不能保存。', 'PFC', 'Icon', 'warning');
            return;
        end
        tx = round(tx_sp.Value);
        pcd = round(pcd_sp.Value);
        aw = round(awg_sp.Value);
        if tx == pcd
            uialert(fig, '回读通道与 PCD 通道不能相同。', 'PFC', 'Icon', 'warning');
            return;
        end
        cfg.scope_visa = s1;
        cfg.awg_visa = s2;
        cfg.scope_tx_channel = tx;
        cfg.scope_pcd_channel = pcd;
        cfg.awg_channel = aw;
        try
            rigol_instr_config('save', cfg);
            pfc_visa('close');
        catch err
            uialert(fig, err.message, '仪器设置', 'Icon', 'error');
            return;
        end
        delete(fig);
    end
end

% ------------------------------------------------------------ 局部工具

function s = edit_str(h)
s = strtrim(char(string(h.Value)));
end

function set_list_items(list, items)
% 先换成占位再赋新列表：旧 Value 不在新 Items 里时 uilistbox 会直接报错。
placeholder = {' '};
try
    list.Items = placeholder;
    list.Value = placeholder{1};
catch
end
list.Items = items;
if ~isempty(items)
    try
        list.Value = items{1};
    catch
    end
end
end

function tf = visa_same(a, b)
na = rigol_visa_norm(a);
nb = rigol_visa_norm(b);
tf = ~isempty(na) && strcmpi(na, nb);
end

function idx = selected_index(list, devs)
idx = [];
val = list.Value;
if iscell(val)
    if isempty(val)
        return;
    end
    val = val{1};
end
items = list.Items;
if ischar(items) || isstring(items)
    items = cellstr(string(items));
end
k = find(strcmp(items, char(string(val))), 1);
if isempty(k) || k > numel(devs)
    return;
end
idx = k;
end

function [ok, msg] = probe_one(addr, who)
ok = false;
dev = [];
try
    dev = visadev(addr);
    dev.Timeout = 3;
    idn = strtrim(char(writeread(dev, '*IDN?')));
    if isempty(idn)
        msg = sprintf('%s：无 *IDN? 应答', who);
    else
        ok = true;
        msg = sprintf('%s OK  %s', who, idn);
    end
catch e
    msg = sprintf('%s失败：%s', who, short_ui_err(e.message));
end
try
    if ~isempty(dev)
        delete(dev);
    end
catch
end
end

function s = short_ui_err(msg)
s = regexprep(char(string(msg)), '<[^>]+>', '');
s = strtrim(regexprep(s, '\s+', ' '));
if numel(s) > 80
    s = [s(1:77) '...'];
end
end

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

function h = mk_btn(parent, C, fn, str, face, cb)
h = uibutton(parent, 'Text', str, 'ButtonPushedFcn', cb, ...
    'BackgroundColor', face, 'FontColor', C.btnFg, ...
    'FontName', fn, 'FontSize', 11, 'FontWeight', 'bold');
end

function ed = mk_addr_row(g, C, fn, row, label, val)
rowg = uigridlayout(g, [1 2]);
rowg.Layout.Row = row;
rowg.BackgroundColor = C.fig;
rowg.Padding = [0 0 0 0];
rowg.ColumnWidth = {70, '1x'};
rowg.ColumnSpacing = 8;
uilabel(rowg, 'Text', label, 'FontColor', C.text, 'FontName', fn, 'FontSize', 11);
ed = uieditfield(rowg, 'text', 'Value', val, ...
    'FontName', fn, 'FontSize', 11, ...
    'BackgroundColor', C.editBg, 'FontColor', C.editFg);
end

function sp = mk_spin(parent, C, fn, val, lim)
if ~(isfinite(val) && val >= lim(1) && val <= lim(2))
    val = lim(1);
end
sp = uispinner(parent, 'Value', val, 'Limits', lim, 'RoundFractionalValues', 'on', ...
    'FontName', fn, 'FontSize', 11, ...
    'BackgroundColor', C.editBg, 'FontColor', C.editFg);
end

function n = ui_font()
if ismac
    n = 'PingFang SC';
else
    n = 'Microsoft YaHei UI';
end
end
