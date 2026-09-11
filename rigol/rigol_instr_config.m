function varargout = rigol_instr_config(cmd, newcfg)
%RIGOL_INSTR_CONFIG 仪器 VISA 地址与采集参数（默认值 + 本地覆盖文件）。
%
%   cfg = rigol_instr_config()        读取当前配置（默认值叠加本地覆盖）
%         rigol_instr_config('save', cfg)  写入本地覆盖文件
%         rigol_instr_config('reset')      删除本地覆盖，回到默认
%   p   = rigol_instr_config('file')  本地覆盖文件路径
%   d   = rigol_instr_config('defaults') 出厂默认配置
%
% 为什么要有本地覆盖：打包成 exe 后无法改源码，而 VISA 地址每台机器都不一样。
% 覆盖文件是纯文本 ini（<工作根>/rigol_config.ini），可用界面的「仪器设置」修改，
% 也可直接编辑。换仪器后在 MATLAB 执行 visadevlist 可查 ResourceName。
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
    otherwise
        error('rigol:config:cmd', '未知命令 %s', cmd);
end
end

function cfg = defaults()
% 本实验室默认值（macOS 上抓到的地址）；换机器请用「仪器设置」或改 ini。
cfg.scope_visa = 'USB0::0x1AB1::0x044D::DHO8A274611769::0::INSTR';
cfg.awg_visa   = 'USB0::0x1AB1::0x0644::DG2P273601178::0::INSTR';

cfg.scope_tx_channel  = 1;   % 发生器回读
cfg.scope_pcd_channel = 2;   % PCD
cfg.scope_channel     = 2;   % 兼容旧代码：默认采 PCD
cfg.awg_channel       = 1;

cfg.acquire_timeout_s = 12;

cfg.harmonic_bandwidth_hz = 20e3;  % Chien 2022：SC/IC 均为 ±20 kHz
end

function f = cfg_file()
f = fullfile(pfc_root(), 'rigol_config.ini');
end

function cfg = merged()
cfg = defaults();
f = cfg_file();
if ~isfile(f)
    return;
end
% 只接受白名单键，避免误改内部字段
numKeys = {'scope_tx_channel', 'scope_pcd_channel', 'awg_channel', 'acquire_timeout_s', ...
    'harmonic_bandwidth_hz'};
strKeys = {'scope_visa', 'awg_visa'};
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
    '# PFC 仪器配置（本地覆盖，不入 git）\n' ...
    '# 换仪器：先在 MATLAB 执行 visadevlist，把 ResourceName 填到下面。\n' ...
    '# 也可用界面上的「仪器设置」按钮修改。删除本文件即回到默认。\n' ...
    'scope_visa=%s\n' ...
    'awg_visa=%s\n' ...
    'scope_tx_channel=%g\n' ...
    'scope_pcd_channel=%g\n' ...
    'awg_channel=%g\n'], ...
    char(cfg.scope_visa), char(cfg.awg_visa), ...
    cfg.scope_tx_channel, cfg.scope_pcd_channel, cfg.awg_channel);
fid = fopen(f, 'w');
if fid < 0
    error('rigol:config:write', '无法写入配置文件：%s', f);
end
fprintf(fid, '%s', txt);
fclose(fid);
end
