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
