function rigol_dg2052_set_vpp_mV(dev, ampl_mVpp)
%RIGOL_DG2052_SET_VPP_MV 运行时更新幅度（峰峰值，mV）。
cfg = rigol_instr_config();
ch = cfg.awg_channel;
src = sprintf('SOURce%d', ch);
vpp = ampl_mVpp / 1000;
writeline(dev, sprintf(':%s:VOLTage:UNIT VPP', src));
writeline(dev, sprintf(':%s:VOLTage %.12g', src, vpp));
end
