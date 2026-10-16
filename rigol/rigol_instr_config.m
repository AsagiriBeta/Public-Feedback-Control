function varargout = rigol_instr_config(cmd, newcfg)
%RIGOL_INSTR_CONFIG 仪器 VISA 地址与采集参数（默认值 + 本地覆盖文件）。
%
%   cfg = rigol_instr_config()        读取当前配置（默认值叠加本地覆盖）
%         rigol_instr_config('save', cfg)  写入本地覆盖文件
%         rigol_instr_config('reset')      删除本地覆盖，回到默认
%   p   = rigol_instr_config('file')  本地覆盖文件路径
%   d   = rigol_instr_config('defaults') 出厂默认配置
%   cfg = rigol_instr_config('autodetect') 扫描 VISA 资源，返回填好地址的建议配置（不落盘）
%         % 用法：cfg = rigol_instr_config('autodetect'); rigol_instr_config('save', cfg);
%
% 为什么要有本地覆盖：打包成 exe 后无法改源码，而 VISA 地址每台机器都不一样。
% 覆盖文件是纯文本 ini（<工作根>/rigol_config.ini），可用界面的「仪器设置」修改，
% 也可直接编辑。默认地址为空，换仪器后扫描即可，不必改源码。
if nargin < 1
    cmd = 'get';
end

switch lower(cmd)
    case 'get'
        varargout{1} = merged();
    case 'defaults'
        varargout{1} = defaults();
    case 'save'
        if nargin < 2 || ~isstruct(newcfg)
            error('rigol:config:save', 'save 需要传入配置结构体。');
        end
        write_ini(newcfg);
    case 'reset'
        f = cfg_file();
        if isfile(f)
            delete(f);
        end
    case 'file'
        varargout{1} = cfg_file();
    case 'autodetect'
        varargout{1} = autodetect();
    otherwise
        error('rigol:config:cmd', '未知命令 %s', cmd);
end
end

function cfg = autodetect()
%AUTODETECT 扫描 VISA 资源，把识别到的示波器/信号源填进配置（只覆盖识别到的那一项，
% 另一项保留原值，避免把手工调好的地址清掉）。结果需要调用方自己 save。
cfg = merged();
devs = rigol_scan_instruments();
sc = pick_dev(devs, 'scope');
aw = pick_dev(devs, 'awg');
if ~isempty(sc)
    cfg.scope_visa = sc;
end
if ~isempty(aw)
    cfg.awg_visa = aw;
end
cfg.detected = struct('n', numel(devs), 'scope', sc, 'awg', aw); % 仅作报告，write_ini 会忽略
end

function v = pick_dev(devs, role)
v = '';
for i = 1:numel(devs)
    if strcmp(devs(i).role, role)
        v = devs(i).visa;
        return;
    end
end
end

function cfg = defaults()
% 地址默认留空：换电脑不能带着别人的序列号。第一次用先「仪器设置 → 扫描」。
cfg.scope_visa = '';
cfg.awg_visa   = '';

cfg.scope_tx_channel  = 1;   % 发生器回读（示波器通道，CH1 坏了可改成 2–4）
cfg.scope_pcd_channel = 2;   % PCD
cfg.scope_channel     = 2;   % 兼容旧代码：默认采 PCD
cfg.scope_trig_channel = 0;  % 0 = 用回读通道触发；1–4 = 单独的触发通道（发生器后面板接到这一路）
cfg.awg_channel       = 1;
% computer：电脑控制 DG2052，可闭环。manual：另一台发生器手调，电脑不连、不闭环。
cfg.awg_mode          = 'computer';

cfg.acquire_timeout_s = 12;

cfg.scope_vdiv = 8;                % 竖直方向格数：波形以 0 V 居中 -> 满量程 ±(vdiv/2)×SCALe
                                   % 削顶判定（rigol_dho814_clipped）要用它，别乱改

cfg.harmonic_bandwidth_hz = 20e3;  % Chien 2022：SC/IC 均为 ±20 kHz

% 采集窗里「猝发之前」要留多长空档 (s)。这台机器的 XORigin 会落在真正跳变前
% 1–3 ms（见 rigol_dho814_setup 里的实测记录），记录不预留这段就会把猝发尾部切掉。
% rigol_dho814_capture_geometry 用它定时基刻度，所以这个值直接决定采样率：
% 留得越多，装下这一发需要的点数越多，fs 越低。默认取实测上界 3 ms 保守起步；
% 跑一轮后看日志里的「实测前置空档」，按实测值调小，fs 会立刻回升。
cfg.scope_lead_s = 3e-3;
end

function f = cfg_file()
f = fullfile(pcd_root(), 'rigol_config.ini');
end

function cfg = merged()
cfg = defaults();
f = cfg_file();
if ~isfile(f)
    return;
end
% 只接受白名单键，避免误改内部字段
numKeys = {'scope_tx_channel', 'scope_pcd_channel', 'scope_trig_channel', 'awg_channel', 'acquire_timeout_s', ...
    'harmonic_bandwidth_hz', 'scope_vdiv', 'scope_lead_s'};
strKeys = {'scope_visa', 'awg_visa', 'awg_mode'};
try
    lines = splitlines(fileread(f));
catch
    return;
end
for i = 1:numel(lines)
    ln = strtrim(lines{i});
    if isempty(ln) || startsWith(ln, '#') || startsWith(ln, ';')
        continue;
    end
    parts = strsplit(ln, '=', 'CollapseDelimiters', false);
    if numel(parts) < 2
        continue;
    end
    key = strtrim(parts{1});
    val = strtrim(strjoin(parts(2:end), '='));   % VISA 地址里可能含 '='（一般不会）
    if any(strcmp(key, numKeys))
        n = str2double(val);
        if isfinite(n)
            cfg.(key) = n;
        end
    elseif any(strcmp(key, strKeys))
        if ~isempty(val)
            cfg.(key) = val;
        end
    end
end
cfg.scope_channel = cfg.scope_pcd_channel;   % 保持一致
end

function write_ini(cfg)
f = cfg_file();
d = defaults();
for fn = fieldnames(d)'
    if ~isfield(cfg, fn{1})
        cfg.(fn{1}) = d.(fn{1});
    end
end
txt = sprintf([ ...
    '# PCD 仪器配置（本地覆盖，不入 git）\n' ...
    '# 换仪器：界面点「仪器设置 → 扫描仪器」，或 visadevlist 后把 ResourceName 填到下面。\n' ...
    '# 删除本文件即回到空地址（必须重新扫描）。保存时会写下全部可配字段。\n' ...
    'scope_visa=%s\n' ...
    'awg_visa=%s\n' ...
    'awg_mode=%s\n' ...
    'scope_tx_channel=%g\n' ...
    'scope_pcd_channel=%g\n' ...
    'scope_trig_channel=%g\n' ...
    'awg_channel=%g\n' ...
    'acquire_timeout_s=%g\n' ...
    'harmonic_bandwidth_hz=%g\n' ...
    'scope_vdiv=%g\n' ...
    'scope_lead_s=%.12g\n'], ...
    char(cfg.scope_visa), char(cfg.awg_visa), awg_mode_of(cfg), ...
    cfg.scope_tx_channel, cfg.scope_pcd_channel, cfg.scope_trig_channel, cfg.awg_channel, ...
    cfg.acquire_timeout_s, cfg.harmonic_bandwidth_hz, cfg.scope_vdiv, cfg.scope_lead_s);
fid = fopen(f, 'w');
if fid < 0
    error('rigol:config:write', '无法写入配置文件：%s', f);
end
fprintf(fid, '%s', txt);
fclose(fid);
end

function m = awg_mode_of(cfg)
m = 'computer';
if isfield(cfg, 'awg_mode') && strcmpi(strtrim(char(string(cfg.awg_mode))), 'manual')
    m = 'manual';
end
end
