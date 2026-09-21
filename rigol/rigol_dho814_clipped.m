function [tf, lvl] = rigol_dho814_clipped(x, scale_vdiv)
%RIGOL_DHO814_CLIPPED 判断一帧采样是否已被示波器竖直量程削顶。
%
%   [tf, lvl] = rigol_dho814_clipped(x, scale_vdiv)
%
% 贴轨帧必须丢弃、不得写入 SC/电压。以前 98% 满量程才判，软削顶（平顶但峰值
% 略低于标称满格）仍会进 SC，偶次谐波被压、奇次假峰。现改为：
%   1) 峰值 ≥ 满量程 90%
%   2) 或峰值 ≥ 85% 且贴轨样本连续成片（真的平顶）
%
% 判据 2 不能用「有多少个点落在峰值附近」：干净正弦在峰顶 ±2% 内的点约占 13%，
% 4000 点里就有约 512 个，而真削顶帧约 960–1216 个 —— 两者同量级，阈值取 30
% 等于「峰值 ≥85% 一律判削顶」，会把 85–90% 满量程的干净帧全部误丢。
% 改用「最长连续段」：削顶是 ADC 钉在同一码上的一整段，而干净正弦每个周期的峰顶
% 只沾到 1 个点（相邻样本差约 150 个码），连不成片。
% 实测 4000 点 @31.25 MSa/s：干净正弦（75–95% 满量程）最长段恒为 1，削顶帧为 3。
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
    % 平顶 = 贴到峰值的那一段是连着的。全屏 scope_vdiv×SCALe 落在 12 位 ADC 上，
    % 容差给 1.5 个码覆盖量化舍入；标称满量程与实际硬上限（实测 4.368 格）的
    % 差异不影响这里 —— 这里只比较「相对本帧峰值」，与满量程无关。
    lsb = max(realmin, (cfg.scope_vdiv * scale_vdiv) / 4096);
    near = abs(x) >= pk - 1.5 * lsb;
    d = diff([false; near; false]);
    st = find(d == 1);
    if isempty(st)
        tf = false;
    else
        en = find(d == -1) - 1;
        tf = max(en - st + 1) >= 2;   % 连着两点钉在同一码上即判平顶
    end
end
end
