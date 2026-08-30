"""Chien et al. 2022 闭环：先升压至目标 SC，再在容差带内维持。"""

from __future__ import annotations

from dataclasses import dataclass


def sc_from_baseline_db(baseline_sc: float, target_db: float) -> float:
    return baseline_sc * (10.0 ** (target_db / 10.0))


@dataclass
class FeedbackController:
    volt_mV: float
    max_mV: float
    step_mV: float = 1.0
    ramping: bool = True
    sc_desired: float = 0.0
    tol_pos: float = 0.0
    tol_neg: float = 0.0
    event_pulse: int | None = None

    def arm_maintain(self, baseline_sc: float, target_db: float, tol_db: float) -> None:
        self.sc_desired = sc_from_baseline_db(baseline_sc, target_db)
        self.tol_pos = sc_from_baseline_db(baseline_sc, target_db + tol_db)
        self.tol_neg = sc_from_baseline_db(baseline_sc, target_db - tol_db)

    def update(self, pulse: int, sc: float, first_fuson: int) -> float:
        if self.ramping:
            if sc >= self.sc_desired and first_fuson != pulse:
                self.event_pulse = pulse
                self.ramping = False
            else:
                self.volt_mV = min(self.volt_mV + self.step_mV, self.max_mV)
        else:
            if sc > self.tol_pos:
                self.volt_mV = max(0.0, self.volt_mV - self.step_mV)
            elif sc < self.tol_neg:
                self.volt_mV = min(self.volt_mV + self.step_mV, self.max_mV)
        return self.volt_mV
