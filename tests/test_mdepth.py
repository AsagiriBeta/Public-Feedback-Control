from pfc.instruments.dho800 import pick_mdepth


def test_pick_mdepth_dho814():
    assert pick_mdepth(100) == "1k"
    assert pick_mdepth(1000) == "1k"
    assert pick_mdepth(1001) == "10k"
    assert pick_mdepth(40000) == "100k"
    assert pick_mdepth(1_000_000) == "1M"
    assert pick_mdepth(20_000_000) == "25M"
    assert pick_mdepth(30_000_000) == "25M"
