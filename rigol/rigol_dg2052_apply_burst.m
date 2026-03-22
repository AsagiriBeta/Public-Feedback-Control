function rigol_dg2052_apply_burst(dev, ch, freq_mhz, ampl_mVpp, ~, n_cycle, period_s)
%RIGOL_DG2052_APPLY_BURST 配置正弦猝发：载波、猝发周期、每个猝发的周期数（DG2000 系列 SCPI）。
% ampl_mVpp: 毫伏峰峰值；period_s: 猝发重复周期 (= 1/PRF)。
src = sprintf('SOURce%d', ch);
freq_hz = freq_mhz * 1e6;
vpp = ampl_mVpp / 1000;

writeline(dev, [':' src ':FUNCtion SINusoid']);
writeline(dev, sprintf(':%s:FREQuency %.12g', src, freq_hz));
writeline(dev, sprintf(':%s:VOLTage:UNIT VPP', src));
writeline(dev, sprintf(':%s:VOLTage %.12g', src, vpp));
writeline(dev, sprintf(':%s:PHASe 0', src));

writeline(dev, sprintf(':%s:BURSt:STATe ON', src));
writeline(dev, sprintf(':%s:BURSt:MODE TRIGgered', src));
writeline(dev, sprintf(':%s:BURSt:NCYCles %d', src, max(1, round(n_cycle))));
writeline(dev, sprintf(':%s:BURSt:TRIGger:SOURce INTernal', src));

cmd1 = sprintf(':%s:BURSt:INTernal:PERiod %.12g', src, period_s);
cmd2 = sprintf(':%s:BURSt:PERiod %.12g', src, period_s);
try
    writeline(dev, cmd1);
catch
    writeline(dev, cmd2);
end

out = sprintf('OUTPut%d', ch);
writeline(dev, [':' out ':LOAD INF']);
end
