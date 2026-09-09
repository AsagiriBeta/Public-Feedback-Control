function [sc, ic] = pfc_band_power(Y, F, f0_hz, bw_hz)
%PFC_BAND_POWER 与 pfc_band_energy 相同：SC=2*f0，IC=2.2*f0（3.3 MHz）。
[sc, ic] = pfc_band_energy(Y, F, f0_hz, bw_hz);
end
