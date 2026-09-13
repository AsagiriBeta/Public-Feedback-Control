function row = pfc_fitrow(x, n)
%PFC_FITROW 把一帧采样整形成 1×n 的定长行：超长截断、不足补零、空帧给全零。
%
% 采集失败或 USB 毛刺时，rigol_dho814_acquire_block 会返回 []，返回的帧长度也
% 可能和上一帧不同。直接 datamat(k,:) = ch 会因「赋值维度不一致」当场报错、
% 把整轮实验或调试打断，所以采集路径一律先过这里。
%
% pfc_run_experiment（闭环/开环）与 pfc_debug_no_mb（调试）共用同一套整形规则，
% 保证两种模式下存出来的 datamat / txmat 列宽一致。
x = x(:).';
if isempty(x)
    row = zeros(1, n);
elseif numel(x) >= n
    row = x(1:n);
else
    row = [x, zeros(1, n - numel(x))];
end
end
