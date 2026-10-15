function fgen_initialize_UTSW(freq_mhz, ampl_mVpp, phase_deg, n_cycle, period_s)
%FGEN_INITIALIZE_UTSW 连接 DG2052（单例）并配置猝发。
global fgen
cfg = rigol_instr_config();
fgen = pcd_visa('fgen');
rigol_dg2052_apply_burst(fgen, cfg.awg_channel, freq_mhz, ampl_mVpp, phase_deg, n_cycle, period_s);
end
