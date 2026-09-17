function rigol_dg2052_apply_burst(dev, ch, freq_mhz, ampl_mVpp, phase_deg, n_cycle, period_s)
%RIGOL_DG2052_APPLY_BURST 正弦 N 周期猝发。
% 本机固件要求：先 BURSt ON，再写 NCYCles / PERiod（OFF 时写这些会 -220）。
% 软件 NCYCles 上限与 pfc_param_limits.n_cycle_max 一致（10000）；不要在这里
% 悄悄截成更小的数，否则界面显示 10000、仪器却按旧上限跑。
if ~(isscalar(period_s) && isnumeric(period_s) && isfinite(period_s) && period_s > 0)
    error('rigol:dg2052:period', 'period_s 须为有限正标量（猝发周期 = 1/PRF）。');
end
src = sprintf('SOURce%d', ch);
freq_hz = freq_mhz * 1e6;
vpp = ampl_mVpp / 1000;
nc = max(1, round(n_cycle));

rigol_dg2052_load(dev, ch);
writeline(dev, sprintf(':%s:FUNCtion SINusoid', src));
writeline(dev, sprintf(':%s:FREQuency %.12g', src, freq_hz));
writeline(dev, sprintf(':%s:VOLTage:UNIT VPP', src));
writeline(dev, sprintf(':%s:VOLTage %.12g', src, vpp));
writeline(dev, sprintf(':%s:PHASe %.12g', src, phase_deg));

writeline(dev, sprintf(':%s:BURSt:MODE TRIG', src));
writeline(dev, sprintf(':%s:BURSt:STATe ON', src));
pause(0.08);
L = pfc_param_limits();
nc = min(nc, L.n_cycle_max);
pl = nc / freq_hz;
period_s = max(period_s, pl + 50e-6);

writeline(dev, sprintf(':%s:BURSt:TRIGger:SOURce INTernal', src));
writeline(dev, sprintf(':%s:BURSt:NCYCles %d', src, nc));
pause(0.05);
writeline(dev, sprintf(':%s:BURSt:INTernal:PERiod %.12g', src, period_s));
writeline(dev, sprintf(':%s:BURSt:TDELay 0', src));
pause(0.05);

nc_rd = str2double(writeread(dev, sprintf(':%s:BURSt:NCYCles?', src)));
per_rd = str2double(writeread(dev, sprintf(':%s:BURSt:INTernal:PERiod?', src)));
if ~(isfinite(nc_rd) && abs(nc_rd - nc) < 1)
    error('rigol:dg2052:ncyc', '猝发周期数未写入（欲 %d，回读 %.4g）。', nc, nc_rd);
end
if ~(isfinite(per_rd) && abs(per_rd - period_s) / period_s < 0.05)
    warning('rigol:dg2052:period', '猝发周期回读 %.4g s（设定 %.4g s）', per_rd, period_s);
end
end
