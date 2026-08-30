"""PCD 基线升压与闭环超声实验循环（对应 MATLAB PCDcontrol / Sonication）。"""

from __future__ import annotations

import threading
import time
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Callable, Literal

import numpy as np

from pfc.config import AppConfig
from pfc.instruments.dg2000 import DG2000
from pfc.instruments.dho800 import DHO800
from pfc.instruments.simulate import SimulatedAWG, SimulatedScope
from pfc.instruments.visa_io import AcquisitionAborted, discover_instruments, pick_resource
from pfc.processing.control import FeedbackController, sc_from_baseline_db
from pfc.processing.fft import harmonic_bands, pulse_spectrum

Mode = Literal["pcd", "sonication"]


@dataclass
class ExperimentParams:
    frequency_mhz: float
    voltage_mVpp: float
    prf_hz: float
    burst_count: int
    duration_s: float
    sample_points: int
    mb_load_time_s: float
    controller_target_db: float
    max_voltage_mV: float
    study_id: str
    save_dir: str
    pcd_duration_s: float = 20.0
    baseline_duration_s: float = 5.0
    baseline_voltage_mV: float = 18.0
    voltage_step_mV: float = 1.0
    maintain_tol_db: float = 0.4


@dataclass
class PulseUpdate:
    pulse: int
    phase: str
    t_us: np.ndarray
    signal: np.ndarray
    freq_mhz: np.ndarray
    fft_amp: np.ndarray
    sc: float
    ic: float
    volt_mV: float
    remaining_s: float


@dataclass
class RunResult:
    path: str
    pulses: int
    notes: str = ""


def connect_instruments(cfg: AppConfig):
    icfg = cfg.instrument
    if cfg.simulate:
        scope = SimulatedScope("SIM::SCOPE", icfg)
        awg = SimulatedAWG("SIM::AWG", icfg)
        scope.open()
        awg.open()
        awg.bind_scope(scope)
        return scope, awg, scope.idn, awg.idn

    discovered = discover_instruments(icfg.visa_backend)
    scope_res = pick_resource("scope", icfg.scope_visa, discovered)
    awg_res = pick_resource("awg", icfg.awg_visa, discovered)
    scope = DHO800(scope_res, icfg)
    awg = DG2000(awg_res, icfg)
    sidn = scope.open()
    aidn = awg.open()
    return scope, awg, sidn, aidn


def _nextpow2(n: int) -> int:
    return 1 if n <= 1 else 2 ** int(np.ceil(np.log2(n)))


def _sum_band(y: np.ndarray, idx_1based: np.ndarray) -> float:
    if idx_1based.size == 0 or y.size == 0:
        return 0.0
    i = np.clip(idx_1based.astype(int) - 1, 0, y.size - 1)
    return float(np.sum(y[i]))


class ExperimentRunner:
    def __init__(
        self,
        cfg: AppConfig,
        params: ExperimentParams,
        scope,
        awg,
        on_pulse: Callable[[PulseUpdate], None] | None = None,
        on_status: Callable[[str], None] | None = None,
    ):
        self.cfg = cfg
        self.params = params
        self.scope = scope
        self.awg = awg
        self.on_pulse = on_pulse or (lambda _: None)
        self.on_status = on_status or (lambda _: None)
        self._stop = threading.Event()
        self.datamat: list[np.ndarray] = []
        self.sc_hist: list[float] = []
        self.ic_hist: list[float] = []
        self.v_hist: list[float] = []
        self.phase_hist: list[str] = []
        self.time_left_hist: list[float] = []
        self.sc_range = np.array([1], dtype=int)
        self.ic_range = np.array([1], dtype=int)
        self.freq_axis = np.array([0.0])
        self.real_fs = params.sample_points and cfg.instrument.target_fs_hz
        self.nfft = _nextpow2(params.sample_points)
        self.first_fuson = 1
        self.feedback_event: int | None = None

    def request_stop(self) -> None:
        self._stop.set()

    def run(self, mode: Mode) -> RunResult:
        self._stop.clear()
        p = self.params
        icfg = self.cfg.instrument
        period_s = 1.0 / p.prf_hz
        info = self.scope.setup(icfg.target_fs_hz, p.sample_points, icfg.scope_channel)
        self.real_fs = info.real_fs
        self.nfft = _nextpow2(p.sample_points)
        self.freq_axis = self.real_fs * np.arange(self.nfft // 2 + 1) / self.nfft
        f0 = p.frequency_mhz * 1e6
        if icfg.use_legacy_fft_bins:
            self.sc_range = np.arange(icfg.legacy_sc_lo, icfg.legacy_sc_hi + 1)
            self.ic_range = np.arange(icfg.legacy_ic_lo, icfg.legacy_ic_hi + 1)
        else:
            self.sc_range, self.ic_range = harmonic_bands(
                f0, self.real_fs, self.nfft, icfg.harmonic_bandwidth_hz
            )

        try:
            if mode == "pcd":
                self._run_pcd(period_s)
            else:
                self._run_sonication(period_s)
        finally:
            try:
                self.awg.output(False)
            except Exception:  # noqa: BLE001
                pass

        path = self._save(mode)
        return RunResult(path=path, pulses=len(self.datamat), notes=mode)

    def _configure_awg(self, volt_mV: float, period_s: float) -> None:
        p = self.params
        self.awg.apply_burst(p.frequency_mhz, volt_mV, 0.0, p.burst_count, period_s)

    def _acquire_pulse(self, pulse: int, phase: str, volt_mV: float, remaining_s: float) -> PulseUpdate:
        npts = self.params.sample_points
        ch = self.cfg.instrument.scope_channel
        chA, dt_ns, _fs = self.scope.acquire_block(npts, ch, self._stop)
        y = pulse_spectrum(chA, self.nfft)
        sc = _sum_band(y, self.sc_range)
        ic = _sum_band(y, self.ic_range)
        t_us = np.arange(chA.size) * float(dt_ns) * 1e-3
        upd = PulseUpdate(
            pulse=pulse,
            phase=phase,
            t_us=t_us,
            signal=chA,
            freq_mhz=self.freq_axis / 1e6,
            fft_amp=y,
            sc=sc,
            ic=ic,
            volt_mV=volt_mV,
            remaining_s=remaining_s,
        )
        self.datamat.append(np.asarray(chA, dtype=np.float64))
        self.sc_hist.append(sc)
        self.ic_hist.append(ic)
        self.v_hist.append(volt_mV)
        self.phase_hist.append(phase)
        self.time_left_hist.append(remaining_s)
        self.on_pulse(upd)
        return upd

    def _run_pcd(self, period_s: float) -> None:
        p = self.params
        volt = p.voltage_mVpp
        self.on_status("PCD 基线：配置信号源")
        self._configure_awg(volt, period_s)
        self.awg.output(True)
        t0 = time.monotonic()
        pulse = 1
        duration = p.pcd_duration_s
        while not self._stop.is_set():
            remaining = duration - (time.monotonic() - t0)
            if remaining <= 0:
                break
            self.on_status(f"PCD 基线  pulse #{pulse}")
            try:
                self._acquire_pulse(pulse, "pcd", volt, remaining)
            except AcquisitionAborted:
                break
            self.awg.set_vpp_mV(volt)
            volt = volt + p.voltage_step_mV
            if volt > p.max_voltage_mV:
                volt = p.max_voltage_mV
            pulse += 1
        self.awg.output(False)

    def _run_sonication(self, period_s: float) -> None:
        p = self.params
        self.on_status("基线采集：配置信号源")
        self._configure_awg(p.baseline_voltage_mV, period_s)
        t0 = time.monotonic()
        pulse = 1
        fu_on = False
        first_fuson = 1
        baseline_span = p.baseline_duration_s + p.mb_load_time_s
        while not self._stop.is_set():
            elapsed = time.monotonic() - t0
            remaining = baseline_span - elapsed
            if remaining <= 0:
                break
            if elapsed >= p.mb_load_time_s and not fu_on:
                self.awg.output(True)
                fu_on = True
                first_fuson = pulse
                self.on_status("基线：已打开超声输出")
            self.on_status(f"基线采集  pulse #{pulse}")
            try:
                self._acquire_pulse(pulse, "baseline", p.baseline_voltage_mV, remaining)
            except AcquisitionAborted:
                break
            pulse += 1
        self.awg.output(False)
        self.first_fuson = first_fuson
        if self._stop.is_set():
            return

        fuson_sc = self.sc_hist[first_fuson - 1 :]
        if not fuson_sc:
            raise RuntimeError("基线阶段没有采集到超声开启后的脉冲")
        baseline_sc = float(np.mean(fuson_sc))
        sc_desired = sc_from_baseline_db(baseline_sc, p.controller_target_db)
        self.on_status(f"基线 SC={baseline_sc:.4g}  目标 SC={sc_desired:.4g}")

        ctrl = FeedbackController(
            volt_mV=p.voltage_mVpp,
            max_mV=p.max_voltage_mV,
            step_mV=p.voltage_step_mV,
        )
        ctrl.arm_maintain(baseline_sc, p.controller_target_db, p.maintain_tol_db)
        volt = p.voltage_mVpp
        self._configure_awg(volt, period_s)
        self.awg.output(True)
        t1 = time.monotonic()
        while not self._stop.is_set():
            remaining = p.duration_s - (time.monotonic() - t1)
            if remaining <= 0:
                break
            self.on_status(f"闭环治疗  pulse #{pulse}")
            try:
                upd = self._acquire_pulse(pulse, "treat", volt, remaining)
            except AcquisitionAborted:
                break
            volt = ctrl.update(pulse, upd.sc, first_fuson)
            self.awg.set_vpp_mV(volt)
            pulse += 1
        self.feedback_event = ctrl.event_pulse
        self.awg.output(False)

    def _save(self, mode: Mode) -> str:
        p = self.params
        folder = Path(p.save_dir).expanduser() if p.save_dir else Path.home() / "PFC_data"
        folder.mkdir(parents=True, exist_ok=True)
        stamp = datetime.now().strftime("%Y-%m-%d_%H%M%S")
        prefix = "NoMB_PCDcontrol" if mode == "pcd" else "Sonication"
        stem = f"{prefix}_{p.study_id}_{stamp}"
        datamat = np.vstack(self.datamat) if self.datamat else np.zeros((0, p.sample_points))
        payload = {
            "mode": mode,
            "datamat": datamat,
            "RampSC": np.asarray(self.sc_hist),
            "RampIC": np.asarray(self.ic_hist),
            "Vrealtime": np.asarray(self.v_hist),
            "phase": np.asarray(self.phase_hist),
            "TimeRecord": np.asarray(self.time_left_hist),
            "frequency_mhz": p.frequency_mhz,
            "prf_hz": p.prf_hz,
            "burst_count": p.burst_count,
            "real_fs": self.real_fs,
            "nfft": self.nfft,
            "SC_range": self.sc_range,
            "IC_range": self.ic_range,
            "firstFUSon": self.first_fuson,
            "FeedbackEvent": self.feedback_event if self.feedback_event is not None else -1,
            "ControllerTarget_dB": p.controller_target_db,
        }
        npz_path = folder / f"{stem}.npz"
        np.savez_compressed(npz_path, **payload)
        try:
            from scipy.io import savemat

            savemat(folder / f"{stem}.mat", payload, do_compression=True)
        except Exception:  # noqa: BLE001
            pass
        return str(npz_path)
