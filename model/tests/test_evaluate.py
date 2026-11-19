import numpy as np
import pytest
from PIL import Image

from anode_model.evaluate import evaluate, iou_and_dice, load_pairs, report_markdown, score, summarise

from .conftest import FakePredictor, square_mask


def test_iou_and_dice():
    a = square_mask(box=(0, 0, 10, 10))
    b = square_mask(box=(0, 5, 10, 15))
    iou, dice = iou_and_dice(a, b)
    assert iou == pytest.approx(50 / 150)
    assert dice == pytest.approx(100 / 200)
    empty = np.zeros_like(a)
    assert iou_and_dice(empty, empty) == (1.0, 1.0)


def test_score_grades_both_sides_with_the_engine_cutoffs():
    truth = square_mask()  # 12% -> Ri 5
    r = score("x", truth, np.where(square_mask(box=(20, 30, 21, 31)), 0.9, 0.0))  # 0.005% -> Ri 1
    assert (r.true_ri, r.predicted_ri) == (5, 1)


def test_summary_and_report():
    results = [
        score("a", square_mask(), np.where(square_mask(), 0.9, 0.0)),
        score("b", square_mask(), np.zeros((100, 200))),
    ]
    s = summarise(results)
    assert s.count == 2 and s.ri_exact == 0.5 and s.under_graded == 0.5 and s.ri_within_one == 0.5
    md = report_markdown(s, "Public held-out test set", "v1")
    assert "| Ri exact | 50.0% |" in md and "Model version `v1`" in md
    with pytest.raises(ValueError):
        summarise([])


def test_load_pairs_and_evaluate(tmp_path):
    images, masks = tmp_path / "images", tmp_path / "masks"
    images.mkdir()
    masks.mkdir()
    m = square_mask()
    Image.new("RGB", (200, 100)).save(images / "p1.jpg")
    Image.fromarray((m * 255).astype(np.uint8)).save(masks / "p1.png")
    (images / "notes.txt").write_text("ignored")
    pairs = load_pairs(images, masks)
    assert [p[0] for p in pairs] == ["p1.jpg"]
    s = evaluate(pairs, FakePredictor(m))
    assert s.mean_iou == 1.0 and s.ri_exact == 1.0


def test_load_pairs_reports_problems(tmp_path):
    images, masks = tmp_path / "images", tmp_path / "masks"
    images.mkdir()
    masks.mkdir()
    Image.new("RGB", (20, 10)).save(images / "a.png")
    with pytest.raises(FileNotFoundError):
        load_pairs(images, masks)
    Image.new("L", (5, 5)).save(masks / "a.png")
    with pytest.raises(ValueError):
        load_pairs(images, masks)
