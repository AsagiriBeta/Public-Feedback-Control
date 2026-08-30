from pfc.instruments.dg2000_scpi import apply_sine_burst


class FakeDev:
    def __init__(self) -> None:
        self.cmds: list[str] = []

    def write(self, command: str) -> None:
        self.cmds.append(command)

    def query(self, command: str) -> str:
        self.cmds.append(command)
        return "0,No error"


def test_burst_order_matches_manual_and_dg2000_trigger():
    dev = FakeDev()
    cmds = apply_sine_burst(
        dev,
        ch=1,
        freq_hz=1.5e6,
        vpp=0.02,
        offset_v=0.0,
        phase_deg=0.0,
        n_cycle=100,
        period_s=1.0,
        load="50",
        trig_out="POSitive",
    )
    assert cmds[0] == ":OUTP1 OFF"
    assert ":SOURce1:APPL:SIN 1500000,0.02,0,0" in cmds
    assert cmds.index(":SOURce1:BURSt:STATe OFF") < cmds.index(":SOURce1:BURSt:STATe ON")
    assert ":SOURce1:BURSt:TRIGger:SOURce INTernal" in cmds
    assert ":SOURce1:BURSt:INTernal:PERiod 1" in cmds
    assert ":SOURce1:BURSt:TRIGger:TRIGOut POSitive" in cmds
    assert cmds[-1] == ":SOURce1:BURSt:STATe ON"


def test_trig_out_off():
    dev = FakeDev()
    cmds = apply_sine_burst(
        dev, ch=1, freq_hz=1e6, vpp=0.02, offset_v=0, phase_deg=0,
        n_cycle=10, period_s=0.01, load="INFinity", trig_out="OFF",
    )
    assert ":SOURce1:BURSt:TRIGger:TRIGOut OFF" in cmds
