from pfc.processing.control import FeedbackController, sc_from_baseline_db


def test_sc_db():
    assert abs(sc_from_baseline_db(10.0, 10.0) - 100.0) < 1e-9
    assert abs(sc_from_baseline_db(10.0, 0.0) - 10.0) < 1e-9


def test_ramp_then_maintain():
    c = FeedbackController(volt_mV=20.0, max_mV=50.0, step_mV=1.0)
    c.arm_maintain(baseline_sc=10.0, target_db=6.0, tol_db=0.4)
    v = 20.0
    for p in range(1, 8):
        v = c.update(p, sc=1.0, first_fuson=1)
    assert c.ramping
    assert v == 27.0
    v = c.update(8, sc=c.sc_desired + 1, first_fuson=1)
    assert not c.ramping
    assert c.event_pulse == 8
    v2 = c.update(9, sc=c.tol_pos + 1, first_fuson=1)
    assert v2 == v - 1
    v3 = c.update(10, sc=c.tol_neg - 1, first_fuson=1)
    assert v3 == v2 + 1


def test_max_clamp():
    c = FeedbackController(volt_mV=49.0, max_mV=50.0, step_mV=2.0)
    c.arm_maintain(1.0, 20.0, 0.4)
    v = c.update(2, sc=0.0, first_fuson=1)
    assert v == 50.0
