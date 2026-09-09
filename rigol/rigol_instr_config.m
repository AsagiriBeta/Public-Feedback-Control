function cfg = rigol_instr_config()
%RIGOL_INSTR_CONFIG 实验室仪器 VISA 地址与采集参数（请按本机修改）。
%
% 示波器接线（当前实验室）：
%   CH1 = 波形发生器回读（触发源，应看到 1.5 MHz）
%   CH2 = PCD 接收

cfg.scope_visa = 'USB0::0x1AB1::0x044D::DHO8A274611769::0::INSTR';
cfg.awg_visa   = 'USB0::0x1AB1::0x0644::DG2P273601178::0::INSTR';

cfg.scope_tx_channel  = 1;   % 发生器回读
cfg.scope_pcd_channel = 2;   % PCD
cfg.scope_channel     = 2;   % 兼容旧代码：默认采 PCD
cfg.awg_channel       = 1;

cfg.acquire_timeout_s = 12;

cfg.use_legacy_fft_bins = false;
cfg.harmonic_bandwidth_hz = 20e3;  % Chien 2022：SC/IC 均为 ±20 kHz
cfg.legacy_SC_range = 56373:56876;
cfg.legacy_IC_range = 9187:9690;

end
