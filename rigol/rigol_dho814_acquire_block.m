function [chPcd, timeIntervalNanoSeconds, realFs, chTx] = rigol_dho814_acquire_block(dev, npts, ch, mode, timeout_s)
%RIGOL_DHO814_ACQUIRE_BLOCK
% 'single'：等 CH1 边沿后读 RAW。触发超时则返回空，不空等 visadev 60s。
% 'live'：短暂停后读 RAW（连续波调试）。
cfg = rigol_instr_config();
if nargin < 3 || isempty(ch)
    ch = cfg.scope_pcd_channel;
end
if nargin < 4 || isempty(mode)
    mode = 'single';
end
if nargin < 5 || isempty(timeout_s)
    timeout_s = cfg.acquire_timeout_s;
end
tx = cfg.scope_tx_channel;
oldT = [];
try
    oldT = dev.Timeout;
    dev.Timeout = min(8, max(3, timeout_s + 2));
catch
end

chPcd = [];
chTx = [];
xinc = NaN;
try
    if strcmpi(mode, 'live')
        % RAW 只能在 STOP 后读。调试若只 STOP 不 RUN，第一帧用的是 setup 里
        % 已经采满的缓冲，看起来正常；第二帧起仪器一直停着，读到的还是同一屏，
        % 改完量程后 :WAVeform:DATA? 还可能一直等到超时 —— 界面就像卡在 #1。
        writeline(dev, ':RUN');
        pause(0.12);
        writeline(dev, ':STOP');
        pause(0.05);
    else
        writeline(dev, ':SINGle');
        t0 = tic;
        ok = false;
        while toc(t0) < timeout_s
            st = rigol_visa_query(dev, ':TRIGger:STATus?');
            if contains(st, 'STOP', 'IgnoreCase', true)
                ok = true;
                break;
            end
            pause(0.01);
        end
        if ~ok
            writeline(dev, ':STOP');
            restore_timeout(dev, oldT);
            realFs = 40e6;
            timeIntervalNanoSeconds = 1e9 / realFs;
            return;
        end
        writeline(dev, ':STOP');
    end

    [chPcd, xinc] = read_raw(dev, ch, npts);
    if nargout >= 4
        [chTx, x2] = read_raw(dev, tx, npts);
        if ~(isfinite(xinc) && xinc > 0) && isfinite(x2) && x2 > 0
            xinc = x2;
        end
    end
    if strcmpi(mode, 'live')
        % 读完重新跑起来，示波器屏幕才不会冻住，下一圈 :RUN 也有新数据可停。
        try, writeline(dev, ':RUN'); catch, end
    end
catch
    chPcd = [];
    chTx = [];
end

if ~(isfinite(xinc) && xinc > 0)
    xinc = 1 / 40e6;
end
realFs = 1 / xinc;
timeIntervalNanoSeconds = xinc * 1e9;
restore_timeout(dev, oldT);
end

function [y, xinc] = read_raw(dev, ch, npts)
try
    [y, xinc] = rigol_dho814_read_channel(dev, ch, npts, 'RAW');
catch
    y = [];
    xinc = NaN;
end
end

function restore_timeout(dev, oldT)
if ~isempty(oldT)
        try
            dev.Timeout = oldT;
        catch
        end
end
end
