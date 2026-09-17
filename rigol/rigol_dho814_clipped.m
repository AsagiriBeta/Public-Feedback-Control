function [tf, lvl] = rigol_dho814_clipped(x, scale_vdiv)
%RIGOL_DHO814_CLIPPED 判断一帧采样是否已被示波器竖直量程削顶。
%
%   [tf, lvl] = rigol_dho814_clipped(x, scale_vdiv)
%
% 贴轨帧必须丢弃、不得写入 SC/电压。以前 98% 满量程才判，软削顶（平顶但峰值
% 略低于标称满格）仍会进 SC，偶次谐波被压、奇次假峰。现改为：
%   1) 峰值 ≥ 满量程 90%
%   2) 或峰值 ≥ 85% 且大量点堆在峰值附近（平顶）
cfg = rigol_instr_config();
lvl = (cfg.scope_vdiv / 2) * scale_vdiv;
tf = false;
if isempty(x) || ~(isfinite(lvl) && lvl > 0)
    return
end
x = x(:);
pk = max(abs(x));
if ~(isfinite(pk) && pk > 0)
    return
end
if pk >= 0.90 * lvl
    tf = true;
    return
end
if pk >= 0.85 * lvl
    nflat = nnz(abs(x) >= 0.98 * pk);
    tf = nflat >= max(30, 0.0005 * numel(x));
end
end
