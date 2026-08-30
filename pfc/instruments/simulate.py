"""无仪器时的仿真，便于开发 GUI 与打包自检。"""

from __future__ import annotations

import time

import numpy as np

from pfc.config import InstrumentConfig
from pfc.instruments.dho800 import ScopeSetupInfo


class SimulatedScope:
    def __init__(self, resource: str = "SIM::SCOPE", cfg: InstrumentConfig | None = None):
        self.resource = resource
        self.cfg = cfg or InstrumentConfig()
        self.idn = "RIGOL TECHNOLOGIES,DHO814,SIM0001,00.00"
        self._fs = 40e6
        self._f0 = 1.5e6
        self._drive_mV = 20.0
        self._pulse = 0
        self._output_on = False

    def open(self) -> str:
        return self.idn

    def close(self) -> None:
        return None

    def setup(self, target_fs: float, npts: int, ch: int | None = None) -> ScopeSetupInfo:
        self._fs = float(target_fs)
        ch = int(ch or self.cfg.scope_channel)
        return ScopeSetupInfo(real_fs=self._fs, time_interval_ns=1e9 / self._fs, channel=ch, mdepth="sim")

    def set_drive(self, mV: float, output_on: bool) -> None:
        self._drive_mV = mV
        self._output_on = output_on

    def acquire_block(
        self,
        npts: int,
        ch: int | None = None,
        stop_event=None,
    ) -> tuple[np.ndarray, float, float]:  # noqa: ARG002
        n = int(npts)
        t0 = time.monotonic()
        while time.monotonic() - t0 < 0.02:
            if stop_event is not None and stop_event.is_set():
                from pfc.instruments.visa_io import AcquisitionAborted

                raise AcquisitionAborted("已停止")
            time.sleep(0.002)
        t = np.arange(n, dtype=np.float64) / self._fs
        amp = (self._drive_mV / 1000.0) * (0.4 if self._output_on else 0.02)
        rng = np.random.default_rng()
        noise = rng.normal(0, 0.002, n)
        sc = 0.15 * amp * np.sin(2 * np.pi * 3 * self._f0 * t)
        ic = 0.08 * amp * np.sin(2 * np.pi * 0.5 * self._f0 * t)
        fund = amp * np.sin(2 * np.pi * self._f0 * t)
        env = np.ones(n)
        env[int(0.7 * n) :] = 0.0
        volts = env * (fund + sc + ic) + noise
        self._pulse += 1
        return volts, 1e9 / self._fs, self._fs


class SimulatedAWG:
    def __init__(self, resource: str = "SIM::AWG", cfg: InstrumentConfig | None = None):
        self.resource = resource
        self.cfg = cfg or InstrumentConfig()
        self.idn = "RIGOL TECHNOLOGIES,DG2052,SIM0002,00.00"
        self.last_err = "0,No error"
        self._vpp = 0.02
        self._freq = 1.5e6
        self._on = False
        self._scope: SimulatedScope | None = None

    def bind_scope(self, scope: SimulatedScope) -> None:
        self._scope = scope

    def open(self) -> str:
        return self.idn

    def close(self) -> None:
        self.output(False)

    def apply_burst(
        self,
        freq_mhz: float,
        ampl_mVpp: float,
        phase_deg: float,  # noqa: ARG002
        n_cycle: int,  # noqa: ARG002
        period_s: float,
        ch: int | None = None,  # noqa: ARG002
    ) -> None:
        if not period_s > 0:
            raise ValueError("period_s 须为正")
        self._freq = freq_mhz * 1e6
        self.set_vpp_mV(ampl_mVpp)
        if self._scope is not None:
            self._scope._f0 = self._freq

    def set_vpp_mV(self, ampl_mVpp: float, ch: int | None = None) -> None:  # noqa: ARG002
        self._vpp = ampl_mVpp / 1000.0
        if self._scope is not None:
            self._scope.set_drive(ampl_mVpp, self._on)

    def output(self, on: bool, ch: int | None = None) -> None:  # noqa: ARG002
        self._on = bool(on)
        if self._scope is not None:
            self._scope.set_drive(self._vpp * 1000.0, self._on)

    def readback(self, ch: int | None = None) -> tuple[float, float]:  # noqa: ARG002
        return self._freq, self._vpp
