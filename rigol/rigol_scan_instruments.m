function [devs, msg] = rigol_scan_instruments(varargin)
%RIGOL_SCAN_INSTRUMENTS 自动扫描本机 VISA 资源并识别仪器（「仪器设置」的自动检测用）。
%
%   devs = rigol_scan_instruments()
%   devs = rigol_scan_instruments('probe', false)   % 只列资源，不逐个发 *IDN?
%   [devs, msg] = rigol_scan_instruments()
%
% 返回结构体数组（已按「最像示波器/信号源」排序），字段：
%   visa    VISA 资源名，可直接写进 rigol_instr_config
%   idn     *IDN? 原文（未探测或失败时为空）
%   vendor  厂商      model 型号      serial 序列号
%   role    'scope' | 'awg' | 'other' | 'unknown'
%   error   打开/查询失败原因（成功为空串）
%
% 第二个输出 msg 是给界面显示的一行摘要（含失败原因）。
%
% 为什么要先 pcd_visa('close')：扫描会**临时打开**资源做握手，本程序已占用的
% 示波器/信号源会被判成「资源被占用」。调用方负责先释放单例连接。
%
% 注意：串口（ASRL）发 *IDN? 可能长时间无响应，默认跳过（'probeASRL', true 可开）。
opts = struct('probe', true, 'timeout', 3, 'probeASRL', false);
for k = 1:2:numel(varargin)
    if ischar(varargin{k}) && isfield(opts, varargin{k})
        opts.(varargin{k}) = varargin{k + 1};
    end
end

devs = blank_dev();
devs(1) = [];                % 空数组，但字段完整
msg = '';

[raw, msg] = list_resources();
if isempty(raw)
    if isempty(msg)
        msg = '本机没有扫描到任何 VISA 资源。请检查 USB 线、仪器电源与 NI-VISA。';
    end
    return;
end

[names, meta] = rigol_visa_table(raw);
if isempty(names)
    msg = 'VISA 返回了资源列表，但没能解析出资源名。';
    return;
end

for i = 1:numel(names)
    d = blank_dev();
    d.visa = names{i};
    if numel(meta) >= i
        d.vendor = meta(i).vendor;
        d.model = meta(i).model;
        d.serial = meta(i).serial;
    end
    if isempty(d.serial)
        d.serial = serial_from_visa(d.visa);
    end
    if opts.probe && can_probe(d.visa, opts.probeASRL)
        [ok, idn, err] = probe_idn(d.visa, opts.timeout);
        if ok
            d.idn = idn;
            [v, m, s] = parse_idn(idn);
            if ~isempty(v), d.vendor = v; end
            if ~isempty(m), d.model = m; end
            if ~isempty(s), d.serial = s; end
        else
            d.error = err;
        end
    end
    d.role = classify(d);
    devs(end + 1) = d; %#ok<AGROW>
end

devs = sort_by_role(devs);
if isempty(msg)
    msg = sprintf('扫描到 %d 个 VISA 资源。', numel(devs));
end
end

% ---------------------------------------------------------------- 资源枚举

function [raw, msg] = list_resources()
raw = [];
msg = '';
hasFcn = exist('visadevlist', 'file') ~= 0 || exist('visadevlist', 'builtin') ~= 0;
if ~hasFcn
    msg = '未检测到 Instrument Control Toolbox（visadevlist），无法扫描仪器。';
    return;
end
try
    raw = visadevlist();
catch err
    msg = ['VISA 不可用：' short_err(err.message) ...
        '  请先安装 NI-VISA（或仪器厂商 VISA）再扫描。'];
end
end

% ---------------------------------------------------------------- 握手探测

function tf = can_probe(visaAddr, allowASRL)
u = upper(char(visaAddr));
if contains(u, 'ASRL') || contains(u, 'COM')
    tf = allowASRL;
else
    tf = true;
end
end

function [ok, idn, err] = probe_idn(visaAddr, tmo)
% 打开 → 发 *IDN? → 读一行 → 关闭。任何一步失败都只记录原因，不打断整轮扫描。
ok = false;
idn = '';
err = '';
dev = [];
try
    dev = visadev(visaAddr);
    dev.Timeout = tmo;
    writeline(dev, '*IDN?');
    idn = strtrim(char(readline(dev)));
    ok = ~isempty(idn);
    if ~ok
        err = '仪器没有返回 *IDN?';
    end
catch e
    err = short_err(e.message);
end
% clear 往往来不及释放 USB，下一台会被判「资源被占用」。delete 是同步关掉。
try
    if ~isempty(dev)
        delete(dev);
    end
catch
end
end

function [vendor, model, serial] = parse_idn(idn)
% 常见格式：RIGOL TECHNOLOGIES,DHO814,DHO8A274611769,00.01.02
vendor = '';
model = '';
serial = '';
p = strsplit(strtrim(char(idn)), ',');
if numel(p) >= 1, vendor = strtrim(p{1}); end
if numel(p) >= 2, model = strtrim(p{2}); end
if numel(p) >= 3, serial = strtrim(p{3}); end
end

function s = serial_from_visa(visaAddr)
% USB0::0x1AB1::0x044D::DHO8A274611769::0::INSTR → 第 4 段是序列号
s = '';
p = strsplit(char(visaAddr), '::');
if numel(p) >= 4
    s = strtrim(p{4});
end
end

% ---------------------------------------------------------------- 角色判定

function role = classify(d)
hay = lower([d.idn ' ' d.vendor ' ' d.model ' ' d.visa]);
if looks_scope(hay)
    role = 'scope';
elseif looks_awg(hay)
    role = 'awg';
elseif ~isempty(d.idn) || ~isempty(d.model)
    role = 'other';
else
    role = 'unknown';
end
end

function tf = looks_scope(h)
% DHO800/900、MSO/DS 系列；以及 RIGOL USB 型号码 0x044D（DHO800）
tf = contains(h, 'dho') || contains(h, 'mso') || contains(h, 'oscilloscope') ...
    || contains(h, 'ds10') || contains(h, 'ds20') || contains(h, '0x044d');
end

function tf = looks_awg(h)
% DG2000 系列；以及 RIGOL USB 型号码 0x0644（DG2000）
tf = contains(h, 'dg2') || contains(h, 'dg1') || contains(h, 'dg9') ...
    || contains(h, 'function generator') || contains(h, 'waveform generator') ...
    || contains(h, '0x0644');
end

function devs = sort_by_role(devs)
rank = zeros(1, numel(devs));
for i = 1:numel(devs)
    switch devs(i).role
        case 'scope'
            rank(i) = 0;
        case 'awg'
            rank(i) = 1;
        case 'other'
            rank(i) = 2;
        otherwise
            rank(i) = 3;
    end
end
[~, ord] = sort(rank);
devs = devs(ord);
end

function d = blank_dev()
d = struct('visa', '', 'idn', '', 'vendor', '', 'model', '', 'serial', '', ...
    'role', 'unknown', 'error', '');
end

function s = short_err(msg)
% 错误信息里常带 <a href="matlab:..."> 之类的 HTML，界面里显示很难看，去掉
s = regexprep(char(string(msg)), '<[^>]+>', '');
s = strtrim(regexprep(s, '\s+', ' '));
end
