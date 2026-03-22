function cfg = rigol_instr_config()
%RIGOL_INSTR_CONFIG 实验室仪器 VISA 地址与采集参数（请按本机修改）。
%
% 在 MATLAB 中运行 visadevlist 或 VISA 资源管理器，将 USB 字符串填入下方。
% 文档参考：
%   - DHO800/DHO900 Programming Guide（DHO814 属 DHO800 系列，SCPI 相同）
%   - DG2000 系列编程手册 / 用户手册（DG2052）
%
% USB 驱动：RIGOL 官网安装 USB Test & Measurement Class (USBTMC) / VISA。

cfg.scope_visa = 'USB0::0x1AB1::0x0514::YOUR_DHO814_SERIAL::INSTR'; %#ok<*NASGU>
cfg.awg_visa   = 'USB0::0x1AB1::0x0641::YOUR_DG2052_SERIAL::INSTR';

cfg.scope_channel = 1;   % 1..4，接 PCD 信号的通道
cfg.awg_channel   = 1;   % 1 或 2

cfg.acquire_timeout_s = 8;

% FFT 频带：原仓库在固定采样率/深度下使用硬编码索引；此处默认按基频自动算谐波带
cfg.use_legacy_fft_bins = false;
cfg.harmonic_bandwidth_hz = 200e3;
cfg.legacy_SC_range = 56373:56876;
cfg.legacy_IC_range = 9187:9690;

end
