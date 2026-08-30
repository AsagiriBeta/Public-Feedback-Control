"""VISA 连接与 IEEE-488.2 二进制块读取。"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from typing import Any

log = logging.getLogger(__name__)

SCOPE_IDN_KEYS = ("DHO8", "DHO9")
AWG_IDN_KEYS = ("DG20", "DG2")


class AcquisitionAborted(Exception):
    """等待触发时收到停止请求。"""


@dataclass
class DiscoveredDevice:
    resource: str
    idn: str
    kind: str  # scope | awg | other


def open_resource_manager(backend: str = "auto"):
    import pyvisa

    if backend == "ivi":
        return pyvisa.ResourceManager()
    if backend == "py":
        return pyvisa.ResourceManager("@py")

    errors: list[str] = []
    for spec in (None, "@ivi", "@py"):
        try:
            rm = pyvisa.ResourceManager() if spec is None else pyvisa.ResourceManager(spec)
            rm.list_resources()
            log.info("VISA backend ok: %s", spec or "default")
            return rm
        except Exception as exc:  # noqa: BLE001
            errors.append(f"{spec or 'default'}: {exc}")
    raise RuntimeError("无法打开 VISA 资源管理器。请安装 NI-VISA，或 pip 安装 pyvisa-py + pyusb。\n" + "\n".join(errors))


def configure_instrument(inst, timeout_ms: int = 15000) -> None:
    inst.timeout = timeout_ms
    inst.write_termination = "\n"
    inst.read_termination = "\n"
    try:
        inst.chunk_size = 1024 * 1024
    except Exception:  # noqa: BLE001
        pass


def write(inst, cmd: str) -> None:
    inst.write(cmd)


def query(inst, cmd: str) -> str:
    return inst.query(cmd).strip()


def read_ieee_block(inst) -> bytes:
    """读取 SCPI 二进制块：#N<len><payload>[terminator]。

    对应 DHO800 编程手册 3.28 节 TMC 头格式。
    """
    old_term = inst.read_termination
    inst.read_termination = None
    try:
        marker = inst.read_bytes(1)
        if marker != b"#":
            raise RuntimeError(f"期望 IEEE 块头 #，收到 {marker!r}")
        ndigits_raw = inst.read_bytes(1)
        ndigits = int(ndigits_raw.decode("ascii"))
        len_raw = inst.read_bytes(ndigits)
        nbytes = int(len_raw.decode("ascii"))
        payload = b""
        while len(payload) < nbytes:
            chunk = inst.read_bytes(nbytes - len(payload))
            if not chunk:
                break
            payload += chunk
        try:
            extra = inst.read_bytes(1)
            if extra not in (b"\n", b"\r", b""):
                pass
        except Exception:  # noqa: BLE001
            pass
        if len(payload) != nbytes:
            raise RuntimeError(f"二进制块长度不足：期望 {nbytes}，实际 {len(payload)}")
        return payload
    finally:
        inst.read_termination = old_term


def classify_idn(idn: str) -> str:
    up = idn.upper()
    if any(k in up for k in SCOPE_IDN_KEYS):
        return "scope"
    if any(k in up for k in AWG_IDN_KEYS):
        return "awg"
    return "other"


def discover_instruments(backend: str = "auto", timeout_ms: int = 4000) -> list[DiscoveredDevice]:
    rm = open_resource_manager(backend)
    found: list[DiscoveredDevice] = []
    try:
        resources = list(rm.list_resources())
    except Exception as exc:  # noqa: BLE001
        log.warning("list_resources failed: %s", exc)
        resources = []
    for res in resources:
        inst = None
        try:
            inst = rm.open_resource(res)
            configure_instrument(inst, timeout_ms=timeout_ms)
            try:
                inst.write("*CLS")
            except Exception:  # noqa: BLE001
                pass
            idn = query(inst, "*IDN?")
            found.append(DiscoveredDevice(resource=res, idn=idn, kind=classify_idn(idn)))
        except Exception as exc:  # noqa: BLE001
            log.debug("skip %s: %s", res, exc)
            found.append(DiscoveredDevice(resource=res, idn="", kind="other"))
        finally:
            if inst is not None:
                try:
                    inst.close()
                except Exception:  # noqa: BLE001
                    pass
    return found


def pick_resource(kind: str, configured: str, discovered: list[DiscoveredDevice]) -> str:
    if configured and configured.upper() != "AUTO":
        return configured
    for d in discovered:
        if d.kind == kind and d.idn:
            return d.resource
    raise RuntimeError(f"未找到 {kind} 设备。请检查 USB/VISA，或在配置中填写完整资源字符串。")


def open_named(resource: str, backend: str = "auto", timeout_ms: int = 15000) -> Any:
    rm = open_resource_manager(backend)
    inst = rm.open_resource(resource)
    configure_instrument(inst, timeout_ms=timeout_ms)
    return inst
