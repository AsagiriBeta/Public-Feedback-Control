function rigol_dg2052_cw(dev, ch, freq_mhz, ampl_mVpp)
%RIGOL_DG2052_CW 关闭猝发，连续正弦（调试 CH1 回读/FFT 用）。
% 负载 50 Ω 必须先于幅度：否则面板数字按高阻解释，一改低阻实际电压就翻倍/减半。
src = sprintf('SOURce%d', ch);
freq_hz = freq_mhz * 1e6;
vpp = ampl_mVpp / 1000;
writeline(dev, sprintf(':%s:BURSt:STATe OFF', src));
rigol_dg2052_load(dev, ch);
writeline(dev, sprintf(':%s:FUNCtion SINusoid', src));
writeline(dev, sprintf(':%s:FREQuency %.12g', src, freq_hz));
writeline(dev, sprintf(':%s:VOLTage:UNIT VPP', src));
writeline(dev, sprintf(':%s:VOLTage %.12g', src, vpp));
end
