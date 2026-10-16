function info = rigol_dho814_setup(dev, targetFs, npts, ~, trigLevel, sweep, burst_s)
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

% 先把存储深度降到两通道都合法的档，再开通道。DHO814 单通道可以停在 25M，
% 这时再打开第二路，示波器会报远程指令错误。
safeMd = rigol_dho814_pick_mdepth(npts);
if strcmp(safeMd, '25M')
    safeMd = '10M';
end
safeScale = (npts / targetFs) / 10;
% 时基和内存用原来能采的档。1M 内存和数毫秒的时基偏移这台示波器会拒绝，
% 屏幕就挂「远程指令错误」，而且每次都会退回这一档。
mdTag = safeMd;
scale = safeScale;
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
end

function v = qnum(dev, cmd)
%QNUM 查询一个数值；仪器/固件不支持该查询时给 NaN，不要因此把整轮采集打断
v = NaN;
try
    v = str2double(rigol_visa_query(dev, cmd));
catch
end
end
