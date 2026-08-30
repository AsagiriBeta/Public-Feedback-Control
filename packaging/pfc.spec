# -*- mode: python ; coding: utf-8 -*-
# 参考 DG2000-Trigger：onedir、排除 QtWebEngine 等大模块；本程序仍需 numpy/scipy/matplotlib。
import sys
from pathlib import Path

SPECDIR = Path(SPECPATH)
ROOT = SPECDIR.parent
is_win = sys.platform.startswith("win")

hidden = [
    "pyvisa_py",
    "pyvisa_py.highlevel",
    "pyvisa_py.usb",
    "pyvisa_py.protocols",
    "usb.backend.libusb1",
    "matplotlib.backends.backend_qtagg",
    "scipy.io",
    "pfc",
    "pfc.gui.app",
    "pfc.cli",
]

excludes = [
    "tkinter",
    "IPython",
    "jupyter",
    "pandas",
    "torch",
    "PyQt5",
    "PyQt6",
    "PySide6.QtWebEngineCore",
    "PySide6.QtWebEngineWidgets",
    "PySide6.QtWebEngineQuick",
    "PySide6.Qt3DCore",
    "PySide6.Qt3DRender",
    "PySide6.Qt3DExtras",
]

gui = Analysis(
    [str(ROOT / "pfc" / "__main__.py")],
    pathex=[str(ROOT)],
    binaries=[],
    datas=[],
    hiddenimports=hidden,
    excludes=excludes,
    noarchive=False,
)

cli = Analysis(
    [str(ROOT / "pfc" / "cli.py")],
    pathex=[str(ROOT)],
    binaries=[],
    datas=[],
    hiddenimports=hidden,
    excludes=excludes,
    noarchive=False,
)

gui_exe = EXE(
    PYZ(gui.pure, gui.zipped_data),
    gui.scripts,
    [],
    exclude_binaries=True,
    name="PFC",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=is_win,
    console=False,
)

cli_exe = EXE(
    PYZ(cli.pure, cli.zipped_data),
    cli.scripts,
    [],
    exclude_binaries=True,
    name="PFC-CLI",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=is_win,
    console=True,
)

coll = COLLECT(
    gui_exe,
    gui.binaries,
    gui.zipfiles,
    gui.datas,
    cli_exe,
    cli.binaries,
    cli.zipfiles,
    cli.datas,
    name="PFC",
    strip=False,
    upx=is_win,
)

if sys.platform == "darwin":
    app = BUNDLE(
        coll,
        name="PFC.app",
        icon=None,
        bundle_identifier="lab.pfc.feedback",
        info_plist={
            "NSHighResolutionCapable": True,
            "CFBundleName": "PFC",
            "CFBundleDisplayName": "PFC 闭环控制",
            "CFBundleShortVersionString": "1.1.0",
        },
    )
