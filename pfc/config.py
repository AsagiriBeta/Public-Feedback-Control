"""仪器与实验默认参数。

VISA 地址可填完整资源字符串，或填 AUTO 由 *IDN? 自动识别：
  - 示波器：RIGOL DHO8xx / DHO9xx（本实验室为 DHO814）
  - 信号源：RIGOL DG2xxx（本实验室为 DG2052）
"""

from __future__ import annotations

import json
import sys
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any


def user_config_dir() -> Path:
    return Path.home() / ".pfc"


def user_config_path() -> Path:
    return user_config_dir() / "config.json"


def bundled_config_path() -> Path | None:
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent / "pfc_config.json"
    return None


@dataclass
class InstrumentConfig:
    scope_visa: str = "AUTO"
    awg_visa: str = "AUTO"
    scope_channel: int = 1
    awg_channel: int = 1
    acquire_timeout_s: float = 8.0
    visa_timeout_ms: int = 15000
    visa_backend: str = "auto"  # auto | ivi | py
    harmonic_bandwidth_hz: float = 200e3
    use_legacy_fft_bins: bool = False
    legacy_sc_lo: int = 56373
    legacy_sc_hi: int = 56876
    legacy_ic_lo: int = 9187
    legacy_ic_hi: int = 9690
    vertical_scale_v: float = 0.05
    trigger_level_v: float = 0.01
    awg_load: str = "50"  # 50 或 INFinity；驱动 50 Ω 功放时用 50
    awg_trig_out: str = "POSitive"  # 后面板 Sync 边沿：POSitive|NEGative|OFF
    scope_trig_source: str = "pcd"  # pcd | sync（sync：用另一通道接 DG2052 后面板）
    scope_trig_channel: int = 2
    target_fs_hz: float = 40e6


@dataclass
class ExperimentDefaults:
    frequency_mhz: float = 1.5
    voltage_mVpp: float = 20.0
    prf_hz: float = 1.0
    burst_count: int = 100
    duration_s: float = 30.0
    sample_points: int = 40000
    mb_load_time_s: float = 5.0
    controller_target_db: float = 6.0
    max_voltage_mV: float = 50.0
    pcd_duration_s: float = 20.0
    baseline_duration_s: float = 5.0
    baseline_voltage_mV: float = 18.0
    voltage_step_mV: float = 1.0
    maintain_tol_db: float = 0.4
    study_id: str = "study"
    save_dir: str = ""


@dataclass
class AppConfig:
    instrument: InstrumentConfig = field(default_factory=InstrumentConfig)
    experiment: ExperimentDefaults = field(default_factory=ExperimentDefaults)
    simulate: bool = False

    def to_dict(self) -> dict[str, Any]:
        return {
            "instrument": asdict(self.instrument),
            "experiment": asdict(self.experiment),
            "simulate": self.simulate,
        }

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> AppConfig:
        inst = InstrumentConfig(**{k: v for k, v in data.get("instrument", {}).items() if k in InstrumentConfig.__dataclass_fields__})
        exp = ExperimentDefaults(**{k: v for k, v in data.get("experiment", {}).items() if k in ExperimentDefaults.__dataclass_fields__})
        return cls(instrument=inst, experiment=exp, simulate=bool(data.get("simulate", False)))


def load_config(path: Path | None = None) -> AppConfig:
    candidates: list[Path] = []
    if path is not None:
        candidates.append(path)
    bundled = bundled_config_path()
    if bundled is not None:
        candidates.append(bundled)
    candidates.append(user_config_path())
    for p in candidates:
        if p.is_file():
            with p.open(encoding="utf-8") as f:
                return AppConfig.from_dict(json.load(f))
    return AppConfig()


def save_config(cfg: AppConfig, path: Path | None = None) -> Path:
    dest = path or user_config_path()
    dest.parent.mkdir(parents=True, exist_ok=True)
    with dest.open("w", encoding="utf-8") as f:
        json.dump(cfg.to_dict(), f, indent=2, ensure_ascii=False)
    return dest
