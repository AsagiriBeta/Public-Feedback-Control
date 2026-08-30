"""RIGOL DHO800/DHO900 示波器（实验室型号 DHO814）。

SCPI 依据《DHO800/DHO900 Programming Guide》：
  采集：:RUN / :STOP / :SINGle、:ACQuire:MDEPth、:ACQuire:SRATe?
  触发：:TRIGger:MODE EDGE、:TRIGger:SWEep SINGle、:TRIGger:STATus?
  读波：:STOP → :WAVeform:MODE RAW → :WAVeform:FORMat WORD → :WAVeform:DATA?
  电压：(raw - YORigin - YREFerence) × YINCrement
"""

from __future__ import annotations

import time
from dataclasses import dataclass

import numpy as np

from pfc.config import InstrumentConfig
from pfc.instruments.visa_io import AcquisitionAborted, open_named, query, read_ieee_block, write

# DHO814 单通道最大 25 Mpts（手册 / 数据手册）；50M 仅 DHO900/DHO824
_MDEPTH = (
    (1_000, "1k"),
    (10_000, "10k"),
    (100_000, "100k"),
    (1_000_000, "1M"),
    (5_000_000, "5M"),
    (10_000_000, "10M"),
    (25_000_000, "25M"),
)


def pick_mdepth(npts: int, max_tag: str = "25M") -> str:
    allowed = []
    for n, tag in _MDEPTH:
        allowed.append((n, tag))
        if tag == max_tag:
            break
    for n, tag in allowed:
        if n >= npts:
            return tag
    return allowed[-1][1]


@dataclass
class ScopeSetupInfo:
    real_fs: float
    time_interval_ns: float
    channel: int
    mdepth: str


class DHO800:
    def __init__(self, resource: str, cfg: InstrumentConfig):
        self.resource = resource
        self.cfg = cfg
        self._inst = None
        self.idn = ""

    def open(self) -> str:
        self._inst = open_named(self.resource, self.cfg.visa_backend, self.cfg.visa_timeout_ms)
        self.idn = query(self._inst, "*IDN?")
        return self.idn

    def close(self) -> None:
        if self._inst is not None:
            try:
                write(self._inst, ":RUN")
            except Exception:  # noqa: BLE001
                pass
            try:
                self._inst.close()
            except Exception:  # noqa: BLE001
                pass
            self._inst = None

    def setup(self, target_fs: float, npts: int, ch: int | None = None) -> ScopeSetupInfo:
        inst = self._require()
        ch = int(ch or self.cfg.scope_channel)
        trig_ch = self._trigger_channel(ch)
        chan = f"CHANnel{ch}"
        for i in range(1, 5):
            on = i == ch or i == trig_ch
            write(inst, f":CHANnel{i}:DISPlay {'ON' if on else 'OFF'}")
        write(inst, f":{chan}:COUPling DC")
        write(inst, f":{chan}:SCALe {self.cfg.vertical_scale_v:.12g}")
        if trig_ch != ch:
            tchan = f"CHANnel{trig_ch}"
            write(inst, f":{tchan}:COUPling DC")
            write(inst, f":{tchan}:SCALe 1")

        md = pick_mdepth(npts)
        write(inst, f":ACQuire:MDEPth {md}")
        write(inst, ":ACQuire:TYPE NORMal")

        t_total = npts / target_fs
        scale = t_total / 10.0
        write(inst, f":TIMebase:MAIN:SCALe {scale:.12g}")
        write(inst, ":TIMebase:HREFerence:MODE LB")

        write(inst, ":TRIGger:MODE EDGE")
        write(inst, f":TRIGger:EDGE:SOURce CHANnel{trig_ch}")
        write(inst, ":TRIGger:EDGE:SLOPe POSitive")
        trig_level = 1.0 if trig_ch != ch else self.cfg.trigger_level_v
        write(inst, f":TRIGger:EDGE:LEVel {trig_level:.12g}")
        write(inst, ":TRIGger:SWEep SINGle")
        write(inst, ":RUN")

        real_fs = float(query(inst, ":ACQuire:SRATe?"))
        return ScopeSetupInfo(
            real_fs=real_fs,
            time_interval_ns=(1.0 / real_fs) * 1e9,
            channel=ch,
            mdepth=md,
        )

    def acquire_block(
        self,
        npts: int,
        ch: int | None = None,
        stop_event=None,
    ) -> tuple[np.ndarray, float, float]:
        inst = self._require()
        ch = int(ch or self.cfg.scope_channel)
        chan = f"CHANnel{ch}"

        write(inst, ":RUN")
        write(inst, ":SINGle")
        t0 = time.monotonic()
        ok = False
        while time.monotonic() - t0 < self.cfg.acquire_timeout_s:
            if stop_event is not None and stop_event.is_set():
                write(inst, ":STOP")
                raise AcquisitionAborted("已停止")
            st = query(inst, ":TRIGger:STATus?")
            if "STOP" in st.upper():
                ok = True
                break
            time.sleep(0.005)
        if not ok:
            raise TimeoutError(f"DHO814 单次触发超时（{self.cfg.acquire_timeout_s:.1f} s）")

        write(inst, ":STOP")
        write(inst, f":WAVeform:SOURce {chan}")
        write(inst, ":WAVeform:MODE RAW")
        write(inst, ":WAVeform:FORMat WORD")
        write(inst, f":WAVeform:POINts {npts}")
        write(inst, ":WAVeform:STARt 1")
        write(inst, f":WAVeform:STOP {npts}")

        yinc = float(query(inst, ":WAVeform:YINCrement?"))
        yor = float(query(inst, ":WAVeform:YORigin?"))
        yref = float(query(inst, ":WAVeform:YREFerence?"))
        xinc = float(query(inst, ":WAVeform:XINCrement?"))

        write(inst, ":WAVeform:DATA?")
        payload = read_ieee_block(inst)
        if len(payload) % 2:
            raise RuntimeError("WORD 波形字节数为奇数")
        raw = np.frombuffer(payload, dtype="<i2")
        volts = (raw.astype(np.float64) - yor - yref) * yinc
        if volts.size > npts:
            volts = volts[:npts]
        elif volts.size < npts:
            pad = np.zeros(npts, dtype=np.float64)
            pad[: volts.size] = volts
            volts = pad

        real_fs = 1.0 / xinc if xinc else 0.0
        time_interval_ns = xinc * 1e9
        write(inst, ":RUN")
        return volts, time_interval_ns, real_fs

    def _trigger_channel(self, pcd_ch: int) -> int:
        if self.cfg.scope_trig_source.lower() != "sync":
            return pcd_ch
        tch = int(self.cfg.scope_trig_channel)
        if tch == pcd_ch:
            return pcd_ch
        return tch

    def _require(self):
        if self._inst is None:
            raise RuntimeError("示波器未连接")
        return self._inst
