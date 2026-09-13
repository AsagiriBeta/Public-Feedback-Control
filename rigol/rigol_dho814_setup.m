function info = rigol_dho814_setup(dev, targetFs, npts, ~, trigLevel, sweep)
%RIGOL_DHO814_SETUP 打开 CH1 回读 + CH2 PCD。
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

for ch = [tx, pcd]
    chan = sprintf('CHANnel%d', ch);
    writeline(dev, sprintf(':%s:DISPlay ON', chan));
    writeline(dev, sprintf(':%s:COUPling AC', chan));
    writeline(dev, sprintf(':%s:OFFSet 0', chan));
end
writeline(dev, sprintf(':CHANnel%d:SCALe 0.05', tx));
writeline(dev, sprintf(':CHANnel%d:SCALe 0.05', pcd));

mdTag = rigol_dho814_pick_mdepth(npts);
writeline(dev, [':ACQuire:MDEPth ' mdTag]);
writeline(dev, ':ACQuire:TYPE NORMal');

t_total = npts / targetFs;
scale = t_total / 10;
writeline(dev, sprintf(':TIMebase:MAIN:SCALe %.12g', scale));
writeline(dev, ':TIMebase:HREFerence:MODE LB');
% 水平偏移必须显式归零。以前从不设置它，用的是仪器残留状态：实测某轮 92 帧里
% 猝发起点一致落在窗内 1.180 ms 处（1 ms 的猝发只有 0.42 ms 进窗，零抖动）。
% 后果是 SC/IC 被占空比稀释约 11 dB，而且稀释系数取决于一个不受控的参数 ——
% 标定会随仪器状态漂。归零后（参考点=左）触发点落在窗左端，整段猝发进窗。
writeline(dev, ':TIMebase:MAIN:OFFSet 0');

trigChan = sprintf('CHANnel%d', tx);
writeline(dev, ':TRIGger:MODE EDGE');
writeline(dev, sprintf(':TRIGger:EDGE:SOURce %s', trigChan));
writeline(dev, ':TRIGger:EDGE:SLOPe POSitive');
writeline(dev, sprintf(':TRIGger:EDGE:LEVel %.8g', trigLevel));
writeline(dev, sprintf(':TRIGger:SWEep %s', sweep));

writeline(dev, ':RUN');

realFs = str2double(rigol_visa_query(dev, ':ACQuire:SRATe?'));
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
