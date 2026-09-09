function rigol_dg2052_cw(dev, ch, freq_mhz, ampl_mVpp)
%RIGOL_DG2052_CW 关闭猝发，连续正弦（调试 CH1 回读/FFT 用）。
src = sprintf('SOURce%d', ch);
out = sprintf('OUTPut%d', ch);
freq_hz = freq_mhz * 1e6;
vpp = ampl_mVpp / 1000;
writeline(dev, sprintf(':%s:BURSt:STATe OFF', src));
writeline(dev, sprintf(':%s:FUNCtion SINusoid', src));
writeline(dev, sprintf(':%s:FREQuency %.12g', src, freq_hz));
writeline(dev, sprintf(':%s:VOLTage:UNIT VPP', src));
writeline(dev, sprintf(':%s:VOLTage %.12g', src, vpp));
writeline(dev, sprintf(':%s:LOAD INFinity', out));
end
