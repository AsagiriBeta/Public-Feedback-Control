function info = rigol_dho814_setup(dev, targetFs, npts, ~, trigLevel, sweep, burst_s)
%RIGOL_DHO814_SETUP 打开回读通道 + PCD 通道（通道号在仪器配置里，不写死 CH1/CH2）。
% sweep: 'SINGle' 闭环逐发对齐；'AUTO' 调试时屏幕保持滚动。
cfg = rigol_instr_config();
tx  = cfg.scope_tx_channel;
pcd = cfg.scope_pcd_channel;
if nargin < 5 || isempty(trigLevel)
    trigLevel = 0.005;
end
if nargin < 6 || isempty(sweep)
    sweep = 'SINGle';
end
if nargin < 7 || isempty(burst_s) || ~isfinite(burst_s) || burst_s <= 0
    burst_s = [];
end

% 清掉上一轮留在屏幕上的远程指令错误。
try, writeline(dev, '*CLS'); catch, end

% 先把存储深度降到两通道都合法的档，再开通道。DHO814 单通道可以停在 25M，
% 这时再打开第二路，示波器会报远程指令错误。
mdTag = rigol_dho814_pick_mdepth(npts);
if strcmp(mdTag, '25M')
    mdTag = '10M';
end
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

writeline(dev, ':ACQuire:TYPE NORMal');

t_total = npts / targetFs;
scale = t_total / 10;
writeline(dev, sprintf(':TIMebase:MAIN:SCALe %.12g', scale));
writeline(dev, ':TIMebase:HREFerence:MODE LB');
% 水平偏移必须显式归零。以前从不设置它，用的是仪器残留状态：实测某轮 92 帧里
% 1 ms 的猝发只有 0.42 ms 落在窗内（猝发起点一致在 1.180 ms、零抖动），
% 后果是 SC/IC 被占空比稀释约 11 dB，而且稀释系数取决于一个不受控的参数。
%
% 注意：上面那行 HREFerence:MODE LB 是**缩放锚点**——手册 3.26.7 写明它是「改变水平
% 时基时，围绕屏幕左侧扩展或压缩波形」，管的是缩放，**不能**用来推理触发点落在窗内
% 哪个位置。所以归零后触发点到底在哪，仍需实测：采集时会跑一次 check_burst_window
% 把结果打进日志并存进数据（burst_align），RAW 模式下的波形几何见下面 wf_* 字段。
writeline(dev, ':TIMebase:MAIN:OFFSet 0');

trigChan = sprintf('CHANnel%d', tx);
writeline(dev, ':TRIGger:MODE EDGE');
writeline(dev, sprintf(':TRIGger:EDGE:SOURce %s', trigChan));
writeline(dev, ':TRIGger:EDGE:SLOPe POSitive');
writeline(dev, sprintf(':TRIGger:EDGE:LEVel %.8g', trigLevel));
writeline(dev, sprintf(':TRIGger:SWEep %s', sweep));

% 记录 RAW 模式下的波形几何。XORigin 尤为重要：手册 3.28.7 写明「RAW 模式下返回
% **内存**中波形数据的起始时间」——屏幕窗与内存记录不重合时，第 1 个采样点就不在
% 触发点上，这本身就能造成一个固定偏移，而且归零 :TIMebase:MAIN:OFFSet 治不了它。
% 存下来，「猝发为什么落在窗内某处」才是有据可查而不是靠猜。
writeline(dev, sprintf(':WAVeform:SOURce CHANnel%d', pcd));
writeline(dev, ':WAVeform:MODE RAW');
info.wf_xorigin_s = qnum(dev, ':WAVeform:XORigin?');
info.wf_xref      = qnum(dev, ':WAVeform:XREFerence?');
info.wf_yorigin   = qnum(dev, ':WAVeform:YORigin?');
info.wf_yref      = qnum(dev, ':WAVeform:YREFerence?');
info.wf_yinc      = qnum(dev, ':WAVeform:YINCrement?');

writeline(dev, ':RUN');

realFs = str2double(rigol_visa_query(dev, ':ACQuire:SRATe?'));
% 内存以触发点为中心。100k 点、12.5 MHz 时一共 8 ms，触发后只有 4 ms，
% 6.7 ms 脉冲的后半段不在内存里，读 RAW 还会带上触发前的空档。
% 把深度加到「触发后仍盖住整段脉冲」，读的时候再从触发点起截。不拉长时基，
% 避免采样率掉到看不到 6 MHz。
if ~isempty(burst_s) && isfinite(realFs) && realFs > 0
    n_need = max(npts, ceil(2.15 * burst_s * realFs));
    tag2 = rigol_dho814_pick_mdepth(n_need);
    if strcmp(tag2, '25M')
        tag2 = '10M';
    end
    if ~strcmp(tag2, mdTag)
        writeline(dev, [':ACQuire:MDEPth ' tag2]);
        fprintf(['内存深度 %s → %s：触发在记录中点时，触发后仍盖住 %.2f ms 脉冲。\n'], ...
            mdTag, tag2, burst_s * 1e3);
    end
end
info.timeIntervalNanoSeconds = (1 / realFs) * 1e9;
info.realFs = realFs;
info.scope_channel = pcd;
info.scope_tx_channel = tx;
info.scope_pcd_channel = pcd;
% 回读实际生效的水平偏移，随数据一起存下去 —— 采集窗对齐情况要能事后追溯
info.time_offset_s = qnum(dev, ':TIMebase:MAIN:OFFSet?');
info.waveform_format = 'WORD';
end

function v = qnum(dev, cmd)
%QNUM 查询一个数值；仪器/固件不支持该查询时给 NaN，不要因此把整轮采集打断
v = NaN;
try
    v = str2double(rigol_visa_query(dev, cmd));
catch
end
end
