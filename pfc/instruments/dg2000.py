"""RIGOL DG2000 任意波形发生器（实验室型号 DG2052）。

SCPI 与 DG2000-Trigger 项目对齐：APPLy:SIN、猝发写完再开、后面板 TRIGOut、断开时回本地。
超声实验保持内部 PRF（:BURSt:INTernal:PERiod = 1/PRF）。
"""

from __future__ import annotations

from pfc.config import InstrumentConfig
from pfc.instruments.dg2000_scpi import apply_sine_burst, clear_error_queue, try_return_to_local
from pfc.instruments.visa_io import open_named, query, write


class DG2000:
    def __init__(self, resource: str, cfg: InstrumentConfig):
        self.resource = resource
        self.cfg = cfg
        self._inst = None
        self.idn = ""
        self.last_err = ""

    def open(self) -> str:
        self._inst = open_named(self.resource, self.cfg.visa_backend, self.cfg.visa_timeout_ms)
        self.idn = query(self._inst, "*IDN?")
        return self.idn

    def close(self) -> None:
        if self._inst is not None:
            try:
                self.output(False)
            except Exception:  # noqa: BLE001
                pass
            try:
                try_return_to_local(self._inst)
            except Exception:  # noqa: BLE001
                pass
            try:
                self._inst.close()
            except Exception:  # noqa: BLE001
                pass
            self._inst = None

    def apply_burst(
        self,
        freq_mhz: float,
        ampl_mVpp: float,
        phase_deg: float,
        n_cycle: int,
        period_s: float,
        ch: int | None = None,
    ) -> None:
        inst = self._require()
        ch = int(ch or self.cfg.awg_channel)
        clear_error_queue(inst)
        apply_sine_burst(
            inst,
            ch=ch,
            freq_hz=freq_mhz * 1e6,
            vpp=ampl_mVpp / 1000.0,
            offset_v=0.0,
            phase_deg=phase_deg,
            n_cycle=n_cycle,
            period_s=period_s,
            load=self.cfg.awg_load,
            trig_out=self.cfg.awg_trig_out,
        )
        self.last_err = clear_error_queue(inst)

    def set_vpp_mV(self, ampl_mVpp: float, ch: int | None = None) -> None:
        inst = self._require()
        ch = int(ch or self.cfg.awg_channel)
        vpp = ampl_mVpp / 1000.0
        write(inst, f":SOURce{ch}:VOLTage:UNIT VPP")
        write(inst, f":SOURce{ch}:VOLTage {vpp:.12g}")

    def output(self, on: bool, ch: int | None = None) -> None:
        inst = self._require()
        ch = int(ch or self.cfg.awg_channel)
        write(inst, f":OUTPut{ch}:STATe {'ON' if on else 'OFF'}")

    def readback(self, ch: int | None = None) -> tuple[float, float]:
        inst = self._require()
        ch = int(ch or self.cfg.awg_channel)
        freq = float(query(inst, f":SOURce{ch}:FREQuency?"))
        volt = float(query(inst, f":SOURce{ch}:VOLTage?"))
        return freq, volt

    def _require(self):
        if self._inst is None:
            raise RuntimeError("信号源未连接")
        return self._inst
