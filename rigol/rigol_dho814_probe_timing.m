function T = rigol_dho814_probe_timing(dev, depth_tags, divs, poll)
%RIGOL_DHO814_PROBE_TIMING 实测「存储深度 × 时基 → 采样率/记录长度」的真实档位表。
%
% 为什么必须实测、不能按公式算：
%   直觉上 realFs = MDEPth / 记录长度，时基刻度 = 记录长度/10，于是可以反推出任何一个
%   想要的 realFs。DHO814（固件 00.01.04）不是这样：
%     1) :ACQuire:SRATe? 是**离散 1-2-5 档位**（实测采样间隔 3.2ns × {1,2,5,10,25,50,125,250}），
%        把时基设成 375µs/div、深度 100k，它会给你 12.5 MSa/s（而不是 26.67）；
%     2) 内存记录长度 ≥ 屏幕窗（1.28–3.2 倍），不是 10 格；
%     3) **:WAVeform:XORigin 恒等于 -记录长度/2**，也就是触发点固定在记录正中央，
%        :TIMebase:HREFerence:MODE LB 对内存记录无效（只影响屏幕显示）。
%
% 第 3 条是决定性的：能用来装这一发的只有**触发之后那一半**，即
%     可用触后窗口 = 记录长度/2 = MDEPth / (2 × SRATe)
% 因此「记录 ≥ 前置空档 + 猝发」这个判据是错的，正确判据是
%     可用触后窗口 ≥ 猝发长度 × 余量
%
% 输入
%   dev         已打开的 visadev（示波器）
%   depth_tags  要测的深度档，如 {'10k','100k','1M'}
%   divs        要测的时基刻度 (s/div)
%   poll        每次改设置后等固件稳定的时间 (s)，默认 0.3
%
% 输出 T：结构体数组，字段 depth_tag / depth_pts / div_s / fs / record_s / post_s
%   fs 为 NaN 的组合会被丢掉（固件拒绝或查询不到）。

if nargin < 2 || isempty(depth_tags)
    depth_tags = {'10k', '100k', '1M'};
end
if nargin < 3 || isempty(divs)
    divs = [20e-6, 50e-6, 100e-6, 200e-6, 500e-6, 1e-3, 2e-3, 5e-3];
end
if nargin < 4 || isempty(poll)
    poll = 0.3;
end

T = struct('depth_tag', {}, 'depth_pts', {}, 'div_s', {}, 'fs', {}, 'record_s', {}, 'post_s', {});

for i = 1:numel(depth_tags)
    md = depth_tags{i};
    try
        writeline(dev, sprintf(':ACQuire:MDEPth %s', md));
    catch
        continue
    end
    pause(0.05);
    % 深度以回读为准：固件可能不认这个档，不要按请求值记账。
    d_pts = qnum(dev, ':ACQuire:MDEPth?');
    for j = 1:numel(divs)
        try
            writeline(dev, sprintf(':TIMebase:MAIN:SCALe %.12g', divs(j)));
            writeline(dev, ':TIMebase:HREFerence:MODE LB');
            writeline(dev, ':TIMebase:MAIN:OFFSet 0');
            % 不 RUN 就读不到有效的 POINts/XINCrement（缓冲还没按新时基采过）
            writeline(dev, ':RUN');
        catch
            continue
        end
        pause(poll);
        try
            writeline(dev, ':STOP');
        catch
        end
        pause(0.05);
        fs = qnum(dev, ':ACQuire:SRATe?');
        n  = qnum(dev, ':WAVeform:POINts?');
        xi = qnum(dev, ':WAVeform:XINCrement?');
        if ~(isfinite(fs) && fs > 0 && isfinite(n) && n >= 256 && isfinite(xi) && xi > 0)
            continue
        end
        rec = n * xi;
        T(end+1) = struct('depth_tag', md, 'depth_pts', d_pts, 'div_s', divs(j), ...
            'fs', fs, 'record_s', rec, 'post_s', rec / 2); %#ok<AGROW>
    end
end

try
    writeline(dev, ':RUN');
catch
end
end

function v = qnum(dev, cmd)
%QNUM 查询数值；固件不支持或查询失败给 NaN，不打断探测
v = NaN;
try
    v = str2double(writeread(dev, cmd));
catch
end
end
