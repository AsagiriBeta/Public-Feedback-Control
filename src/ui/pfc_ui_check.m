function ui = pfc_ui_check(ui)
%PFC_UI_CHECK 校验算法层收到的「UI 适配层」是否具备约定接口，并原样返回。
%
% 约定接口（目前唯一的实现是 pfc_ui_html：uifigure + uihtml + web/ 前端）：
%   ui.params()                             读 FUS 参数（已校验）
%   ui.raw()                                读原始参数字典
%   [f, v] = ui.debugfv()                   采集面板的频率 / 电压（非法时为 NaN）
%   ui.outdir()                             本次保存目录
%   ui.waveform(y, fs, f0, name, opts)      显示时域；opts.ch='tx'|'pcd' 分流到
%                                           对应时域图；opts.fft=true 时把频谱推到
%                                           该通道自己的 FFT 图（CH1 / CH2 各一张）
%                                           （第 5 个参数可省略，兼容旧调用）
%   ui.trend(k, sc, ic, volt, xmax, ymax)   追加一组实时点
%   ui.clearTrend()                         清空实时曲线
%   ui.status(s)                            显示一行状态
%   ui.countdown(remain_s, total_s)         墙钟倒计时（NaN 则关掉）
%
% 算法层（pfc_run_experiment / pfc_oneshot / pfc_debug_run / pfc_debug_no_mb）
% 只通过这层操作界面、不碰任何控件，所以换个界面实现时算法层一行都不用改 ——
% 新实现只要能提供上面这些函数句柄，就在这里放行。
need = {'params', 'raw', 'debugfv', 'outdir', ...
    'waveform', 'trend', 'clearTrend', 'status', 'countdown'};

bad = '';
if ~isstruct(ui)
    bad = '不是结构体';
else
    for i = 1:numel(need)
        k = need{i};
        if ~isfield(ui, k)
            bad = sprintf('缺少 %s', k);
            break;
        elseif ~isa(ui.(k), 'function_handle')
            bad = sprintf('%s 不是函数句柄', k);
            break;
        end
    end
end
if ~isempty(bad)
    error('PFC:ui:adapter', ...
        ['界面适配层不符合约定（%s）。\n需要：%s\n' ...
         '界面实现见 pfc_ui_html，把它的返回值传给算法层即可。'], ...
        bad, strjoin(need, ' / '));
end
end
