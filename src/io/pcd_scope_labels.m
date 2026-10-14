function L = pcd_scope_labels()
%PCD_SCOPE_LABELS 当前示波器通道和信号源控制方式，供界面标题与采集共用。
%
% 回读 / PCD 通道来自 rigol_config.ini（仪器设置或主界面下拉）。
% awg_mode=manual 时电脑不连接信号源，也不做闭环。
cfg = rigol_instr_config();
tx = clamp_ch(cfg, 'scope_tx_channel', 1);
pcd = clamp_ch(cfg, 'scope_pcd_channel', 2);
L.tx = tx;
L.pcd = pcd;
L.txTag = sprintf('CH%d', tx);
L.pcdTag = sprintf('CH%d', pcd);
L.txName = sprintf('CH%d 回读', tx);
L.pcdName = sprintf('CH%d PCD', pcd);
L.txTime = sprintf('CH%d 时域 · 回读', tx);
L.pcdTime = sprintf('CH%d 时域 · PCD', pcd);
L.txFft = sprintf('频谱  FFT  ·  %s', L.txTag);
L.pcdFft = sprintf('频谱  FFT  ·  %s', L.pcdTag);
L.awg_mode = 'computer';
L.manual = false;
if isfield(cfg, 'awg_mode') && strcmpi(strtrim(char(string(cfg.awg_mode))), 'manual')
    L.awg_mode = 'manual';
    L.manual = true;
end
end

function ch = clamp_ch(cfg, key, fallback)
ch = fallback;
if isfield(cfg, key) && isnumeric(cfg.(key)) && isfinite(cfg.(key))
    ch = round(double(cfg.(key)));
end
ch = min(4, max(1, ch));
end
