function pfc_update_flow(fig)
%PFC_UPDATE_FLOW 「检查更新」的完整交互流程（GUIDE 界面与网页界面共用）。
% 更新源对用户透明、没有可配置项，因此只有两种结果：有更新 / 已是最新。
if pfc_visa('is_busy')
    warndlg('采集进行中，请先 STOP。', 'PFC');
    return;
end

info = pfc_update('check');
if ~info.ok
    errordlg(info.error, '检查更新');
    return;
end
if ~info.available
    msgbox(sprintf('已是最新版本  v%s', info.current), '检查更新');
    return;
end

notes = info.notes;
if isempty(notes)
    notes = '（本版未提供说明）';
end
q = sprintf(['发现新版本  v%s（当前 v%s）\n\n%s\n\n' ...
    '点「下载并安装」后，程序会下载安装包，然后自动关闭并启动安装程序。\n' ...
    '装好后从开始菜单重新打开即可。'], info.latest, info.current, notes);
if ~strcmp(questdlg(q, '检查更新', '下载并安装', '稍后', '稍后'), '下载并安装')
    return;
end

out = pfc_update('apply', info);
if ~out.ok
    errordlg(out.error, '检查更新');
    return;
end

% 安装程序要替换正在使用的 exe，本进程必须先退出。这里用 close() 而不是 delete()，
% 好让窗口的 CloseRequestFcn（pfc_ui_app 里的 pfc_ui_close）生效、参数照常存盘；
% launch_installer 里留了几秒延迟等本进程退出。
if ~isempty(fig) && isvalid(fig)
    close(fig);
end
end
