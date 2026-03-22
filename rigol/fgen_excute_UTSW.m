function fgen_excute_UTSW(freq_mhz, ampl_mVpp, phase_deg, n_cycle, period_s)
%FGEN_EXCUTE_UTSW 在已连接时刷新 DG2052 猝发/幅度设置。
global fgen
cfg = rigol_instr_config();
if isempty(fgen)
    fgen_initialize_UTSW(freq_mhz, ampl_mVpp, phase_deg, n_cycle, period_s);
    return;
end
rigol_dg2052_apply_burst(fgen, cfg.awg_channel, freq_mhz, ampl_mVpp, phase_deg, n_cycle, period_s);
end
