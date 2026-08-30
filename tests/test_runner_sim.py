from pathlib import Path

from pfc.config import AppConfig
from pfc.experiment.runner import ExperimentParams, ExperimentRunner
from pfc.instruments.simulate import SimulatedAWG, SimulatedScope


def test_pcd_simulate_runs(tmp_path):
    cfg = AppConfig()
    cfg.simulate = True
    scope = SimulatedScope(cfg=cfg.instrument)
    awg = SimulatedAWG(cfg=cfg.instrument)
    scope.open()
    awg.open()
    awg.bind_scope(scope)
    p = ExperimentParams(
        frequency_mhz=1.5,
        voltage_mVpp=20.0,
        prf_hz=100.0,
        burst_count=10,
        duration_s=1.0,
        sample_points=1024,
        mb_load_time_s=0.05,
        controller_target_db=6.0,
        max_voltage_mV=40.0,
        study_id="t",
        save_dir=str(tmp_path),
        pcd_duration_s=0.12,
        baseline_duration_s=0.08,
        baseline_voltage_mV=18.0,
    )
    r = ExperimentRunner(cfg, p, scope, awg)
    out = r.run("pcd")
    assert r.datamat
    assert out.path.endswith(".npz")


def test_sonication_simulate_runs(tmp_path):
    cfg = AppConfig()
    cfg.simulate = True
    scope = SimulatedScope(cfg=cfg.instrument)
    awg = SimulatedAWG(cfg=cfg.instrument)
    scope.open()
    awg.open()
    awg.bind_scope(scope)
    p = ExperimentParams(
        frequency_mhz=1.5,
        voltage_mVpp=22.0,
        prf_hz=100.0,
        burst_count=10,
        duration_s=0.12,
        sample_points=1024,
        mb_load_time_s=0.04,
        controller_target_db=3.0,
        max_voltage_mV=40.0,
        study_id="s",
        save_dir=str(tmp_path),
        pcd_duration_s=0.1,
        baseline_duration_s=0.08,
        baseline_voltage_mV=18.0,
    )
    r = ExperimentRunner(cfg, p, scope, awg)
    out = r.run("sonication")
    assert "baseline" in r.phase_hist
    assert "treat" in r.phase_hist
    assert Path(out.path).is_file()
