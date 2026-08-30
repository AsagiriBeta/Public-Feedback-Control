"""命令行：列出仪器、信号源自检。"""

from __future__ import annotations

import argparse
import sys

from pfc.config import load_config
from pfc.experiment.runner import connect_instruments
from pfc.instruments.visa_io import discover_instruments


def cmd_list(args: argparse.Namespace) -> int:
    cfg = load_config()
    backend = args.backend or cfg.instrument.visa_backend
    try:
        found = discover_instruments(backend)
    except Exception as exc:  # noqa: BLE001
        print(exc, file=sys.stderr)
        return 1
    if not found:
        print("未发现 VISA 资源。请确认已安装 NI-VISA 或 pyvisa-py，且 USB 已连接。")
        return 2
    for d in found:
        print(f"{d.kind:6s}  {d.resource}")
        if d.idn:
            print(f"        {d.idn}")
    return 0


def cmd_selftest(args: argparse.Namespace) -> int:
    cfg = load_config()
    cfg.simulate = args.simulate
    try:
        scope, awg, sidn, aidn = connect_instruments(cfg)
    except Exception as exc:  # noqa: BLE001
        print(exc, file=sys.stderr)
        return 1
    print(f"示波器  {sidn}")
    print(f"信号源  {aidn}")
    try:
        awg.output(False)
        awg.apply_burst(1.0, 20.0, 0.0, 10, 0.01)
        freq, volt = awg.readback()
        print(f"回读    f={freq:.6g} Hz  Vpp={volt:.6g} V")
        if abs(freq - 1e6) > 1e3 and not cfg.simulate:
            print("警告：频率回读与 1 MHz 偏差较大（猝发配置后载波读数可能因机型而异）")
        if args.enable_output:
            print("打开输出 2 秒（请确认负载安全）…")
            awg.output(True)
            import time

            time.sleep(2)
            awg.output(False)
            print("已关闭输出")
        else:
            print("未打开射频输出。加 --enable-output 可做短脉冲测试。")
    finally:
        try:
            awg.output(False)
        except Exception:  # noqa: BLE001
            pass
        awg.close()
        scope.close()
    return 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="pfc-cli", description="PFC 仪器工具")
    sub = p.add_subparsers(dest="cmd", required=True)
    p_list = sub.add_parser("list", help="列出 VISA 设备")
    p_list.add_argument("--backend", default=None, help="auto | ivi | py")
    p_list.set_defaults(func=cmd_list)
    p_test = sub.add_parser("selftest", help="连接并配置 DG2052 猝发（默认不开输出）")
    p_test.add_argument("--simulate", action="store_true")
    p_test.add_argument("--enable-output", action="store_true")
    p_test.set_defaults(func=cmd_selftest)
    args = p.parse_args(argv)
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())
