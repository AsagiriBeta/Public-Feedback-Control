function info = rigol_dho814_setup(dev, targetFs, npts, ~, trigLevel, sweep, burst_s, f0_hz)
%RIGOL_DHO814_SETUP 打开回读通道 + PCD 通道（通道号在仪器配置里，不写死 CH1/CH2）。
% sweep: 'SINGle' 闭环逐发对齐；'AUTO' 调试时屏幕保持滚动。
cfg = rigol_instr_config();
tx  = cfg.scope_tx_channel;
pcd = cfg.scope_pcd_channel;
trigCh = tx;
if isfield(cfg, 'scope_trig_channel')
    tc = round(cfg.scope_trig_channel);
    if tc >= 1 && tc <= 4
        trigCh = tc;
    end
end
% 触发接在另一路（发生器后面板 → CH4）时，电平是 TTL 的 1.5 V。
% 回读通道那套零点几毫伏永远跨不过 3 V 脉冲。
ttlTrig = trigCh ~= tx;
if nargin < 5 || isempty(trigLevel)
    trigLevel = 0.005;
end
if ttlTrig
    trigLevel = 1.5;
end
if nargin < 6 || isempty(sweep)
    sweep = 'SINGle';
end
if nargin < 7 || isempty(burst_s) || ~isfinite(burst_s) || burst_s <= 0
    burst_s = [];
end

% 清掉上一轮留在屏幕上的远程指令错误。
try, writeline(dev, '*CLS'); catch, end

% 采集几何：由「猝发长度 + 分析频带 + 传输预算」反推深度档与时基，不写死 npts/40e6。
% 改之前 scale = (npts/targetFs)/10，记录长度与这一发多长无关：猝发 0.27 ms 时
% 窗口里 3.7 倍是空档（signal_span 得在空档里找包络，acq_n 逐帧抖），猝发 6.6 ms
% 时窗根本装不下、静默截断。而 realFs = 深度档/记录长度 = 100k/1ms = 100 MSa/s，
% 比设计的 40 MSa/s 多采 2.5 倍。详见 rigol_dho814_capture_geometry。
geom = [];
if nargin < 8 || isempty(f0_hz) || ~isfinite(f0_hz) || f0_hz <= 0
    f0_hz = 1.5e6;   % 与 pcd_cav_bands 的默认一致
end
try
    L = pcd_param_limits();
    npts_max = L.npts_max;
catch
    npts_max = 1e5;
end
lead_s = 3e-3;
if isfield(cfg, 'scope_lead_s') && isnumeric(cfg.scope_lead_s) && isfinite(cfg.scope_lead_s) && cfg.scope_lead_s >= 0
    lead_s = double(cfg.scope_lead_s);
end

if isfinite(burst_s) && burst_s > 0
    geom = rigol_dho814_capture_geometry(burst_s, f0_hz, targetFs, npts, npts_max, lead_s);
    if ~geom.ok
        error('rigol:dho814:geometry', '%s', geom.reason);
    end
end

if isempty(geom)
    % 没有猝发长度（CW 调试 / 单次看波形）：沿用旧的 npts/targetFs 定标，不改调试路径行为。
    mdTag = rigol_dho814_pick_mdepth(npts);
    if strcmp(mdTag, '25M')
        mdTag = '10M';
    end
    scale = (npts / targetFs) / 10;
else
    mdTag = geom.depth_tag;
    scale = geom.scale_s_per_div;
end
% 时基偏移保持 0：这台固件的 1M 内存和数毫秒的时基偏移会拒绝，屏幕挂「远程指令错误」。
writeline(dev, [':ACQuire:MDEPth ' mdTag]);

% 只打开要用的两路，不要 DISPlay OFF。触发源还停在旧通道（常常是坏掉的 CH1）时，
% 关掉那一路是设置冲突，屏幕会一直挂着「远程指令错误」。不用的通道留在示波器上即可。
for ch = [tx, pcd]
    chan = sprintf('CHANnel%d', ch);
    writeline(dev, sprintf(':%s:DISPlay ON', chan));
    writeline(dev, sprintf(':%s:COUPling AC', chan));
    writeline(dev, sprintf(':%s:OFFSet 0', chan));
end
writeline(dev, sprintf(':CHANnel%d:SCALe 0.05', tx));
writeline(dev, sprintf(':CHANnel%d:SCALe 0.05', pcd));
if ttlTrig
    % BNC 直连，不是 10× 探头。直流耦合才能稳住 TTL 的高电平。
    chan = sprintf('CHANnel%d', trigCh);
    writeline(dev, sprintf(':%s:DISPlay ON', chan));
    writeline(dev, sprintf(':%s:COUPling DC', chan));
    writeline(dev, sprintf(':%s:OFFSet 0', chan));
    writeline(dev, sprintf(':%s:SCALe 1', chan));
    writeline(dev, sprintf(':%s:PROBe 1', chan));
end

writeline(dev, ':ACQuire:TYPE NORMal');

writeline(dev, sprintf(':TIMebase:MAIN:SCALe %.12g', scale));
writeline(dev, ':TIMebase:HREFerence:MODE LB');
% 先归零。这台机器上非零时基偏移会让后面的波形读传不完。
writeline(dev, ':TIMebase:MAIN:OFFSet 0');

trigChan = sprintf('CHANnel%d', trigCh);
writeline(dev, ':TRIGger:MODE EDGE');
writeline(dev, sprintf(':TRIGger:EDGE:SOURce %s', trigChan));
writeline(dev, ':TRIGger:EDGE:SLOPe POSitive');
writeline(dev, sprintf(':TRIGger:EDGE:LEVel %.8g', trigLevel));
if ttlTrig
    writeline(dev, ':TRIGger:COUPling DC');
end
writeline(dev, sprintf(':TRIGger:SWEep %s', sweep));

% 记录 RAW 模式下的波形几何。XORigin 尤为重要：手册 3.28.7 写明「RAW 模式下返回
% **内存**中波形数据的起始时间」——屏幕窗与内存记录不重合时，第 1 个采样点就不在
% 触发点上，这本身就能造成一个固定偏移，而且归零 :TIMebase:MAIN:OFFSet 治不了它。
% 存下来，「猝发为什么落在窗内某处」才是有据可查而不是靠猜。
writeline(dev, sprintf(':WAVeform:SOURce CHANnel%d', tx));
writeline(dev, ':WAVeform:MODE RAW');
% 文献里 Pico 是「触发前 0 点、触发后恰好一个脉冲」。这台 DHO814 做不到把触发点
% 挪到记录开头：写 :WAVeform:STARt/:STOP 必回 -200（屏幕就挂远程指令执行错误），
% 时基偏移写进去后波形块又会传不完，而且脉冲不在 XORigin 指的那个点上。
% 偏移保持 0。触发在 8 ms 记录正中，触发后大约 4 ms，两路裁同一段，不超过脉冲。
info.wf_xorigin_s = qnum(dev, ':WAVeform:XORigin?');
info.wf_xref      = qnum(dev, ':WAVeform:XREFerence?');
info.wf_yorigin   = qnum(dev, ':WAVeform:YORigin?');
info.wf_yref      = qnum(dev, ':WAVeform:YREFerence?');
info.wf_yinc      = qnum(dev, ':WAVeform:YINCrement?');

writeline(dev, ':RUN');

realFs = str2double(rigol_visa_query(dev, ':ACQuire:SRATe?'));
try, writeline(dev, '*CLS'); catch, end
info.timeIntervalNanoSeconds = (1 / realFs) * 1e9;
info.realFs = realFs;
info.scope_channel = pcd;
info.scope_tx_channel = tx;
info.scope_pcd_channel = pcd;
info.scope_trig_channel = trigCh;
% 回读实际生效的水平偏移，随数据一起存下去 —— 采集窗对齐情况要能事后追溯
info.time_offset_s = qnum(dev, ':TIMebase:MAIN:OFFSet?');
info.waveform_format = 'WORD';
% 采集几何留档：acq_n 是「这一发本身」的点数（burst_s × fs），每帧固定，
% 不再由某一帧的裁剪结果决定 —— 频谱幅值不随帧长抖动就靠它。
if isempty(geom)
    info.geom_ok = false;
    info.depth_tag = mdTag;
    info.record_s = 10 * scale;
    info.acq_n = NaN;
    info.fs_planned = NaN;
else
    info.geom_ok = true;
    info.depth_tag = geom.depth_tag;
    info.record_s = geom.record_s;
    info.acq_n = geom.acq_n;
    info.fs_planned = geom.fs;
    info.fs_target = geom.fs_target;
    info.fs_min = geom.fs_min;
    info.nyquist_margin = geom.nyquist_hz / geom.band_max_hz;
    info.transfer_bytes = geom.transfer_bytes;
    info.geom_note = geom.note;
end
end

function v = qnum(dev, cmd)
%QNUM 查询一个数值；仪器/固件不支持该查询时给 NaN，不要因此把整轮采集打断
v = NaN;
try
    v = str2double(rigol_visa_query(dev, cmd));
catch
end
end
