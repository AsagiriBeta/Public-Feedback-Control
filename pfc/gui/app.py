"""主界面：分区布局对齐 DG2000-Trigger（连接 / 参数 / 动作 / 波形 / 日志）。"""

from __future__ import annotations

import sys
from pathlib import Path

from PySide6.QtCore import QSettings, QSize, Qt, QThread, Signal, Slot
from PySide6.QtGui import QCloseEvent, QColor, QGuiApplication, QKeySequence, QPalette, QShortcut, QShowEvent
from PySide6.QtWidgets import (
    QApplication,
    QComboBox,
    QDoubleSpinBox,
    QFileDialog,
    QFormLayout,
    QFrame,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QLayout,
    QLineEdit,
    QMainWindow,
    QMessageBox,
    QPlainTextEdit,
    QPushButton,
    QScrollArea,
    QSizePolicy,
    QSpinBox,
    QSplitter,
    QStatusBar,
    QVBoxLayout,
    QWidget,
)

from pfc import __version__
from pfc.config import AppConfig, load_config, save_config
from pfc.experiment.runner import ExperimentParams, ExperimentRunner, PulseUpdate, connect_instruments
from pfc.gui.plots import PlotPanel
from pfc.gui.style import QSS
from pfc.instruments.visa_io import discover_instruments


class _PrefScroll(QScrollArea):
    """按内部控件的 sizeHint 要高度，窗口变矮时再出现滚动条而不是压缩行高。"""

    def sizeHint(self) -> QSize:
        inner = self.widget()
        if inner is None:
            return super().sizeHint()
        hint = inner.sizeHint()
        frame = self.frameWidth() * 2
        return QSize(400, hint.height() + frame)

    def minimumSizeHint(self) -> QSize:
        return QSize(340, 240)


class Worker(QThread):
    pulse = Signal(object)
    status = Signal(str)
    done = Signal(str)
    failed = Signal(str)

    def __init__(self, runner: ExperimentRunner, mode: str):
        super().__init__()
        self.runner = runner
        self.mode = mode

    def run(self) -> None:
        try:
            result = self.runner.run(self.mode)  # type: ignore[arg-type]
            self.done.emit(result.path)
        except Exception as exc:  # noqa: BLE001
            self.failed.emit(str(exc))


class MainWindow(QMainWindow):
    def __init__(self, cfg: AppConfig):
        super().__init__()
        self.cfg = cfg
        self.scope = None
        self.awg = None
        self.worker: Worker | None = None
        self.runner: ExperimentRunner | None = None
        self._settings = QSettings("pfc", "pfc")
        self._scope_txt = "—"
        self._awg_txt = "—"
        self.setWindowTitle(f"PFC 闭环空化控制  v{__version__}")
        self.setMinimumSize(960, 700)
        self.resize(1280, 860)
        self._top: QWidget | None = None
        self._build()
        self._load_fields()
        QShortcut(QKeySequence("Escape"), self, activated=self.on_stop)

    def _build(self) -> None:
        root = QWidget()
        self.setCentralWidget(root)
        outer = QVBoxLayout(root)
        outer.setContentsMargins(10, 8, 10, 8)
        outer.setSpacing(6)

        outer.addLayout(self._build_header())

        conn = self._build_connection_box()
        params = self._build_params_box()
        actions = self._build_actions_box()

        params_host = QWidget()
        ph = QVBoxLayout(params_host)
        ph.setContentsMargins(0, 0, 0, 0)
        ph.setSpacing(0)
        ph.setSizeConstraint(QLayout.SizeConstraint.SetMinimumSize)
        ph.addWidget(params)
        self._top = params_host

        left_scroll = _PrefScroll()
        left_scroll.setWidget(params_host)
        left_scroll.setWidgetResizable(True)
        left_scroll.setFrameShape(QFrame.Shape.NoFrame)
        left_scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        left_scroll.setVerticalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAsNeeded)

        left = QWidget()
        left.setMinimumWidth(340)
        left_lay = QVBoxLayout(left)
        left_lay.setContentsMargins(0, 0, 0, 0)
        left_lay.setSpacing(8)
        left_lay.addWidget(conn)
        left_lay.addWidget(left_scroll, 1)
        left_lay.addWidget(actions)

        plots_split = QSplitter(Qt.Orientation.Vertical)
        plots_split.setChildrenCollapsible(False)
        self.plots = PlotPanel()
        plots_split.addWidget(self.plots)
        plots_split.addWidget(self._build_log_box())
        plots_split.setStretchFactor(0, 4)
        plots_split.setStretchFactor(1, 1)
        plots_split.setSizes([560, 140])

        hsplit = QSplitter(Qt.Orientation.Horizontal)
        hsplit.setChildrenCollapsible(False)
        hsplit.addWidget(left)
        hsplit.addWidget(plots_split)
        hsplit.setStretchFactor(0, 0)
        hsplit.setStretchFactor(1, 1)
        hsplit.setSizes([400, 860])
        outer.addWidget(hsplit, 1)

        bar = QStatusBar()
        self.setStatusBar(bar)
        bar.showMessage("未连接仪器")

    def showEvent(self, event: QShowEvent) -> None:
        super().showEvent(event)
        if self._top is not None:
            self._top.adjustSize()
            self._top.setMinimumHeight(self._top.sizeHint().height())

    def _build_header(self) -> QHBoxLayout:
        row = QHBoxLayout()
        title = QLabel("PFC  ·  DHO814 / DG2052")
        title.setStyleSheet("font-size: 15px; font-weight: 700; color: #e6c35c;")
        row.addWidget(title)
        row.addStretch(1)
        ver = QLabel(f"版本: v{__version__}")
        ver.setAlignment(Qt.AlignmentFlag.AlignRight | Qt.AlignmentFlag.AlignVCenter)
        ver.setStyleSheet("color: #9aa3ad;")
        row.addWidget(ver)
        return row

    def _build_connection_box(self) -> QGroupBox:
        box = QGroupBox("连接")
        box.setSizePolicy(QSizePolicy.Policy.Preferred, QSizePolicy.Policy.Maximum)
        col = QVBoxLayout(box)
        col.setContentsMargins(10, 8, 10, 8)
        col.setSpacing(6)
        col.setSizeConstraint(QLayout.SizeConstraint.SetMinimumSize)

        self.combo_scope = self._resource_combo()
        self.combo_awg = self._resource_combo()
        form = _form()
        form.addRow("示波器", self.combo_scope)
        form.addRow("信号源", self.combo_awg)
        col.addLayout(form)

        self.chk_sim = QComboBox()
        self.chk_sim.addItems(["硬件", "仿真"])
        self.chk_sim.setCurrentIndex(1 if self.cfg.simulate else 0)
        self.chk_sim.setFixedWidth(88)
        _lock_height(self.chk_sim)

        self.btn_scan = QPushButton("扫描设备")
        self.btn_scan.clicked.connect(self.on_scan)
        self.btn_connect = QPushButton("连接")
        self.btn_connect.setObjectName("primary")
        self.btn_connect.clicked.connect(self.on_connect)
        self.btn_disc = QPushButton("断开")
        self.btn_disc.clicked.connect(self.on_disconnect)
        self.btn_test = QPushButton("自检")
        self.btn_test.clicked.connect(self.on_selftest)

        btns = QHBoxLayout()
        btns.setSpacing(6)
        btns.addWidget(self.btn_scan)
        btns.addWidget(self.btn_connect)
        btns.addWidget(self.btn_disc)
        btns.addWidget(self.btn_test)
        col.addLayout(btns)

        self.status_edit = QLineEdit("未连接")
        self.status_edit.setReadOnly(True)
        _lock_height(self.status_edit)
        meta = QHBoxLayout()
        meta.setSpacing(6)
        meta.addWidget(QLabel("模式"))
        meta.addWidget(self.chk_sim)
        meta.addWidget(QLabel("状态"))
        meta.addWidget(self.status_edit, 1)
        col.addLayout(meta)

        self.ed_dir = QLineEdit()
        _lock_height(self.ed_dir)
        btn_dir = QPushButton("…")
        btn_dir.setObjectName("compact")
        btn_dir.setFixedSize(36, 28)
        btn_dir.clicked.connect(self.on_pick_dir)
        self.ed_id = QLineEdit()
        self.ed_id.setMaximumWidth(120)
        _lock_height(self.ed_id)
        paths = QHBoxLayout()
        paths.setSpacing(6)
        paths.addWidget(QLabel("保存"))
        paths.addWidget(self.ed_dir, 1)
        paths.addWidget(btn_dir)
        paths.addWidget(QLabel("编号"))
        paths.addWidget(self.ed_id)
        col.addLayout(paths)
        return box

    def _build_params_box(self) -> QGroupBox:
        box = QGroupBox("参数")
        box.setSizePolicy(QSizePolicy.Policy.Preferred, QSizePolicy.Policy.Maximum)
        col = QVBoxLayout(box)
        col.setContentsMargins(10, 8, 10, 8)
        col.setSpacing(8)
        col.setSizeConstraint(QLayout.SizeConstraint.SetMinimumSize)
        pair = QHBoxLayout()
        pair.setSpacing(12)
        pair.addLayout(self._drive_col(), 1)
        pair.addLayout(self._loop_col(), 1)
        col.addLayout(pair)
        col.addLayout(self._instr_col())
        return box

    def _drive_col(self) -> QVBoxLayout:
        f = _form()
        self.sp_freq = self._double(0.01, 50.0, 3, " MHz")
        self.sp_volt = self._double(1.0, 10000.0, 1, " mVpp")
        self.sp_prf = self._double(0.01, 1000.0, 2, " Hz")
        self.sp_burst = _spin(1, 500000)
        self.sp_npts = _spin(100, 10_000_000, step=1000)
        f.addRow("频率", self.sp_freq)
        f.addRow("幅度", self.sp_volt)
        f.addRow("PRF", self.sp_prf)
        f.addRow("周期数", self.sp_burst)
        f.addRow("采样点", self.sp_npts)
        return _section("激励", f)

    def _loop_col(self) -> QVBoxLayout:
        f = _form()
        self.sp_dur = self._double(1.0, 3600.0, 1, " s")
        self.sp_mb = self._double(0.0, 600.0, 1, " s")
        self.sp_tgt = self._double(0.0, 40.0, 2, " dB")
        self.sp_maxv = self._double(1.0, 10000.0, 1, " mV")
        f.addRow("治疗时长", self.sp_dur)
        f.addRow("MB 等待", self.sp_mb)
        f.addRow("目标 SC", self.sp_tgt)
        f.addRow("电压上限", self.sp_maxv)
        return _section("闭环", f)

    def _instr_col(self) -> QVBoxLayout:
        f = _form()
        self.sp_sch = _spin(1, 4)
        self.sp_ach = _spin(1, 2)
        self.combo_load = QComboBox()
        self.combo_load.addItems(["50", "INFinity"])
        _lock_height(self.combo_load)
        self.combo_trigsrc = QComboBox()
        self.combo_trigsrc.addItems(["PCD 通道", "AWG 同步"])
        self.combo_trigsrc.setMinimumContentsLength(8)
        _lock_height(self.combo_trigsrc)
        self.sp_trigch = _spin(1, 4)
        self.sp_vdiv = self._double(0.0005, 10.0, 4, " V/div")
        self.sp_trig = self._double(-20.0, 20.0, 4, " V")
        f.addRow("示波器 CH", self.sp_sch)
        f.addRow("信号源 CH", self.sp_ach)
        f.addRow("AWG 负载", self.combo_load)
        f.addRow("触发源", self.combo_trigsrc)
        f.addRow("同步 CH", self.sp_trigch)
        f.addRow("垂直档位", self.sp_vdiv)
        f.addRow("触发电平", self.sp_trig)
        return _section("仪器", f)

    def _build_actions_box(self) -> QGroupBox:
        box = QGroupBox("动作")
        box.setSizePolicy(QSizePolicy.Policy.Preferred, QSizePolicy.Policy.Maximum)
        col = QVBoxLayout(box)
        col.setContentsMargins(10, 8, 10, 8)
        col.setSpacing(6)
        col.setSizeConstraint(QLayout.SizeConstraint.SetMinimumSize)
        self.btn_init = QPushButton("初始化信号源")
        self.btn_init.clicked.connect(self.on_init_awg)
        self.btn_pcd = QPushButton("PCD 基线")
        self.btn_pcd.setObjectName("primary")
        self.btn_pcd.clicked.connect(lambda: self.start_run("pcd"))
        self.btn_son = QPushButton("闭环超声")
        self.btn_son.setObjectName("primary")
        self.btn_son.clicked.connect(lambda: self.start_run("sonication"))
        self.btn_stop = QPushButton("停止")
        self.btn_stop.setObjectName("danger")
        self.btn_stop.clicked.connect(self.on_stop)
        row = QHBoxLayout()
        row.setSpacing(6)
        row.addWidget(self.btn_init, 1)
        row.addWidget(self.btn_pcd, 1)
        col.addLayout(row)
        row2 = QHBoxLayout()
        row2.setSpacing(6)
        row2.addWidget(self.btn_son, 1)
        row2.addWidget(self.btn_stop, 1)
        col.addLayout(row2)
        self.lbl_pulse = QLabel("pulse  —")
        self.lbl_pulse.setObjectName("readout")
        self.lbl_pulse.setMinimumHeight(28)
        self.lbl_pulse.setWordWrap(True)
        self.lbl_pulse.setTextInteractionFlags(Qt.TextInteractionFlag.TextSelectableByMouse)
        col.addWidget(self.lbl_pulse)
        return box

    def _build_log_box(self) -> QGroupBox:
        box = QGroupBox("日志")
        lay = QVBoxLayout(box)
        lay.setContentsMargins(10, 8, 10, 8)
        self.log = QPlainTextEdit()
        self.log.setReadOnly(True)
        self.log.setMinimumHeight(56)
        self.log.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Preferred)
        lay.addWidget(self.log)
        return box

    @staticmethod
    def _resource_combo() -> QComboBox:
        w = QComboBox()
        w.setEditable(True)
        w.setInsertPolicy(QComboBox.InsertPolicy.NoInsert)
        w.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed)
        w.setMinimumContentsLength(12)
        w.setSizeAdjustPolicy(QComboBox.SizeAdjustPolicy.AdjustToMinimumContentsLengthWithIcon)
        _lock_height(w)
        return w

    @staticmethod
    def _double(lo: float, hi: float, decimals: int, suffix: str) -> QDoubleSpinBox:
        w = QDoubleSpinBox()
        w.setDecimals(decimals)
        w.setRange(lo, hi)
        w.setSuffix(suffix)
        w.setMinimumWidth(110)
        w.setKeyboardTracking(False)
        _lock_height(w)
        return w

    def _load_fields(self) -> None:
        e = self.cfg.experiment
        i = self.cfg.instrument
        self.ed_dir.setText(e.save_dir or str(Path.home() / "PFC_data"))
        self.ed_dir.setCursorPosition(0)
        self.ed_id.setText(e.study_id)
        self.sp_freq.setValue(e.frequency_mhz)
        self.sp_volt.setValue(e.voltage_mVpp)
        self.sp_prf.setValue(e.prf_hz)
        self.sp_burst.setValue(e.burst_count)
        self.sp_npts.setValue(e.sample_points)
        self.sp_dur.setValue(e.duration_s)
        self.sp_mb.setValue(e.mb_load_time_s)
        self.sp_tgt.setValue(e.controller_target_db)
        self.sp_maxv.setValue(e.max_voltage_mV)
        self.sp_sch.setValue(i.scope_channel)
        self.sp_ach.setValue(i.awg_channel)
        self.combo_load.setCurrentText("50" if i.awg_load in ("50", "50.0") else "INFinity")
        self.combo_trigsrc.setCurrentIndex(1 if i.scope_trig_source.lower() == "sync" else 0)
        self.sp_trigch.setValue(i.scope_trig_channel)
        self.sp_vdiv.setValue(i.vertical_scale_v)
        self.sp_trig.setValue(i.trigger_level_v)
        scope_res = str(self._settings.value("scope_visa", i.scope_visa) or i.scope_visa)
        awg_res = str(self._settings.value("awg_visa", i.awg_visa) or i.awg_visa)
        self.combo_scope.setEditText(scope_res)
        self.combo_awg.setEditText(awg_res)

    def _sync_cfg(self) -> None:
        e = self.cfg.experiment
        i = self.cfg.instrument
        e.save_dir = self.ed_dir.text().strip()
        e.study_id = self.ed_id.text().strip() or "study"
        e.frequency_mhz = self.sp_freq.value()
        e.voltage_mVpp = self.sp_volt.value()
        e.prf_hz = self.sp_prf.value()
        e.burst_count = self.sp_burst.value()
        e.sample_points = self.sp_npts.value()
        e.duration_s = self.sp_dur.value()
        e.mb_load_time_s = self.sp_mb.value()
        e.controller_target_db = self.sp_tgt.value()
        e.max_voltage_mV = self.sp_maxv.value()
        i.scope_channel = self.sp_sch.value()
        i.awg_channel = self.sp_ach.value()
        i.awg_load = self.combo_load.currentText()
        i.scope_trig_source = "sync" if self.combo_trigsrc.currentIndex() == 1 else "pcd"
        i.scope_trig_channel = self.sp_trigch.value()
        i.vertical_scale_v = self.sp_vdiv.value()
        i.trigger_level_v = self.sp_trig.value()
        i.scope_visa = self._combo_resource(self.combo_scope)
        i.awg_visa = self._combo_resource(self.combo_awg)
        self.cfg.simulate = self.chk_sim.currentIndex() == 1

    @staticmethod
    def _combo_resource(combo: QComboBox) -> str:
        text = combo.currentText().strip()
        if not text or text.upper() == "AUTO":
            return "AUTO"
        for part in reversed(text.split()):
            if "::" in part:
                return part
        data = combo.currentData()
        if isinstance(data, str) and data:
            return data
        return text

    def _params(self) -> ExperimentParams:
        self._sync_cfg()
        e = self.cfg.experiment
        return ExperimentParams(
            frequency_mhz=e.frequency_mhz,
            voltage_mVpp=e.voltage_mVpp,
            prf_hz=e.prf_hz,
            burst_count=e.burst_count,
            duration_s=e.duration_s,
            sample_points=e.sample_points,
            mb_load_time_s=e.mb_load_time_s,
            controller_target_db=e.controller_target_db,
            max_voltage_mV=e.max_voltage_mV,
            study_id=e.study_id,
            save_dir=e.save_dir,
            pcd_duration_s=e.pcd_duration_s,
            baseline_duration_s=e.baseline_duration_s,
            baseline_voltage_mV=e.baseline_voltage_mV,
            voltage_step_mV=e.voltage_step_mV,
            maintain_tol_db=e.maintain_tol_db,
        )

    def _log(self, msg: str) -> None:
        self.log.appendPlainText(msg)
        self.statusBar().showMessage(msg.split("\n", 1)[0])

    def _refresh_status(self) -> None:
        self.status_edit.setText(f"示波器 {self._scope_txt}    |    信号源 {self._awg_txt}")

    def _set_led(self, _label: QLabel | None, name: str, ok: bool, text: str) -> None:
        short = text.strip() if ok else "—"
        if name.startswith("示波"):
            self._scope_txt = short
        else:
            self._awg_txt = short
        self._refresh_status()

    def _busy(self, running: bool) -> None:
        for w in (
            self.btn_init,
            self.btn_pcd,
            self.btn_son,
            self.btn_test,
            self.btn_scan,
            self.btn_connect,
            self.chk_sim,
        ):
            w.setEnabled(not running)

    @Slot()
    def on_pick_dir(self) -> None:
        d = QFileDialog.getExistingDirectory(self, "选择保存目录", self.ed_dir.text())
        if d:
            self.ed_dir.setText(d)

    @Slot()
    def on_scan(self) -> None:
        self._sync_cfg()
        if self.cfg.simulate:
            self._log("仿真模式：跳过 VISA 扫描")
            return
        try:
            found = discover_instruments(self.cfg.instrument.visa_backend)
        except Exception as exc:  # noqa: BLE001
            QMessageBox.warning(self, "扫描失败", str(exc))
            return
        if not found:
            self._log("未发现 VISA 设备")
            return
        self._fill_resource_combo(self.combo_scope, [d for d in found if d.kind == "scope"], found)
        self._fill_resource_combo(self.combo_awg, [d for d in found if d.kind == "awg"], found)
        lines = [f"{d.kind:5s}  {d.resource}  {d.idn}" for d in found]
        self._log("扫描结果：\n" + "\n".join(lines))

    def _fill_resource_combo(self, combo: QComboBox, preferred, all_found) -> None:
        current = combo.currentText().strip()
        combo.clear()
        combo.addItem("AUTO")
        seen = set()
        for d in list(preferred) + list(all_found):
            if d.resource in seen:
                continue
            seen.add(d.resource)
            model = d.idn.split(",")[1].strip() if d.idn and "," in d.idn else d.kind
            combo.addItem(f"{model}  {d.resource}", d.resource)
        if current:
            combo.setEditText(current)

    @Slot()
    def on_connect(self) -> None:
        self._sync_cfg()
        self.on_disconnect()
        try:
            self.scope, self.awg, sidn, aidn = connect_instruments(self.cfg)
        except Exception as exc:  # noqa: BLE001
            QMessageBox.critical(self, "连接失败", str(exc))
            return
        smodel = sidn.split(",")[1].strip() if "," in sidn else sidn
        amodel = aidn.split(",")[1].strip() if "," in aidn else aidn
        self._set_led(None, "示波器", True, smodel)
        self._set_led(None, "信号源", True, amodel)
        self._log(f"已连接\n  {sidn}\n  {aidn}")
        if getattr(self.awg, "last_err", ""):
            self._log(f"SYST:ERR {self.awg.last_err}")
        self._settings.setValue("scope_visa", self.cfg.instrument.scope_visa)
        self._settings.setValue("awg_visa", self.cfg.instrument.awg_visa)

    @Slot()
    def on_disconnect(self) -> None:
        if self.awg is not None:
            try:
                self.awg.output(False)
            except Exception:  # noqa: BLE001
                pass
            try:
                self.awg.close()
            except Exception:  # noqa: BLE001
                pass
        if self.scope is not None:
            try:
                self.scope.close()
            except Exception:  # noqa: BLE001
                pass
        self.scope = None
        self.awg = None
        self._set_led(None, "示波器", False, "—")
        self._set_led(None, "信号源", False, "—")
        self.status_edit.setText("未连接")

    @Slot()
    def on_init_awg(self) -> None:
        if self.awg is None:
            QMessageBox.information(self, "提示", "请先连接仪器")
            return
        p = self._params()
        try:
            self.awg.apply_burst(p.frequency_mhz, p.voltage_mVpp, 0.0, p.burst_count, 1.0 / p.prf_hz)
            self.awg.output(False)
            self._log(
                f"信号源已配置：{p.frequency_mhz} MHz，{p.burst_count} 周期/猝发，"
                f"{p.prf_hz} Hz PRF，{p.voltage_mVpp} mVpp（输出关闭）"
            )
        except Exception as exc:  # noqa: BLE001
            QMessageBox.critical(self, "初始化失败", str(exc))

    @Slot()
    def on_selftest(self) -> None:
        if self.awg is None:
            QMessageBox.information(self, "提示", "请先连接仪器")
            return
        try:
            self.awg.apply_burst(1.0, 20.0, 0.0, 10, 0.01)
            freq, volt = self.awg.readback()
            self._log(f"自检回读  f={freq:.6g} Hz  Vpp={volt:.6g} V（未打开输出）")
        except Exception as exc:  # noqa: BLE001
            QMessageBox.critical(self, "自检失败", str(exc))

    def start_run(self, mode: str) -> None:
        if self.worker is not None and self.worker.isRunning():
            return
        if self.scope is None or self.awg is None:
            QMessageBox.information(self, "提示", "请先连接仪器")
            return
        p = self._params()
        xmax = (p.pcd_duration_s if mode == "pcd" else p.duration_s + p.mb_load_time_s + p.baseline_duration_s) * max(p.prf_hz, 1.0) + 8
        self.plots.reset(xmax, p.max_voltage_mV)
        self.runner = ExperimentRunner(
            self.cfg,
            p,
            self.scope,
            self.awg,
            on_pulse=lambda u: None,
            on_status=lambda s: None,
        )
        self.worker = Worker(self.runner, mode)
        self.worker.runner.on_pulse = self.worker.pulse.emit
        self.worker.runner.on_status = self.worker.status.emit
        self.worker.pulse.connect(self.on_pulse)
        self.worker.status.connect(self._log)
        self.worker.done.connect(self.on_done)
        self.worker.failed.connect(self.on_failed)
        self._busy(True)
        self.worker.start()

    @Slot(object)
    def on_pulse(self, upd: PulseUpdate) -> None:
        self.lbl_pulse.setText(
            f"{upd.phase}  pulse #{upd.pulse}   {upd.volt_mV:.1f} mV   剩余 {upd.remaining_s:.1f}s"
        )
        self.plots.update_pulse(upd, self.sp_maxv.value())

    @Slot()
    def on_stop(self) -> None:
        if self.runner is not None:
            self.runner.request_stop()
        running = self.worker is not None and self.worker.isRunning()
        if not running and self.awg is not None:
            try:
                self.awg.output(False)
            except Exception:  # noqa: BLE001
                pass
        self._log("停止：已请求关闭输出")

    @Slot(str)
    def on_done(self, path: str) -> None:
        self._busy(False)
        self._log(f"已保存 {path}")

    @Slot(str)
    def on_failed(self, msg: str) -> None:
        self._busy(False)
        QMessageBox.critical(self, "运行失败", msg)
        self._log("失败：" + msg)

    def closeEvent(self, event: QCloseEvent) -> None:
        self.on_stop()
        if self.worker is not None and self.worker.isRunning():
            self.worker.wait(4000)
        self.on_disconnect()
        try:
            self._sync_cfg()
            save_config(self.cfg)
            self._settings.setValue("scope_visa", self.cfg.instrument.scope_visa)
            self._settings.setValue("awg_visa", self.cfg.instrument.awg_visa)
        except Exception:  # noqa: BLE001
            pass
        event.accept()


def _lock_height(w: QWidget, height: int = 26) -> None:
    w.setMinimumHeight(height)
    w.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed)


def _spin(lo: int, hi: int, step: int = 1) -> QSpinBox:
    w = QSpinBox()
    w.setRange(lo, hi)
    w.setSingleStep(step)
    _lock_height(w)
    return w


def _section(title: str, body: QLayout) -> QVBoxLayout:
    col = QVBoxLayout()
    col.setContentsMargins(0, 0, 0, 0)
    col.setSpacing(6)
    head = QLabel(title)
    head.setObjectName("section")
    col.addWidget(head)
    col.addLayout(body)
    return col


def _form() -> QFormLayout:
    f = QFormLayout()
    f.setContentsMargins(0, 0, 0, 0)
    f.setHorizontalSpacing(10)
    f.setVerticalSpacing(6)
    f.setFieldGrowthPolicy(QFormLayout.FieldGrowthPolicy.ExpandingFieldsGrow)
    f.setLabelAlignment(Qt.AlignmentFlag.AlignRight | Qt.AlignmentFlag.AlignVCenter)
    f.setFormAlignment(Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignTop)
    f.setRowWrapPolicy(QFormLayout.RowWrapPolicy.DontWrapRows)
    return f


def _dark_palette() -> QPalette:
    pal = QPalette()
    pal.setColor(QPalette.ColorRole.Window, QColor("#1b1e23"))
    pal.setColor(QPalette.ColorRole.WindowText, QColor("#d7dbe0"))
    pal.setColor(QPalette.ColorRole.Base, QColor("#121417"))
    pal.setColor(QPalette.ColorRole.AlternateBase, QColor("#242830"))
    pal.setColor(QPalette.ColorRole.Text, QColor("#e8edf2"))
    pal.setColor(QPalette.ColorRole.Button, QColor("#2e3440"))
    pal.setColor(QPalette.ColorRole.ButtonText, QColor("#e8edf2"))
    pal.setColor(QPalette.ColorRole.Highlight, QColor("#c9a227"))
    pal.setColor(QPalette.ColorRole.HighlightedText, QColor("#111111"))
    pal.setColor(QPalette.ColorRole.PlaceholderText, QColor("#8a939e"))
    pal.setColor(QPalette.ColorRole.ToolTipBase, QColor("#121417"))
    pal.setColor(QPalette.ColorRole.ToolTipText, QColor("#d7dbe0"))
    return pal


def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv if argv is None else argv)
    simulate = "--simulate" in argv
    argv = [a for a in argv if a != "--simulate"]
    QGuiApplication.setHighDpiScaleFactorRoundingPolicy(
        Qt.HighDpiScaleFactorRoundingPolicy.PassThrough
    )
    cfg = load_config()
    if simulate:
        cfg.simulate = True
    app = QApplication(argv)
    app.setApplicationName("PFC")
    app.setStyle("Fusion")
    app.setPalette(_dark_palette())
    app.setStyleSheet(QSS)
    win = MainWindow(cfg)
    win.show()
    return app.exec()
