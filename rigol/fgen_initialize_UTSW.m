function fgen_initialize_UTSW(freq_mhz, ampl_mVpp, phase_deg, n_cycle, period_s)
%FGEN_INITIALIZE_UTSW 连接 DG2052 并配置猝发参数（替代原 UTSW/其他驱动）。
global fgen
cfg = rigol_instr_config();
if isempty(fgen)
    fgen = visadev(cfg.awg_visa);
    fgen.Timeout = 10;
end
rigol_dg2052_apply_burst(fgen, cfg.awg_channel, freq_mhz, ampl_mVpp, phase_deg, n_cycle, period_s);
end
