function root = pcd_web_root()
%PCD_WEB_ROOT 返回前端资源目录（web/）：源码模式在项目内，打包后在 CTF 内。
%
% 网页界面（uifigure + uihtml）依赖这套静态资源：index.html / app.css / app.js /
% vendor/*（Alpine.js、uPlot）。必须随包分发，打包见 pcd_build_exe。
%
% 打包后的位置不是 <ctfroot>\web：MATLAB Compiler 会把附加文件解到
% <ctfroot>\<组件名>\ 下（组件名 = exe 名，现在是 PCD），web/ 实际在
% <ctfroot>\PCD\web。这个层级不保证跨 Compiler 版本不变，所以先试
% 常见位置，都不中就在解包目录里按名字搜，别把路径写死成一层。
persistent cached
if ~isempty(cached)
    root = cached;
    return;
end

if isdeployed
    root = pick_web(ctfroot);
else
    % 源码模式：web/ 在项目根下。用 pcd_root()（源码模式下它就是项目根）取，
    % 这样本文件不管放在 src/ui 还是别处都对。
    root = fullfile(pcd_root(), 'web');
end
cached = root;
end

% ---------------------------------------------------------------- 定位
function d = pick_web(base)
%PICK_WEB 在打包解包目录 base 下找到含 index.html 的 web 目录。
cands = {fullfile(base, 'web'), fullfile(base, 'PCD', 'web'), fullfile(base, 'pcd_app', 'web')};
for i = 1:numel(cands)
    if isfile(fullfile(cands{i}, 'index.html'))
        d = cands{i};
        return;
    end
end
% 兜底：解包目录只有几十个文件，按名字搜一遍最稳，免得 Compiler 换层级后又打不开。
hit = dir(fullfile(base, '**', 'index.html'));
for k = 1:numel(hit)
    if strcmpi(last_name(hit(k).folder), 'web')
        d = hit(k).folder;
        return;
    end
end
% 都没找到：返回首选路径，让调用方报出完整路径（PCD:ui:noWeb）
d = cands{1};
end

function n = last_name(p)
[~, n, ext] = fileparts(p);
n = [n ext];
end
