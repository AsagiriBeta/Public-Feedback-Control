function rigol_dg2052_apply_burst(dev, ch, freq_mhz, ampl_mVpp, phase_deg, n_cycle, period_s)
%RIGOL_DG2052_APPLY_BURST 配置正弦猝发：载波、猝发周期、每个猝发的周期数（DG2000 编程手册）。
% ampl_mVpp: 毫伏峰峰值；period_s: 猝发重复周期 (= 1/PRF)；phase_deg: 载波起始相位（°）。
% 猝发参数全部就绪后再开 BURSt:STATe（手册建议，减少波形反复切换）。
if ~(isscalar(period_s) && isnumeric(period_s) && isfinite(period_s) && period_s > 0)
    error('rigol:dg2052:period', 'period_s 须为有限正标量（猝发周期 = 1/PRF）。');
end
src = sprintf('SOURce%d', ch);
freq_hz = freq_mhz * 1e6;
vpp = ampl_mVpp / 1000;
nc = max(1, round(n_cycle));

writeline(dev, [':' src ':FUNCtion SINusoid']);
writeline(dev, sprintf(':%s:FREQuency %.12g', src, freq_hz));
writeline(dev, sprintf(':%s:VOLTage:UNIT VPP', src));
writeline(dev, sprintf(':%s:VOLTage %.12g', src, vpp));
writeline(dev, sprintf(':%s:PHASe %.12g', src, phase_deg));

out = sprintf('OUTPut%d', ch);
writeline(dev, [':' out ':LOAD INFinity']);

writeline(dev, sprintf(':%s:BURSt:STATe OFF', src));
writeline(dev, sprintf(':%s:BURSt:MODE TRIGgered', src));
writeline(dev, sprintf(':%s:BURSt:NCYCles %d', src, nc));
writeline(dev, sprintf(':%s:BURSt:TRIGger:SOURce INTernal', src));
writeline(dev, sprintf(':%s:BURSt:INTernal:PERiod %.12g', src, period_s));
writeline(dev, sprintf(':%s:BURSt:STATe ON', src));
end
