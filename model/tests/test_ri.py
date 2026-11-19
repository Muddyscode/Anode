import json

import pytest

from anode_model.ri import _DEFAULT, cutoffs, ri_from_percent

EPS = 1e-9


@pytest.mark.parametrize(
    ("pct", "ri"),
    [
        (0, 0),
        (EPS, 1),
        (0.05, 1),
        (0.05 + EPS, 2),
        (0.5, 2),
        (0.5 + EPS, 3),
        (1, 3),
        (1 + EPS, 4),
        (8, 4),
        (8 + EPS, 5),
        (100, 5),
    ],
)
def test_same_cutoffs_as_the_grading_engine(pct, ri):
    assert ri_from_percent(pct) == ri


@pytest.mark.parametrize("pct", [-EPS, 100 + EPS])
def test_refuses_out_of_range(pct):
    with pytest.raises(ValueError):
        ri_from_percent(pct)


def test_reads_the_shared_file():
    bands = json.loads(_DEFAULT.read_text())["bands"]
    assert cutoffs() == [(b["ri"], b["upTo"]) for b in bands]
