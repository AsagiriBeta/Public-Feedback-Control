"""DG2000 猝发 SCPI（与 DG2000-Trigger 同一命令顺序，便于单测）。

依据《DG2000 编程手册》：
  :SOURce<n>:APPLy:SINusoid <freq>,<amp>,<offset>,<phase>
  猝发参数写完后再 :BURSt:STATe ON
  内部触发时可用 :BURSt:TRIGger:TRIGOut 从后面板输出同步边沿
"""

from __future__ import annotations

from typing import Protocol, runtime_checkable


@runtime_checkable
class ScpiWriter(Protocol):
    def write(self, command: str) -> None: ...

    def query(self, command: str) -> str: ...


def try_return_to_local(dev: ScpiWriter) -> None:
    for cmd in (":SYST:KLOC OFF", ":SYST:LOC", "SYST:KLOC OFF", "SYST:LOC"):
        try:
            dev.write(cmd)
        except Exception:  # noqa: BLE001
            continue


def clear_error_queue(dev: ScpiWriter, n: int = 6) -> str:
    last = ""
    for _ in range(n):
        try:
            last = dev.query(":SYST:ERR?").strip()
        except Exception as exc:  # noqa: BLE001
            return f"<ERR {exc}>"
        if last.startswith("0,") or last.startswith("+0,"):
            break
    return last


def apply_sine_burst(
    dev: ScpiWriter,
    *,
    ch: int,
    freq_hz: float,
    vpp: float,
    offset_v: float,
    phase_deg: float,
    n_cycle: int,
    period_s: float,
    load: str,
    trig_out: str = "POSitive",
) -> list[str]:
    """写入正弦 N 循环内部猝发。trig_out: POSitive|NEGative|OFF。"""
    if not (period_s > 0 and period_s == period_s):
        raise ValueError("period_s 须为有限正数（猝发周期 = 1/PRF）")
    src = f"SOURce{ch}"
    out = f"OUTPut{ch}"
    nc = max(1, int(round(n_cycle)))
    cmds = [
        f":OUTP{ch} OFF",
        f":{out}:LOAD {load}",
        f":{src}:APPL:SIN {freq_hz:.12g},{vpp:.12g},{offset_v:.12g},{phase_deg:.12g}",
        f":{src}:BURSt:STATe OFF",
        f":{src}:BURSt:MODE TRIGgered",
        f":{src}:BURSt:NCYCles {nc}",
        f":{src}:BURSt:TDELay 0",
        f":{src}:BURSt:TRIGger:SOURce INTernal",
        f":{src}:BURSt:INTernal:PERiod {period_s:.12g}",
    ]
    if trig_out and trig_out.upper() != "OFF":
        cmds.append(f":{src}:BURSt:TRIGger:TRIGOut {trig_out}")
    else:
        cmds.append(f":{src}:BURSt:TRIGger:TRIGOut OFF")
    cmds.append(f":{src}:BURSt:STATe ON")
    for cmd in cmds:
        dev.write(cmd)
    return cmds
