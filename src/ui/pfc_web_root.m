function root = pfc_web_root()
%PFC_WEB_ROOT 返回前端资源目录（web/）：源码模式在项目内，打包后在 CTF 内。
%
% 网页界面（uifigure + uihtml）依赖这套静态资源：index.html / app.css / app.js /
% vendor/*（Alpine.js、uPlot）。必须随包分发，打包见 pfc_build_exe。
persistent cached
if ~isempty(cached)
    root = cached;
    return;
end

cands = {};
if isdeployed
    cands{end+1} = fullfile(ctfroot, 'web');
else
    % 源码模式：web/ 在项目根下。用 pfc_root()（源码模式下它就是项目根）取，
    % 这样本文件不管放在 src/ui 还是别处都对。
    cands{end+1} = fullfile(pfc_root(), 'web');
end

root = '';
for i = 1:numel(cands)
    if isfolder(cands{i})
        root = cands{i};
        break;
    end
end
if isempty(root)
    root = cands{1};
end
cached = root;
end
