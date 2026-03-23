function tag = rigol_dho814_pick_mdepth(npts)
%RIGOL_DHO814_PICK_MDEPTH 选择不小于 npts 的最小标准存储深度（单通道）。
% 档位与 DHO800/DHO900 编程手册 :ACQuire:MDEPth 一致（DHO814 单通道最高 25M）。
opts = [1e3, 1e4, 1e5, 1e6, 5e6, 1e7, 2.5e7];
idx = find(opts >= npts, 1, 'first');
if isempty(idx)
    tag = '25M';
else
    tags = {'1k', '10k', '100k', '1M', '5M', '10M', '25M'};
    tag = tags{idx};
end
end
