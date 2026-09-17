/* ============================================================
 * PFC 前端逻辑：Alpine 状态 + uPlot 图表 + 与 MATLAB(uihtml) 的桥接
 *
 * 两种运行方式：
 *   1) 在 MATLAB 里（uihtml 宿主）  -> MATLAB 调用 setup()，双向通信
 *   2) 直接在浏览器打开（离线预览） -> 无 bridge，自动跑演示数据
 * 协议：
 *   MATLAB -> JS : htmlComponent 事件 'pfc'（sendEventToHTMLSource）；启动时也可走 Data
 *   JS -> MATLAB : sendEventToMATLAB('action',{name}) / ('params',{...})
 * ============================================================ */
(function () {
  'use strict';

  /* ---------------- 与 MATLAB 的通道 ---------------- */
  var bridge = { comp: null, onData: null };
  var lastData = null;

  function deliver(d) {
    lastData = d;
    if (!(bridge.onData && d)) { return; }
    try { bridge.onData(d); }
    catch (e) { try { console.error('[PFC] fromMatlab', e); } catch (e2) {} }
  }

  // MATLAB 在加载 HTML 后自动调用这个全局函数（约定名，不能改）
  window.setup = function (htmlComponent) {
    bridge.comp = htmlComponent;
    htmlComponent.addEventListener('DataChanged', function () {
      deliver(htmlComponent.Data);
    });
    // 采集过程用 sendEventToHTMLSource('pfc', …)，避免每帧写 Data 触发整页重载
    htmlComponent.addEventListener('pfc', function (ev) {
      var d = ev && (ev.HTMLEventData !== undefined ? ev.HTMLEventData : ev.Data);
      deliver(d);
    });
    // MATLAB 可能在页面加载前就写过 Data，这里补取一次
    if (htmlComponent.Data !== undefined && htmlComponent.Data !== null) {
      deliver(htmlComponent.Data);
    }
    try { htmlComponent.sendEventToMATLAB('ready', {}); } catch (e) {}
  };

  function toMatlab(name, payload) {
    // 必须先剥掉 Alpine 的响应式包装：sendEventToMATLAB 底层是 postMessage，
    // 走的是结构化克隆，而 Alpine 的 state 是 Proxy —— 直接发会抛
    // "could not be cloned"，事件静默丢失（改参数、点按钮全都不生效）。
    // JSON 往返是最省事又最可靠的还原方式，MATLAB 侧本来也是按 JSON 解码的。
    var data = payload;
    try { data = JSON.parse(JSON.stringify(payload)); }
    catch (e) { data = null; }
    if (bridge.comp) { bridge.comp.sendEventToMATLAB(name, data); }
    else { console.log('[PFC demo] -> MATLAB:', name, data); }
  }

  /* ---------------- 配色（与 pfc_ui_colors 对齐） ---------------- */
  var C = {
    axBg: '#111419', axFg: '#C7D1E0', grid: '#373E4B',
    line: '#78ADF2', ref: '#6B788C', text: '#E6EAEF', muted: '#8B95A5'
  };
  var FONT = '10px -apple-system,"PingFang SC","Microsoft YaHei UI",Segoe UI,sans-serif';

  function axisY(label) {
    return {
      stroke: C.axFg, font: FONT, size: 56, label: label, labelSize: 12,
      labelFont: FONT, stroke: C.axFg,
      grid: { stroke: C.grid, width: 1, dash: [2, 3] },
      ticks: { stroke: C.grid, width: 1 }
    };
  }
  function axisX(label) {
    return {
      stroke: C.axFg, font: FONT, size: 30, label: label, labelSize: 11,
      labelFont: FONT,
      grid: { stroke: C.grid, width: 1, dash: [2, 3] },
      ticks: { stroke: C.grid, width: 1 }
    };
  }
  function lineSeries() {
    return { stroke: C.line, width: 1.4, points: { show: false } };
  }
  function dotSeries() {
    return { stroke: C.line, width: 0, points: { show: true, size: 6, fill: C.line, stroke: C.line } };
  }

  function mkChart(el, opts) {
    if (!el) { return null; }
    var w = el.clientWidth || 400, h = el.clientHeight || 180;
    return new uPlot(Object.assign({
      width: w, height: h, legend: { show: false },
      cursor: { show: false, drag: { x: false, y: false, setScale: false } },
      scales: { x: { time: false } }
    }, opts), [[], []], el);
  }

  /* MATLAB uihtml 有时把 1×N 向量编成嵌套数组；统一摊平成一维数字列。 */
  function vec(a) {
    if (a == null) { return null; }
    if (typeof a === 'number') { return [a]; }
    if (typeof a.length !== 'number') { return a; }
    if (a.length > 0 && typeof a[0] !== 'number' && a[0] && typeof a[0].length === 'number') {
      var out = [], i, j, row;
      for (i = 0; i < a.length; i++) {
        row = a[i];
        if (typeof row === 'number') { out.push(row); }
        else if (row && row.length) {
          for (j = 0; j < row.length; j++) { out.push(row[j]); }
        }
      }
      return out;
    }
    return Array.prototype.slice.call(a);
  }

  function inferCh(d) {
    var c = d && d.ch;
    if (c === 'pcd' || c === 'tx') { return c; }
    var n = ((d && d.name) || '').toLowerCase();
    if (n.indexOf('pcd') >= 0 || n.indexOf('ch2') >= 0) { return 'pcd'; }
    return 'tx';
  }

  /* 电压图自己按数据量程；ymax 曾经被闭环 SC 的 dB 上限（~8）占用，400 mVpp 会画到窗外。 */
  function voltYmax(volt, hinted) {
    var m = 0, i, v;
    if (volt && volt.length) {
      for (i = 0; i < volt.length; i++) {
        v = volt[i];
        if (typeof v === 'number' && isFinite(v) && v > m) { m = v; }
      }
    }
    var hi = Math.max(40, m * 1.25);
    if (typeof hinted === 'number' && isFinite(hinted) && hinted >= 40) {
      hi = Math.max(hi, hinted);
    }
    return hi;
  }

  function scYlim(sc, tgt) {
    if (!(typeof tgt === 'number' && isFinite(tgt))) { tgt = 2; }
    var mx = tgt, mn = 0, i, v;
    if (sc && sc.length) {
      for (i = 0; i < sc.length; i++) {
        v = sc[i];
        if (typeof v === 'number' && isFinite(v)) {
          if (v > mx) { mx = v; }
          if (v < mn) { mn = v; }
        }
      }
    }
    return {
      min: Math.min(-1, mn - 0.3),
      max: Math.max(tgt + 1.2, mx + 0.5, 4)
    };
  }

  function drawScBand(u) {
    var tgt = u.__tgt_db;
    if (!(typeof tgt === 'number' && isFinite(tgt))) { return; }
    var bb = u.bbox;
    var y0 = u.valToPos(tgt - 0.4, 'y', true);
    var y1 = u.valToPos(tgt + 0.4, 'y', true);
    var ym = u.valToPos(tgt, 'y', true);
    var ctx = u.ctx;
    ctx.save();
    ctx.beginPath();
    ctx.rect(bb.left, bb.top, bb.width, bb.height);
    ctx.clip();
    var top = Math.min(y0, y1), h = Math.abs(y1 - y0);
    ctx.fillStyle = 'rgba(255, 196, 80, 0.28)';
    ctx.fillRect(bb.left, top, bb.width, h);
    ctx.strokeStyle = 'rgba(200, 120, 40, 0.85)';
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(bb.left, ym);
    ctx.lineTo(bb.left + bb.width, ym);
    ctx.stroke();
    ctx.restore();
  }

  var CHART_IDS = {
    timeTx: '#ch-time-tx', timePcd: '#ch-time-pcd',
    fftTx: '#ch-fft-tx', fftPcd: '#ch-fft-pcd',
    volt: '#ch-volt', sc: '#ch-sc', ic: '#ch-ic'
  };
  var CHART_KEYS = ['timeTx', 'timePcd', 'fftTx', 'fftPcd', 'volt', 'sc', 'ic'];
  var STEP_TABS = { debug: 1, nomb: 1, open: 1, fb: 1 };
  var ACTION_TAB = {
    oneshot: 'debug', debug: 'debug',
    noMB: 'nomb', openMB: 'open', feedback: 'fb'
  };

  /* ---------------- 采样点 / 周期数软件上下限 ---------------- */
  /* 必须与 src/core/pfc_param_limits.m、web/index.html 的 min/max 保持同一套数字。
   * 上限 100000：100k WORD × 2 通道，40 MSa/s ≈ 2.5 ms 窗，USB 仍可接受（旧实验上限 50k 的 2 倍）。
   * 周期数 10000：与 pfc_param_limits.n_cycle_max 一致。不要按假 40 MSa/s 窗再压到 3000。
   * 超限必须在输入时截断并写回 x-model，否则框里仍显示 400000 / 9990，MATLAB 却按上限跑，
   * 截图会骗人。低于下限只在失焦/回车时截（逐键输入 40000 时中间的 4、40、400 还不能截）。 */
  var NPTS_MIN = 4096, NPTS_MAX = 100000;
  var NCYC_MIN = 1, NCYC_MAX = 10000;
  var AMP_GAIN_MIN = 1, AMP_GAIN_DEFAULT = 40;

  function clampInt(v, lo, hi, commitMin) {
    if (typeof v !== 'number' || !isFinite(v)) { return v; }
    v = Math.round(v);
    if (v > hi) { return hi; }
    if (v < lo && (commitMin || v <= 0)) { return lo; }
    return v;
  }

  /* 空化率 duty = T_on / PRI = n_cycle * PRF / f0_Hz
   * T_on = n_cycle / f0_Hz；PRI = 1 / PRF
   * 界面百分数：cav_pct = 100 * duty
   * n_cycle = (cav_pct/100) * f0_Hz / PRF
   * 例：1.5 MHz、PRF 5 Hz、n_cycle 3000 → 1%。必须与 src/core/pfc_duty.m 同一套公式。 */
  function cavPctFromNcycle(n, freqMhz, prf) {
    if (typeof n !== 'number' || typeof freqMhz !== 'number' || typeof prf !== 'number') { return NaN; }
    if (!isFinite(n) || !isFinite(freqMhz) || !isFinite(prf) || freqMhz <= 0 || prf <= 0) { return NaN; }
    return 100 * n * prf / (freqMhz * 1e6);
  }
  function ncycleFromCavPct(pct, freqMhz, prf) {
    if (typeof pct !== 'number' || typeof freqMhz !== 'number' || typeof prf !== 'number') { return NaN; }
    if (!isFinite(pct) || !isFinite(freqMhz) || !isFinite(prf) || freqMhz <= 0 || prf <= 0) { return NaN; }
    return Math.round((pct / 100) * (freqMhz * 1e6) / prf);
  }
  function prettyPct(x) {
    if (typeof x !== 'number' || !isFinite(x)) { return x; }
    return parseFloat(x.toPrecision(6));
  }
  function fmtMmSs(sec) {
    sec = Math.max(0, Math.floor(sec + 1e-9));
    var m = Math.floor(sec / 60);
    var r = sec % 60;
    return m + ':' + (r < 10 ? '0' : '') + r;
  }

  function defaultParams() {
    var p = {
      studyID: '', directory: '',
      dbg_freq: 1.5, dbg_volt: 20,
      freq_mhz: 1.5, volt_mVpp: 50, amp_gain: 40, prf_hz: 2, n_cycle: 400,
      cav_pct: 100 * 400 * 2 / 1.5e6, duration_s: 120, npts: 40000,
      target_db: 2, max_mVpp: 120, base_mVpp: 100, vstep_mVpp: 5,
      ctrl_metric: '2f_window_sum', sc_harm: '2f'
    };
    // MATLAB 若在 Alpine 启动前已写入 Data，第一帧就用存档，避免框里先闪出厂 2 dB。
    if (lastData && lastData.params && typeof lastData.params === 'object') {
      Object.assign(p, lastData.params);
    }
    return p;
  }

  /* ---------------- Alpine 组件 ---------------- */
  window.pfcApp = function () {
    return {
      busy: false,
      paramsReady: false,  // MATLAB init 到达前不让点闭环，避免按 JS 缺省 2 开跑
      status: '就绪 / Ready',
      cdOn: false,
      cdClock: '0:00',
      cdSub: '',
      _cdTimer: null,
      _cdSyncAt: 0,
      _cdSyncRemain: 0,
      _cdTotal: 0,
      tab: 'debug',          // 步骤页：debug / nomb / open / fb（不是波形/趋势）
      runTab: '',            // 正在跑的步骤；切去看别的页时那个页签仍带 run 标记
      titles: {
        tx: 'CH1 时域  ·  TX',
        pcd: 'CH2 时域  ·  PCD',
        fftTx: '频谱  FFT  ·  CH1',
        fftPcd: '频谱  FFT  ·  CH2'
      },
      // 字段名与 MATLAB 侧存档（pfc_gui_params）完全一致，两边共用一套词汇
      p: defaultParams(),
      charts: {},
      trend: { x: [], sc: [], ic: [], volt: [] },
      _demo: null,

      /* ---- 初始化 ---- */
      init: function () {
        var self = this;
        this.charts.timeTx  = mkChart(this.$el.querySelector('#ch-time-tx'),
          { axes: [axisX('Time (µs)'), axisY('V')], series: [{}, lineSeries()] });
        this.charts.timePcd = mkChart(this.$el.querySelector('#ch-time-pcd'),
          { axes: [axisX('Time (µs)'), axisY('V')], series: [{}, lineSeries()] });
        this.charts.fftTx = mkChart(this.$el.querySelector('#ch-fft-tx'),
          { axes: [axisX('Frequency (MHz)'), axisY('dB')], series: [{}, lineSeries()],
            hooks: { draw: [function (u) { drawMarks(u); }] } });
        this.charts.fftPcd = mkChart(this.$el.querySelector('#ch-fft-pcd'),
          { axes: [axisX('Frequency (MHz)'), axisY('dB')], series: [{}, lineSeries()],
            hooks: { draw: [function (u) { drawMarks(u); }] } });
        this.charts.volt  = mkChart(this.$el.querySelector('#ch-volt'),
          { axes: [axisX('Pulse #'), axisY('mVpp')], series: [{}, dotSeries()] });
        this.charts.sc    = mkChart(this.$el.querySelector('#ch-sc'),
          { axes: [axisX('Pulse #'), axisY('dB')], series: [{}, dotSeries()],
            hooks: { draw: [function (u) { drawScBand(u); }] } });
        this.charts.ic    = mkChart(this.$el.querySelector('#ch-ic'),
          { axes: [axisX('Pulse #'), axisY('IC')], series: [{}, dotSeries()] });

        window.addEventListener('resize', function () { self.resizeCharts(); });
        // uihtml 改尺寸经常不触发 window.resize；图表格子自己变了再跟上。
        if (typeof ResizeObserver !== 'undefined') {
          var ro = new ResizeObserver(function () { self.resizeCharts(); });
          Object.keys(CHART_IDS).forEach(function (k) {
            var el = self.$el.querySelector(CHART_IDS[k]);
            if (el) { ro.observe(el); }
          });
          var body = self.$el.querySelector('.right-body');
          if (body) { ro.observe(body); }
          var grid = self.$el.querySelector('.chart-grid');
          if (grid) { ro.observe(grid); }
        }
        setTimeout(function () { self.resizeCharts(); }, 60);

        // 接上 MATLAB 数据；若在浏览器里单独打开则跑演示数据
        bridge.onData = function (d) { self.fromMatlab(d); };
        if (lastData) { this.fromMatlab(lastData); }
        if (!bridge.comp) {
          this.paramsReady = true;  // 浏览器预览没有 MATLAB 存档
          setTimeout(function () { if (!bridge.comp) { self.startDemo(); } }, 400);
        }
      },

      resizeCharts: function () {
        var self = this;
        if (this._rzPending) { return; }
        this._rzPending = true;
        requestAnimationFrame(function () {
          self._rzPending = false;
          CHART_KEYS.forEach(function (k) {
            var u = self.charts[k]; if (!u) { return; }
            var el = u.root.parentNode;
            if (!el) { return; }
            var w = el.clientWidth, h = el.clientHeight;
            // 尺寸没变就不要 setSize：uPlot 重画画布是闪烁的主要来源之一。
            if (w > 10 && h > 10 && (u.width !== w || u.height !== h)) {
              u.setSize({ width: w, height: h });
            }
          });
        });
      },

      // 切步骤页后格子才有尺寸；uPlot 在 display:none 里量到 0，必须补一次 resize。
      setTab: function (name) {
        if (!STEP_TABS[name]) { return; }
        this.tab = name;
        var self = this;
        this.$nextTick(function () {
          self.resizeCharts();
          setTimeout(function () { self.resizeCharts(); }, 50);
        });
      },

      /* 墙钟倒计时：MATLAB 在开射频时推 remain/total，USB 阻塞期间靠本地 ~4 Hz 补跳。 */
      applyCountdown: function (d) {
        if (!d || !d.on) {
          this.stopCountdown();
          return;
        }
        var remain = Number(d.remain_s);
        var total = Number(d.total_s);
        if (!isFinite(remain) || !isFinite(total) || total <= 0) {
          this.stopCountdown();
          return;
        }
        this.cdOn = true;
        this._cdTotal = total;
        this._cdSyncRemain = remain;
        this._cdSyncAt = Date.now();
        this.paintCountdown(remain);
        this.startCountdownTimer();
      },
      startCountdownTimer: function () {
        if (this._cdTimer) { return; }
        var self = this;
        this._cdTimer = setInterval(function () { self.tickCountdown(); }, 250);
      },
      tickCountdown: function () {
        if (!this.cdOn) { return; }
        var left = this._cdSyncRemain - (Date.now() - this._cdSyncAt) / 1000;
        this.paintCountdown(left);
      },
      paintCountdown: function (left) {
        if (typeof left !== 'number' || !isFinite(left)) { left = 0; }
        left = Math.max(0, left);
        this.cdClock = fmtMmSs(left);
        var sec = Math.floor(left + 1e-9);
        var tot = Math.round(this._cdTotal);
        this.cdSub = sec + ' / ' + tot + ' s';
      },
      stopCountdown: function () {
        this.cdOn = false;
        this.cdClock = '0:00';
        this.cdSub = '';
        this._cdSyncRemain = 0;
        this._cdTotal = 0;
        if (this._cdTimer) {
          clearInterval(this._cdTimer);
          this._cdTimer = null;
        }
      },
      // 动作事件带上点击那一刻的表单值：MATLAB 侧会先合并再跑，
      // 这样即使某个 params 事件还在路上，实验用的也是界面上看到的参数。
      action: function (name) {
        this.clampCaps(true);
        this.syncCavFromNcycle();
        if (bridge.comp && !this.paramsReady && ACTION_TAB[name]) {
          this.status = '参数尚未从 MATLAB 加载，请等「目标」框显示存档值再开闭环。';
          return;
        }
        // 已经在跑就不要再发 start：连点 / 页面闪一下 busy 丢失都会变成对话框风暴。
        if (ACTION_TAB[name] && this.busy) {
          if (this.runTab) { this.setTab(this.runTab); }
          return;
        }
        // 点步骤按钮立刻切到该步骤页，不必等 MATLAB 回 busy。
        if (ACTION_TAB[name] && !this.busy) {
          this.busy = true;          // 乐观锁：按钮立刻变成 STOP / disabled
          this.runTab = ACTION_TAB[name];
          this.setTab(this.runTab);
        }
        toMatlab('action', { name: name, params: this.p });
      },
      // live=false：逐键输入，只落盘、不下发到信号源；
      // live=true ：回车 / 失焦，算「确认」，调试采集会把新值立刻下发。
      // 不做这个区分的话，调试中打「150」会先输出 1 mVpp、再 15、再 150。
      pushParams: function (live) {
        this.clampCaps(!!live);
        toMatlab('params', { params: this.p, live: !!live });
      },
      // 把超限值写回 p.npts / p.n_cycle / p.amp_gain，Alpine x-model 才会把输入框改成实际会用的数。
      clampCaps: function (commitMin) {
        this.p.npts = clampInt(this.p.npts, NPTS_MIN, NPTS_MAX, !!commitMin);
        this.p.n_cycle = clampInt(this.p.n_cycle, NCYC_MIN, NCYC_MAX, !!commitMin);
        this.p.amp_gain = clampInt(this.p.amp_gain, AMP_GAIN_MIN, 1e6, !!commitMin);
      },
      /* 空化率 ↔ 周期数：改空化率更新周期数；改周期数 / 频率 / PRF 更新空化率。
       * 周期数四舍五入为整数，再截到 1–10000；截断后把真实空化率写回，框不说谎。 */
      syncCavFromNcycle: function () {
        var pct = cavPctFromNcycle(this.p.n_cycle, this.p.freq_mhz, this.p.prf_hz);
        if (typeof pct === 'number' && isFinite(pct)) {
          this.p.cav_pct = prettyPct(pct);
        }
      },
      syncNcycleFromCav: function (commitMin) {
        var n = ncycleFromCavPct(this.p.cav_pct, this.p.freq_mhz, this.p.prf_hz);
        if (typeof n === 'number' && isFinite(n)) {
          this.p.n_cycle = clampInt(n, NCYC_MIN, NCYC_MAX, !!commitMin);
        }
      },
      onCavPct: function (live) {
        this.syncNcycleFromCav(!!live);
        this.clampCaps(!!live);
        if (live) { this.syncCavFromNcycle(); }
        toMatlab('params', { params: this.p, live: !!live });
      },
      onNCycle: function (live) {
        this.clampCaps(!!live);
        this.syncCavFromNcycle();
        toMatlab('params', { params: this.p, live: !!live });
      },
      onDutyDrivers: function (live) {
        this.clampCaps(!!live);
        this.syncCavFromNcycle();
        toMatlab('params', { params: this.p, live: !!live });
      },
      /* V_load ≈ mVpp/1000 * amp_gain。闭环页按上限估，开环按治疗电压。 */
      ampLoadHint: function () {
        var v = Number(this.tab === 'fb' ? this.p.max_mVpp : this.p.volt_mVpp), g = Number(this.p.amp_gain);
        if (!isFinite(v) || !isFinite(g) || g <= 0) { return ''; }
        var vpp = v / 1000 * g;
        var t = Math.abs(vpp) >= 1 ? vpp.toFixed(1) : vpp.toFixed(2);
        var who = this.tab === 'fb' ? '上限 ' : '发生器 ';
        return who + v + ' mVpp ×' + g + ' → ' + t + ' Vpp';
      },
      scHarmHint: function () {
        var f = Number(this.p.freq_mhz), h = String(this.p.sc_harm || '2f');
        var n = 2;
        if (h === '3f') { n = 3; }
        else if (h === '1.5f') { n = 1.5; }
        else if (h === '1f') { n = 1; }
        else if (h === '0.5f') { n = 0.5; }
        if (!isFinite(f) || f <= 0) { return ''; }
        return (f * n).toFixed(2) + ' MHz';
      },

      /* ---- 接收 MATLAB ---- */
      fromMatlab: function (d) {
        if (!d || typeof d !== 'object') { return; }
        if (Array.isArray(d) && d.length) { d = d[0]; }
        if (!d || !d.cmd) { return; }
        // 任意命令都可附带 tab，用来在实验开始时切到对应步骤页。
        if (d.tab) { this.setTab(d.tab); }
        switch (d.cmd) {
          case 'init':
          case 'params':
            if (d.params) { Object.assign(this.p, d.params); }
            this.paramsReady = true;
            if (!this.p.ctrl_metric) { this.p.ctrl_metric = '2f_window_sum'; }
            if (!this.p.sc_harm) { this.p.sc_harm = '2f'; }
            if (!(typeof this.p.cav_pct === 'number' && isFinite(this.p.cav_pct))) {
              this.syncCavFromNcycle();
            }
            if (!(typeof this.p.amp_gain === 'number' && isFinite(this.p.amp_gain) && this.p.amp_gain > 0)) {
              this.p.amp_gain = AMP_GAIN_DEFAULT;
            }
            break;
          case 'status':
            if (d.text != null) { this.status = d.text; }
            break;
          case 'busy':
            this.busy = !!d.on;
            if (d.on && d.tab) { this.runTab = d.tab; }
            if (!d.on) {
              this.runTab = '';
              this.stopCountdown();
            }
            break;
          case 'tab':
            break;
          case 'countdown':
            this.applyCountdown(d);
            break;
          case 'frame':
            // 一帧里 CH1+CH2+状态（+趋势）一次推过来，避免三次 Data 刷新把页面闪没。
            if (d.tx) { this.setWave(d.tx); }
            if (d.pcd) { this.setWave(d.pcd); }
            if (d.trend) { this.pushTrend(d.trend); }
            if (d.text != null) { this.status = d.text; }
            break;
          case 'waveform':
            this.setWave(d);
            break;
          case 'trend':
            this.pushTrend(d);
            break;
          case 'clearTrend':
            this.trend = { x: [], sc: [], ic: [], volt: [] };
            this.redrawTrend();
            break;
        }
      },

      setWave: function (d) {
        var slot = inferCh(d);
        var t = slot === 'pcd' ? this.charts.timePcd : this.charts.timeTx;
        var dt = vec(d.dt_us), y = vec(d.y);
        if (t && dt && y && dt.length && y.length) {
          var n = Math.min(dt.length, y.length);
          t.setData([dt.slice(0, n), y.slice(0, n)]);
          var t0 = dt[0], t1 = dt[n - 1];
          if (typeof t0 === 'number' && typeof t1 === 'number' && t1 > t0) {
            t.setScale('x', { min: t0, max: t1 });
          }
          if (d.name) {
            var pp = (typeof d.pp_mV === 'number' && isFinite(d.pp_mV))
              ? ('  ' + (d.pp_mV >= 10 ? d.pp_mV.toFixed(1) : d.pp_mV.toFixed(2)) + ' mVpp')
              : '';
            var title = slot === 'pcd'
              ? ('CH2 时域  ·  ' + d.name + pp)
              : ('CH1 时域  ·  ' + d.name + pp);
            if (this.titles[slot] !== title) { this.titles[slot] = title; }
          }
        }
        var freq = vec(d.f), db = vec(d.db);
        // CH1 / CH2 各有一张 FFT，按 ch 分槽；不再把两路谱叠到同一张图上。
        if (freq && db && freq.length && db.length) {
          var fk = slot === 'pcd' ? 'fftPcd' : 'fftTx';
          var f = this.charts[fk];
          if (f) {
            var m = Math.min(freq.length, db.length);
            f.__marks = normalizeMarks(d.marks);
            f.__f0 = (typeof d.f0 === 'number' && isFinite(d.f0)) ? d.f0 : 0;
            f.setData([freq.slice(0, m), db.slice(0, m)]);
            f.setScale('x', { min: 0, max: fftXmax(d) });
          }
          if (d.fft_title) {
            if (this.titles[fk] !== d.fft_title) { this.titles[fk] = d.fft_title; }
          }
        }
      },

      pushTrend: function (d) {
        var tr = this.trend;
        tr.x.push(d.k); tr.sc.push(d.sc); tr.ic.push(d.ic); tr.volt.push(d.volt);
        if (tr.x.length > 20000) {   // 兜底，避免浏览器端无限增长
          ['x', 'sc', 'ic', 'volt'].forEach(function (k) { tr[k].shift(); });
        }
        this._trendWin = { xmax: d.xmax || (d.k + 5), ymax: d.ymax || 200 };
        this.redrawTrend();
      },

      redrawTrend: function () {
        var tr = this.trend;
        var win = this._trendWin || { xmax: 40, ymax: 200 };
        this._draw(this.charts.volt, tr.x, tr.volt, 0, voltYmax(tr.volt, win.ymax));
        var tgt = this.p && this.p.target_db;
        var scU = this.charts.sc;
        if (scU) { scU.__tgt_db = tgt; }
        var yr = scYlim(tr.sc, tgt);
        this._draw(scU, tr.x, tr.sc, yr.min, yr.max);
        this._draw(this.charts.ic, tr.x, tr.ic);
      },

      _draw: function (u, x, y, ymin, ymax) {
        if (!u) { return; }
        u.setData([x.slice(), y.slice()]);
        u.setScale('x', { min: 0, max: (this._trendWin ? this._trendWin.xmax : 40) });
        if (ymax !== undefined) { u.setScale('y', { min: ymin, max: ymax }); }
      },

      /* ---- 浏览器独立预览时的演示数据 ---- */
      startDemo: function () {
        var self = this;
        this.p.studyID = 'P0001';
        this.p.directory = 'C:\\Users\\lab\\PFC\\data';
        var Fs = 40e6, f0 = 1.5, nCyc = 16;
        var N = Math.round(nCyc * Fs / (f0 * 1e6));   // ~16 周期，与 MATLAB TX 上屏窗一致
        function wave() {
          var dt = [], y = [], i;
          for (i = 0; i < N; i++) {
            var t = i / Fs;
            dt.push(t * 1e6);
            y.push(0.18 * Math.sin(2 * Math.PI * f0 * 1e6 * t) + 0.006 * Math.sin(2 * Math.PI * 3e6 * t) + (Math.random() - .5) * 0.004);
          }
          return { dt: dt, y: y };
        }
        function pcdWave() {
          // 整段 ~1 ms 底噪，对应无微泡 CH2；不要截成 16 个「周期」
          var nP = 800, dt = [], y = [], i;
          for (i = 0; i < nP; i++) {
            var us = i / nP * 1000;
            dt.push(us);
            var burst = (us > 200 && us < 470) ? 0.0035 * Math.sin(2 * Math.PI * f0 * us) : 0;
            y.push(burst + (Math.random() - 0.5) * 0.0016);
          }
          return { dt: dt, y: y };
        }
        function spec(kind) {
          var f = [], db = [], i;
          for (i = 0; i <= 320; i++) {
            var mhz = i * 0.025;                        // 0 .. 8 MHz
            var v = -94 + 5 * (Math.random() + Math.random() - 1); // 底噪
            if (kind === 'pcd') {
              // 无微泡 CH2：没有大的 f0 驱动峰，2f/IC 也只比底噪略高
              if (Math.abs(mhz - f0) < .05) { v = -42; }
              if (Math.abs(mhz - 2 * f0) < .05) { v = -36; }
              if (Math.abs(mhz - 3 * f0) < .05) { v = -58; }
              if (Math.abs(mhz - 2.2 * f0) < .05) { v = -62; }
            } else {
              if (Math.abs(mhz - f0) < .05) { v = 22; }
              if (Math.abs(mhz - 2 * f0) < .05) { v = 8; }
              if (Math.abs(mhz - 3 * f0) < .05) { v = -26; }
              if (Math.abs(mhz - 2.2 * f0) < .05) { v = -38; }
            }
            f.push(mhz); db.push(v);
          }
          return { f: f, db: db };
        }
        var w = wave(), s = spec('tx'), sp = spec('pcd'), pcd = pcdWave();
        this.setWave({
          ch: 'tx', name: 'CH1 回读 TX',
          dt_us: w.dt, y: w.y, f: s.f, db: s.db, f0: f0, f_max: 8,
          fft_of: 'CH1 回读 TX',
          marks: [
            { f: 0.75, main: false }, { f: 1.5, main: false }, { f: 2.25, main: false },
            { f: 3.0, main: true }, { f: 3.75, main: false }, { f: 4.5, main: false }
          ]
        });
        this.setWave({
          ch: 'pcd', name: 'CH2 PCD',
          dt_us: pcd.dt, y: pcd.y, f: sp.f, db: sp.db, f0: f0, f_max: 8,
          marks: [
            { f: 0.75, main: false }, { f: 1.5, main: false }, { f: 2.25, main: false },
            { f: 3.0, main: true }, { f: 3.75, main: false }, { f: 4.5, main: false }
          ]
        });
        var k = 0, base = 0.35;
        this.status = '演示数据（未连接 MATLAB）';
        this._demo = setInterval(function () {
          k++;
          var sc = base * (1 + 0.35 * Math.min(1, k / 60)) * (0.9 + 0.2 * Math.random());
          var ic = 0.02 + 0.01 * Math.random();
          var volt = 50 + Math.min(70, k * 0.8);
          self.pushTrend({ k: k, sc: sc, ic: ic, volt: volt, xmax: Math.max(40, k + 8), ymax: Math.max(60, volt * 1.6) });
          self.status = '演示中  Pulse ' + k + ' / 400    SC(2f)=' + sc.toFixed(3) + '  IC=' + ic.toFixed(4) + '  V=' + Math.round(volt) + ' mVpp';
        }, 220);
      }
    };
  };

  /* ---------------- 频谱横轴上限 ---------------- */
  function fftXmax(d) {
    // 不要拉到 Nyquist。实验室关心 f0 / 2f(SC) / IC~2.2f / 3f，
    // 拉到 20–30 MHz 时这些峰全挤在左缘。与 MATLAB html_waveform 同一套公式。
    var nyq = 8;
    if (d.f && d.f.length) {
      var last = d.f[d.f.length - 1];
      if (typeof last === 'number' && isFinite(last) && last > 0) { nyq = last; }
    }
    var cap = 8;
    if (typeof d.f_max === 'number' && isFinite(d.f_max) && d.f_max > 0) {
      cap = d.f_max;
    } else if (typeof d.f0 === 'number' && isFinite(d.f0) && d.f0 > 0) {
      cap = Math.max(8, 5 * d.f0);
    }
    return Math.min(nyq, cap);
  }

  /* ---------------- 频谱谐波标记线 ---------------- */
  function unwrapMark(v) {
    while (v && typeof v !== 'string' && typeof v !== 'number' &&
        Array.isArray(v) && v.length === 1) {
      v = v[0];
    }
    if (Array.isArray(v) && v.length && typeof v[0] === 'string') {
      return v.join('').replace(/\s+/g, '');
    }
    if (typeof v === 'string') { return v.replace(/\s+/g, ''); }
    return v;
  }

  function normalizeMarks(raw) {
    if (raw == null) { return []; }
    var src = raw;
    if (Array.isArray(raw) && raw.length === 1 && raw[0] && raw[0].f != null &&
        (Array.isArray(raw[0].f) || (raw[0].f && raw[0].f.length > 1))) {
      src = raw[0];
    }
    if (src && src.f != null && typeof src.f === 'object' && typeof src.f.length === 'number' &&
        src.f.length > 1 && (typeof src.f[0] === 'number' || (src.f[0] && src.f[0].length))) {
      var n = src.f.length, out = [], i;
      for (i = 0; i < n; i++) {
        out.push({
          f: unwrapMark(src.f[i]),
          main: unwrapMark(src.main ? src.main[i] : 0),
          kind: unwrapMark(src.kind ? src.kind[i] : ''),
          label: unwrapMark(src.label ? src.label[i] : '')
        });
      }
      return out;
    }
    if (!Array.isArray(raw)) { return [raw]; }
    return Array.prototype.slice.call(raw).map(function (m) {
      if (!m || typeof m !== 'object') { return { f: m }; }
      return {
        f: unwrapMark(m.f),
        main: unwrapMark(m.main),
        kind: unwrapMark(m.kind),
        label: unwrapMark(m.label)
      };
    });
  }

  function drawMarks(u) {
    var marks = normalizeMarks(u.__marks);
    if (!marks.length) { return; }
    var ctx = u.ctx, bb = u.bbox;
    var f0 = (typeof u.__f0 === 'number' && u.__f0 > 0) ? u.__f0 : 0;
    ctx.save();
    ctx.beginPath();
    ctx.rect(bb.left, bb.top, bb.width, bb.height);
    ctx.clip();
    marks.forEach(function (m) {
      var fv = unwrapMark(m.f);
      if (typeof fv !== 'number' || !isFinite(fv)) { return; }
      var x = u.valToPos(fv, 'x', true);
      if (x < bb.left || x > bb.left + bb.width) { return; }
      var kind = String(m.kind || '');
      var lab0 = String(m.label || '');
      var emi = kind === 'emi' || m.emi === true || m.emi === 1;
      var isIc = kind === 'ic' || lab0.indexOf('IC') === 0;
      // 2*f0 = 3 MHz：任何形式都不画竖线（白线会盖住峰）。
      var is2f = kind === 'sc' || kind === '2f' || lab0 === 'SC' || lab0 === '2f' ||
        lab0.indexOf('SC') === 0 || (f0 > 0 && Math.abs(fv - 2 * f0) < 0.12);
      x = Math.round(x) + 0.5;
      if (!is2f) {
        ctx.beginPath();
        ctx.setLineDash(emi ? [4, 3] : [2, 3]);
        ctx.strokeStyle = emi ? '#C4A35A' : (isIc ? '#7EB6C9' : C.ref);
        ctx.lineWidth = 1;
        ctx.moveTo(x, bb.top);
        ctx.lineTo(x, bb.top + bb.height);
        ctx.stroke();
      }
      var lab = lab0;
      if (!lab && is2f) { lab = 'SC'; }
      if (!lab && emi) { lab = '干扰'; }
      if (lab) {
        ctx.setLineDash([]);
        ctx.fillStyle = emi ? '#C4A35A' : (is2f ? C.line : (isIc ? '#7EB6C9' : C.muted));
        ctx.font = '11px ui-sans-serif, system-ui, sans-serif';
        ctx.textAlign = 'center';
        ctx.textBaseline = 'top';
        ctx.fillText(lab, x, is2f ? bb.top + 2 : (isIc ? bb.top + 14 : bb.top + 2));
      }
    });
    // 即使 MATLAB 没发 SC 标记，也在 2f 处写字、不画线
    if (f0 > 0) {
      var x2 = u.valToPos(2 * f0, 'x', true);
      if (x2 >= bb.left && x2 <= bb.left + bb.width) {
        ctx.setLineDash([]);
        ctx.fillStyle = C.line;
        ctx.font = '11px ui-sans-serif, system-ui, sans-serif';
        ctx.textAlign = 'center';
        ctx.textBaseline = 'top';
        ctx.fillText('SC', Math.round(x2) + 0.5, bb.top + 2);
      }
    }
    ctx.restore();
  }
})();
