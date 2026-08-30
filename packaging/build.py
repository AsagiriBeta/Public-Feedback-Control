#!/usr/bin/env python3
"""在当前操作系统上打包 PFC 与 PFC-CLI。必须在目标平台本机（或 CI）上运行。"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SPEC = Path(__file__).resolve().parent / "pfc.spec"


def main() -> int:
    cmd = [
        sys.executable,
        "-m",
        "PyInstaller",
        str(SPEC),
        "--noconfirm",
        "--clean",
        "--distpath",
        str(ROOT / "dist"),
        "--workpath",
        str(ROOT / "build" / "pyinstaller"),
    ]
    print(" ".join(cmd))
    subprocess.check_call(cmd, cwd=ROOT)
    print(f"\n完成。输出目录: {ROOT / 'dist'}")
    print("  macOS: dist/PFC.app  （可直接打开；首次需在系统设置中允许）")
    print("  Windows / Linux: dist/PFC/PFC  与  dist/PFC/PFC-CLI")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
