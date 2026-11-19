import jsonschema
import numpy as np
import pytest

from anode_model.postprocess import confidence, mask_from_probabilities, measure, outline, percent_area

from .conftest import square_mask


def test_percent_area_counts_every_rust_pixel():
    m = square_mask()  # 40 x 60 = 2400 of 20000
    assert percent_area(m) == pytest.approx(12.0)
    assert percent_area(np.zeros((10, 10), bool)) == 0.0


def test_percent_area_refuses_empty():
    with pytest.raises(ValueError):
        percent_area(np.zeros((0, 0), bool))


def test_threshold_and_shape():
    prob = np.array([[0.49, 0.5], [0.9, 0.1]])
    assert mask_from_probabilities(prob).tolist() == [[False, True], [True, False]]
    with pytest.raises(ValueError):
        mask_from_probabilities(np.zeros(3))


def test_outline_is_a_closed_multipolygon_inside_the_image():
    geo = outline(square_mask())
    assert geo["type"] == "MultiPolygon"
    assert len(geo["coordinates"]) == 1
    ring = geo["coordinates"][0][0]
    assert ring[0] == ring[-1] and len(ring) >= 4
    xs, ys = [p[0] for p in ring], [p[1] for p in ring]
    assert min(xs) >= 30 and max(xs) <= 89 and min(ys) >= 20 and max(ys) <= 59


def test_outline_keeps_holes_and_separate_patches():
    m = square_mask(box=(10, 10, 90, 90))
    m[40:60, 40:60] = False  # a hole
    m[5:15, 150:190] = True  # a second patch
    polys = outline(m)["coordinates"]
    assert len(polys) == 2
    assert sorted(len(p) for p in polys) == [1, 2]


def test_outline_of_nothing_is_empty():
    assert outline(np.zeros((20, 20), bool)) == {"type": "MultiPolygon", "coordinates": []}


def test_outline_drops_specks_too_small_for_a_ring():
    m = np.zeros((20, 20), bool)
    m[5, 5] = True
    assert outline(m)["coordinates"] == []


def test_confidence_is_high_when_sure_and_low_when_unsure():
    m = square_mask()
    sure = np.where(m, 0.98, 0.01)
    unsure = np.where(m, 0.55, 0.45)
    assert confidence(sure, sure >= 0.5) > 0.95
    assert confidence(unsure, unsure >= 0.5) < 0.6
    clean = np.full((10, 10), 0.03)
    assert confidence(clean, clean >= 0.5) == pytest.approx(0.97)


def test_measure_matches_the_contract(response_schema):
    out = measure(np.where(square_mask(), 0.9, 0.05), "m", "1")
    jsonschema.validate(out, response_schema)
    assert out["percentAreaRusted"] == pytest.approx(12.0)
