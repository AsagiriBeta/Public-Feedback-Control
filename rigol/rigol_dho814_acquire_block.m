function [chPcd, timeIntervalNanoSeconds, realFs, chTx] = rigol_dho814_acquire_block(dev, npts, ch, mode, timeout_s, live_wait_s, burst_s)
%RIGOL_DHO814_ACQUIRE_BLOCK
% 'single'：等 CH1 边沿后读 RAW。触发超时则 STOP 后仍读一屏。
% 'live'：RUN 约一个 PRF 再 STOP 读（CH1 太弱、边沿触发空等时用）。
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
if nargin < 6 || isempty(live_wait_s)
    live_wait_s = 0.22;
end
live_wait_s = max(0.12, min(1.2, live_wait_s));
if nargin < 7 || isempty(burst_s) || ~isfinite(burst_s) || burst_s <= 0
    burst_s = [];
end
tx = cfg.scope_tx_channel;
oldT = [];
try
    oldT = dev.Timeout;
    % 波形块偶尔传不完。最多等 8 秒，不要用连接上的 60 秒把界面冻住。
    dev.Timeout = 8;
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
        if ~pause_or_abort(live_wait_s)
            restore_timeout(dev, oldT);
            realFs = 40e6;
            timeIntervalNanoSeconds = 1e9 / realFs;
            return;
        end
        writeline(dev, ':STOP');
        if ~pause_or_abort(0.05)
            try, writeline(dev, ':RUN'); catch, end
            restore_timeout(dev, oldT);
            realFs = 40e6;
            timeIntervalNanoSeconds = 1e9 / realFs;
            return;
        end
    else
        writeline(dev, ':SINGle');
        % 上一发读完仪器停在 STOP。立刻查 STATus 仍是 STOP，会把旧波形再读一遍
        % （调探头距离时表现为连续完全相同的脉冲）。先等到离开 STOP（已武装 WAIT），
        % 再等这次触发完成回到 STOP。不改 WORD/RAW。
        tArm = tic;
        tDraw = tic;
        while toc(tArm) < min(1.0, timeout_s)
            if scope_abort()
                writeline(dev, ':STOP');
                restore_timeout(dev, oldT);
                realFs = 40e6;
                timeIntervalNanoSeconds = 1e9 / realFs;
                return;
            end
            st = rigol_visa_query(dev, ':TRIGger:STATus?');
            if ~contains(st, 'STOP', 'IgnoreCase', true)
                break;
            end
            if toc(tDraw) > 0.2
                drawnow;
                tDraw = tic;
            end
            pause(0.01);
        end
        t0 = tic;
        while toc(t0) < timeout_s
            if scope_abort()
                writeline(dev, ':STOP');
                restore_timeout(dev, oldT);
                realFs = 40e6;
                timeIntervalNanoSeconds = 1e9 / realFs;
                return;
            end
            st = rigol_visa_query(dev, ':TRIGger:STATus?');
            if contains(st, 'STOP', 'IgnoreCase', true)
                break;
            end
            if toc(tDraw) > 0.2
                drawnow;
                tDraw = tic;
            end
            pause(0.01);
        end
        % 超时也 STOP 后读一屏：空返回会让网页一直停在上一实验的图。
        writeline(dev, ':STOP');
    end

    % 两路各读整段内存，再裁同一段。
    % 不写 STARt/STOP：这台固件一写就 -200，屏幕报远程指令执行错误。
    % 这台机器的 XORigin 会落在真正跳变前面 1–3 ms，不能拿它当脉冲开头。
    % 起点用回读通道上电平实际升高的地方，两路同一组下标。空档里没有这个跳变就不往前裁。
    [chTx, xinc, xorigin] = read_raw(dev, tx, npts);
    [chPcd, x2, xo2] = read_raw(dev, ch, npts);
    if ~(isfinite(xinc) && xinc > 0) && isfinite(x2) && x2 > 0
        xinc = x2;
    end
    if ~(isfinite(xorigin)) && isfinite(xo2)
        xorigin = xo2;
    end
    [chTx, chPcd] = crop_same(chTx, chPcd, xorigin, xinc, npts, burst_s);
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

function [a, b] = crop_same(a, b, xorigin, xinc, npts, burst_s)
% 两路用同一段。优先从回读通道上这一发真正开始的地方裁到它结束。
% 找不到跳变时才退回触发点。最长不超过这一发，内存里不够就不补。
if isempty(a) && isempty(b)
    return
end
na = numel(a);
nb = numel(b);
n = max(na, nb);
if n < 256 || ~(isfinite(xinc) && xinc > 0)
    return
end
[i0, last] = signal_span(a, xinc);
if isempty(i0)
    if ~(isfinite(xorigin))
        i0 = floor(n / 2) + 1;
    else
        i0 = round((-xorigin) / xinc) + 1;
    end
    last = n;
end
if i0 < 1
    i0 = 1;
end
n_cap = last - i0 + 1;
if ~isempty(burst_s) && isfinite(burst_s) && burst_s > 0
    n_cap = min(n_cap, max(256, round(burst_s / xinc)));
end
if isfinite(npts) && npts >= 256
    n_cap = min(n_cap, npts);
end
last = i0 + n_cap - 1;
if na > 0
    last = min(last, na);
end
if nb > 0
    last = min(last, nb);
end
if last - i0 + 1 < 256
    return
end
if na >= last
    a = a(i0:last);
end
if nb >= last
    b = b(i0:last);
end
end

function [i0, i1] = signal_span(y, xinc)
% 相对记录开头的空档，包络超过峰值 25% 的那一段。
% 正弦和猝发台阶都算有信号；整段都是同一个直流时峰值不够，返回空。
i0 = [];
i1 = [];
n = numel(y);
if n < 1000 || ~(isfinite(xinc) && xinc > 0)
    return
end
win = max(8, round(0.02e-3 / xinc));
if n < win * 4
    return
end
% 空档是最靠近 0 的那一截。猝发占了大半段时，整段中位数会落到高电平上。
nq = max(win, floor(0.15 * n));
[~, ord] = sort(abs(y(:)));
base = median(y(ord(1:nq)));
ac = abs(y(:) - base);
c = cumsum([0; ac]);
ma = (c((1 + win):end) - c(1:(end - win))) / win;
pk = max(ma);
if ~(isfinite(pk) && pk >= 0.02)
    return
end
ks = find(ma > max(0.05, 0.4 * pk));
if isempty(ks)
    return
end
i0 = ks(1);
i1 = min(n, ks(end) + win - 1);
if i1 - i0 + 1 < 256
    i0 = [];
    i1 = [];
end
end

function [y, xinc, xorigin] = read_raw(dev, ch, npts)
y = [];
xinc = NaN;
xorigin = NaN;
for attempt = 1:2
    try
        [y, xinc, xorigin] = rigol_dho814_read_channel(dev, ch, npts, 'RAW');
        return
    catch
        try
            writeline(dev, '*CLS');
            writeline(dev, ':STOP');
        catch
        end
    end
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

function tf = scope_abort()
global pcd_abort %#ok<GVMIS>
tf = ~isempty(pcd_abort) && logical(pcd_abort);
end

function ok = pause_or_abort(dt)
% 短暂停也要让 STOP / 关窗进来；中止就立刻返回，别把 visadev 空等到 Timeout。
ok = false;
t0 = tic;
while toc(t0) < dt
    if scope_abort()
        return;
    end
    pause(min(0.02, dt));
end
ok = true;
end
