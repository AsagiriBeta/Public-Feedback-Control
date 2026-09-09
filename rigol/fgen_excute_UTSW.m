function fgen_excute_UTSW(freq_mhz, ampl_mVpp, phase_deg, n_cycle, period_s)
%FGEN_EXCUTE_UTSW 刷新 DG2052 猝发/幅度（连接不存在则先打开）。
global fgen
cfg = rigol_instr_config();
alive = false;
try
    alive = ~isempty(fgen) && isvalid(fgen);
catch
end
if ~alive
    fgen_initialize_UTSW(freq_mhz, ampl_mVpp, phase_deg, n_cycle, period_s);
    return;
end
rigol_dg2052_apply_burst(fgen, cfg.awg_channel, freq_mhz, ampl_mVpp, phase_deg, n_cycle, period_s);
end
