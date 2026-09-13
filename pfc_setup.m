function root = pfc_setup()
%PFC_SETUP 把项目所有子目录加入 MATLAB 搜索路径。
%
%   root = pfc_setup();
%
% 目录结构：
%   src/ui    界面层（uifigure 宿主、UI 适配层、配色、对话框）
%   src/core  业务逻辑（参数、采集/闭环流程、信号处理、存盘）
%   src/io    仪器与配置（VISA、参数存档、检查更新）
%   rigol     RIGOL DHO814 / DG2052 驱动
%   tools     构建与发布脚本（不参与运行）
%   tests     不依赖硬件的自检
%   web       界面前端静态资源（HTML/CSS/JS）
%
% 开发时一般不用手动调用：直接从项目根运行 pfc_app 即可，它会自动调用本函数。
% 从 tools/ 或 rigol/ 里启动脚本前，先在项目根跑一次 pfc_setup。
root = fileparts(mfilename('fullpath'));
if isempty(root)
    root = pwd;
end
addpath(genpath(root));
end
