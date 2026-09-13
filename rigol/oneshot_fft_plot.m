function oneshot_fft_plot()
%ONESHOT_FFT_PLOT 第一步：开环发一帧、收一帧，画 dB 频谱（不做反馈）。
% 无换能器/负载时不要运行。参数与 GUI 默认一致：1.5 MHz、20 mVpp。
thisdir = fileparts(mfilename('fullpath'));
if ~isdeployed
    % 本脚本在 rigol/ 下，其余代码在 src/ 等目录；按项目根加整棵路径，
    % 否则间接用到的 pfc_root / pfc_spectrum 之类会找不到。
    addpath(genpath(fileparts(thisdir)));
end
cfg = rigol_instr_config();

freq_mhz = 1.5;
volt_mV = 20;
n_cycle = 100;
prf_hz = 1;
npts = 40000;
fs_target = 40e6;

scope = rigol_dho814_open(cfg.scope_visa);
info = rigol_dho814_setup(scope, fs_target, npts, cfg.scope_channel);
fgen = visadev(cfg.awg_visa);
fgen.Timeout = 15;
cleanup = onCleanup(@() local_off(fgen, scope)); %#ok<NASGU>

rigol_dg2052_apply_burst(fgen, cfg.awg_channel, freq_mhz, volt_mV, 0, n_cycle, 1/prf_hz);
rigol_dg2052_output_set(fgen, true);
[chPcd, dt_ns, realFs, chTx] = rigol_dho814_acquire_block(scope, npts, cfg.scope_pcd_channel);
rigol_dg2052_output_set(fgen, false);

[F, ~, db] = pfc_spectrum(chTx, realFs);
f_mhz = F / 1e6;
nf0 = f_mhz / freq_mhz;
n_tail = min(numel(db), max(16, floor(numel(db)/10)));
db = db - mean(db(end-n_tail+1:end));

figure('Name', '单次 CH1 回读 FFT', 'Color', 'w');
plot(nf0, db, 'k');
xlim([0 4]);
ylim([-10 max(80, max(db(nf0<=4))+8)]);
xlabel('Frequency (n f_0)');
ylabel('Spectrum (dB)');
title(sprintf('CH1 TX readback  f_0=%.2f MHz  %g mVpp', freq_mhz, volt_mV));
grid on;
xline(1.0, 'r-');
xline(0.5, 'm--');
xline(2.0, 'g-');
xline(3.0, 'b--');
legend('FFT', 'f_0', 'IC 0.5 f_0', 'SC 2 f_0', '3 f_0');

t_us = (0:numel(chTx)-1) / realFs * 1e6;
figure('Name', '单次时域', 'Color', 'w');
subplot(2,1,1); plot(t_us, chTx); ylabel('CH1 TX (V)'); title('AWG readback');
subplot(2,1,2); plot(t_us, chPcd); ylabel('CH2 PCD (V)'); xlabel('Time (\mus)');

assignin('base', 'total_PCD_data', chPcd(:).');
assignin('base', 'oneshot_tx', chTx(:).');
assignin('base', 'oneshot_fs', realFs);

outdir = fullfile(pfc_root(), 'data');
S = struct('chPcd', chPcd, 'chTx', chTx, 'realFs', realFs, 'timeIntervalNanoSeconds', dt_ns, ...
    'f_Hz', F, 'fft_dB', db, 'freq_MHz', freq_mhz, 'volt_mVpp', volt_mV);
pfc_save_acquisition(outdir, 'oneshot_cli', S);
fprintf('oneshot 完成：采样率 %.4g Hz，CH1 peak 应在 1.5 MHz。输出已关闭。\n', realFs);
end

function local_off(fgen, scope)
try
    writeline(fgen, ':OUTPut1:STATe OFF');
catch
end
try
    clear fgen
catch
end
try
    clear scope
catch
end
end
