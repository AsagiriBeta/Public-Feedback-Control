function [tf, lvl] = rigol_dho814_clipped(x, scale_vdiv)
%RIGOL_DHO814_CLIPPED 判断一帧采样是否已被示波器竖直量程削顶。
%
%   [tf, lvl] = rigol_dho814_clipped(x, scale_vdiv)
%     x           一帧采样（V）
%     scale_vdiv  采这一帧时所用的 CHANnel<n>:SCALe（V/div）
%     tf          是否顶到满量程（贴轨帧必须丢弃重采，不可入库）
%     lvl         满量程幅度（V），便于日志
%
% 原理：波形以 0 V 居中（setup 里设了 :CHANnel<n>:OFFSet 0），竖直方向 scope_vdiv 格，
% 因此满量程 = ±(scope_vdiv/2)×SCALe；峰值贴到满量程 98% 即判定削顶。
%
% 为什么必须拦：削顶是**对称**的，只生奇次谐波（3f/5f）、同时压掉偶次（2f）。
% 实测某轮数据里，被削顶的 4 帧（第 17/51/78/79 帧）3f 电平比中位帧虚高约 45 dB，
% 它们的波峰因数一致落在 1.09–1.20（正常帧 2.8–9.1），而且峰值/(满量程) 全部等于
% 1.092（量程各不相同）—— 这是被硬性钉在量程上限的指纹。
% 闭环若吃进削顶帧，会把 3f 假飙升当成「空化增强」。主循环先留 4× 余量预防贴轨；
% 若仍贴轨则丢弃本发、扩量程重采（最多 3 次），削顶点不进 SC/电压/图。
%
% 判定用「峰值是否贴住满量程」而不是波峰因数：波峰因数依赖窗口里猝发占多大比例，
% 不同采集设置下阈值会漂；满量程是硬边界，与信号形状无关。
cfg = rigol_instr_config();
lvl = 0.98 * (cfg.scope_vdiv / 2) * scale_vdiv;
tf = ~isempty(x) && isfinite(lvl) && lvl > 0 && max(abs(x)) >= lvl;
end
