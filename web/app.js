/* ============================================================
 * PFC 前端逻辑：Alpine 状态 + uPlot 图表 + 与 MATLAB(uihtml) 的桥接
 *
 * 两种运行方式：
 *   1) 在 MATLAB 里（uihtml 宿主）  -> MATLAB 调用 setup()，双向通信
 *   2) 直接在浏览器打开（离线预览） -> 无 bridge，自动跑演示数据
 * 协议：
 *   MATLAB -> JS : htmlComponent.Data = {cmd:'init'|'status'|'busy'|'waveform'|'trend'|...}
 *   JS -> MATLAB : sendEventToMATLAB('action',{name}) / ('params',{...})
 * ============================================================ */
(function () {
  'use strict';

  /* ---------------- 与 MATLAB 的通道 ---------------- */
  var bridge = { comp: null, onData: null };
  var lastData = null;

  function deliver(d) {
    lastData = d;
    if (bridge.onData && d) { bridge.onData(d); }
  }

  // MATLAB 在加载 HTML 后自动调用这个全局函数（约定名，不能改）
  window.setup = function (htmlComponent) {
    bridge.comp = htmlComponent;
    htmlComponent.addEventListener('DataChanged', function () {
      deliver(htmlComponent.Data);
    });
    // MATLAB 可能在页面加载前就写过 Data，这里补取一次
    if (htmlComponent.Data !== undefined && htmlComponent.Data !== null) {
      deliver(htmlComponent.Data);
    }
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
    line: '#78ADF2', ref: '#6B788C', text: '#E6EAEF'
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
    var w = el.clientWidth || 400, h = el.clientHeight || 180;
    return new uPlot(Object.assign({
      width: w, height: h, legend: { show: false },
      cursor: { show: false, drag: { x: false, y: false, setScale: false } },
      scales: { x: { time: false } }
    }, opts), [[], []], el);
  }

  /* ---------------- Alpine 组件 ---------------- */
  window.pfcApp = function () {
    return {
      busy: false,
      status: '就绪 / Ready',
      // 字段名与 MATLAB 侧存档（pfc_gui_params）完全一致，两边共用一套词汇
      p: {
        studyID: '', directory: '',
        dbg_freq: 1.5, dbg_volt: 20,
        freq_mhz: 1.5, volt_mVpp: 50, prf_hz: 2, n_cycle: 400, duration_s: 120, npts: 40000,
        target_db: 2, max_mVpp: 120
      },
      charts: {},
      trend: { x: [], sc: [], ic: [], volt: [] },
      _demo: null,

      /* ---- 初始化 ---- */
      init: function () {
        var self = this;
        this.charts.time  = mkChart(this.$el.querySelector('#ch-time'),
          { axes: [axisX('Time (µs)'), axisY('V')], series: [{}, lineSeries()] });
        this.charts.fft   = mkChart(this.$el.querySelector('#ch-fft'),
          { axes: [axisX('Frequency (MHz)'), axisY('dB')], series: [{}, lineSeries()],
            hooks: { draw: [function (u) { drawMarks(u); }] } });
        this.charts.volt  = mkChart(this.$el.querySelector('#ch-volt'),
          { axes: [axisX('Pulse #'), axisY('mVpp')], series: [{}, dotSeries()] });
        this.charts.sc    = mkChart(this.$el.querySelector('#ch-sc'),
          { axes: [axisX('Pulse #'), axisY('SC')], series: [{}, dotSeries()] });
        this.charts.ic    = mkChart(this.$el.querySelector('#ch-ic'),
          { axes: [axisX('Pulse #'), axisY('IC')], series: [{}, dotSeries()] });

        window.addEventListener('resize', function () { self.resizeCharts(); });
        // uihtml 改尺寸经常不触发 window.resize；图表格子自己变了再跟上。
        if (typeof ResizeObserver !== 'undefined') {
          var ro = new ResizeObserver(function () { self.resizeCharts(); });
          ['#ch-time', '#ch-fft', '#ch-volt', '#ch-sc', '#ch-ic'].forEach(function (sel) {
            var el = self.$el.querySelector(sel);
            if (el) { ro.observe(el); }
          });
        }
        setTimeout(function () { self.resizeCharts(); }, 60);

        // 接上 MATLAB 数据；若在浏览器里单独打开则跑演示数据
        bridge.onData = function (d) { self.fromMatlab(d); };
        if (lastData) { this.fromMatlab(lastData); }
        setTimeout(function () { if (!bridge.comp) { self.startDemo(); } }, 400);
      },

      resizeCharts: function () {
        var self = this;
        if (this._rzPending) { return; }
        this._rzPending = true;
        requestAnimationFrame(function () {
          self._rzPending = false;
          ['time', 'fft', 'volt', 'sc', 'ic'].forEach(function (k) {
            var u = self.charts[k]; if (!u) { return; }
            var el = u.root.parentNode;
            var w = el.clientWidth, h = el.clientHeight;
            if (w > 10 && h > 10) { u.setSize({ width: w, height: h }); }
          });
        });
      },

      /* ---- 发给 MATLAB ---- */
      // 动作事件带上点击那一刻的表单值：MATLAB 侧会先合并再跑，
      // 这样即使某个 params 事件还在路上，实验用的也是界面上看到的参数。
      action: function (name) { toMatlab('action', { name: name, params: this.p }); },
      // live=false：逐键输入，只落盘、不下发到信号源；
      // live=true ：回车 / 失焦，算「确认」，调试采集会把新值立刻下发。
      // 不做这个区分的话，调试中打「150」会先输出 1 mVpp、再 15、再 150。
      pushParams: function (live) {
        toMatlab('params', { params: this.p, live: !!live });
      },

      /* ---- 接收 MATLAB ---- */
      fromMatlab: function (d) {
        if (!d || !d.cmd) { return; }
        switch (d.cmd) {
          case 'init':
          case 'params':
            if (d.params) { Object.assign(this.p, d.params); }
            break;
          case 'status':
            this.status = d.text || '';
            break;
          case 'busy':
            this.busy = !!d.on;
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
        var t = this.charts.time, f = this.charts.fft;
        if (t && d.dt_us && d.y) {
          t.setData([d.dt_us, d.y]);
          t.setScale('x', { min: d.dt_us[0], max: d.dt_us[d.dt_us.length - 1] });
        }
        if (f && d.f && d.db) {
          f.__marks = (d.marks || []).slice();
          f.setData([d.f, d.db]);
          var lo = 0, hi = d.f[d.f.length - 1];
          f.setScale('x', { min: lo, max: hi });
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
        this._draw(this.charts.volt, tr.x, tr.volt, 0, win.ymax);
        this._draw(this.charts.sc, tr.x, tr.sc);
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
        var Fs = 40e6, N = 1200, f0 = 1.5;
        function wave() {
          var dt = [], y = [], i;
          for (i = 0; i < N; i++) {
            var t = i / Fs;
            dt.push(t * 1e6);
            y.push(0.18 * Math.sin(2 * Math.PI * f0 * 1e6 * t) + 0.006 * Math.sin(2 * Math.PI * 3e6 * t) + (Math.random() - .5) * 0.004);
          }
          return { dt: dt, y: y };
        }
        function spec() {
          var f = [], db = [], i;
          for (i = 0; i <= 400; i++) {
            var mhz = i * 0.025;                        // 0 .. 10 MHz
            var v = -94 + 5 * (Math.random() + Math.random() - 1); // 底噪
            if (Math.abs(mhz - f0) < .05) { v = 22; }
            if (Math.abs(mhz - 2 * f0) < .05) { v = 8; }
            if (Math.abs(mhz - 3 * f0) < .05) { v = -26; }
            if (Math.abs(mhz - 2.2 * f0) < .05) { v = -38; }
            f.push(mhz); db.push(v);
          }
          return { f: f, db: db };
        }
        var w = wave(), s = spec();
        this.setWave({
          dt_us: w.dt, y: w.y, f: s.f, db: s.db,
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

  /* ---------------- 频谱谐波标记线 ---------------- */
  function drawMarks(u) {
    var marks = u.__marks;
    if (!marks || !marks.length) { return; }
    var ctx = u.ctx, bb = u.bbox;
    ctx.save();
    ctx.beginPath();
    ctx.rect(bb.left, bb.top, bb.width, bb.height);
    ctx.clip();
    marks.forEach(function (m) {
      var x = u.valToPos(m.f, 'x', true);
      if (x < bb.left || x > bb.left + bb.width) { return; }
      ctx.beginPath();
      ctx.setLineDash(m.main ? [] : [2, 3]);
      ctx.strokeStyle = m.main ? C.line : C.ref;
      ctx.lineWidth = m.main ? 2 : 1;
      x = Math.round(x) + 0.5;
      ctx.moveTo(x, bb.top);
      ctx.lineTo(x, bb.top + bb.height);
      ctx.stroke();
    });
    ctx.restore();
  }
})();
