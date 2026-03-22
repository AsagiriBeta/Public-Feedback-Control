function info = rigol_dho814_setup(dev, targetFs, npts, ch)
%RIGOL_DHO814_SETUP 按目标采样长度配置水平时基、存储深度与边沿触发（DHO800 SCPI）。
% targetFs: 期望平均采样率 [Hz]（由时基与存储深度共同决定，实际值见 ACQuire:SRATe?）
if nargin < 4 || isempty(ch)
    ch = rigol_instr_config().scope_channel;
end

chan = sprintf('CHANnel%d', ch);
writeline(dev, sprintf(':%s:DISPlay ON', chan));
writeline(dev, sprintf(':%s:COUPling DC', chan));

mdTag = rigol_dho814_pick_mdepth(npts);
writeline(dev, [':ACQuire:MDEPth ' mdTag]);
writeline(dev, ':ACQuire:TYPE NORMal');

t_total = npts / targetFs;
scale = t_total / 10;
writeline(dev, sprintf(':TIMebase:MAIN:SCALe %.12g', scale));
writeline(dev, ':TIMebase:HREFerence:MODE LB');

writeline(dev, ':TRIGger:MODE EDGE');
writeline(dev, sprintf(':TRIGger:EDGE:SOURce %s', chan));
writeline(dev, ':TRIGger:EDGE:SLOPe POSitive');
writeline(dev, sprintf(':TRIGger:EDGE:LEVel 0.01'));
writeline(dev, ':TRIGger:SWEep SINGle');

writeline(dev, ':RUN');

realFs = str2double(rigol_visa_query(dev, ':ACQuire:SRATe?'));
info.timeIntervalNanoSeconds = (1 / realFs) * 1e9;
info.realFs = realFs;
info.scope_channel = ch;
end
