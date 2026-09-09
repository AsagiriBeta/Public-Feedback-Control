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
end
