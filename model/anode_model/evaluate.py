"""Evaluation harness (Stage 6). Same code for the public held-out test set (6a) and the gold set (6b).

    python -m anode_model.evaluate --images DIR --masks DIR --weights FILE --version V --out report.md

Masks are PNGs with the same file stem as their image; any non-zero pixel is rust.
"""

from __future__ import annotations

import argparse
import statistics
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image

from .postprocess import mask_from_probabilities, percent_area
from .predictor import Predictor
from .ri import ri_from_percent

IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png", ".webp"}


@dataclass(frozen=True)
class SampleResult:
    name: str
    iou: float
    dice: float
    true_percent: float
    predicted_percent: float
    true_ri: int
    predicted_ri: int


def iou_and_dice(truth: np.ndarray, pred: np.ndarray) -> tuple[float, float]:
    """Both 1.0 when truth and prediction are both empty."""
    inter = np.count_nonzero(truth & pred)
    union = np.count_nonzero(truth | pred)
    total = np.count_nonzero(truth) + np.count_nonzero(pred)
    if union == 0:
        return 1.0, 1.0
    return inter / union, 2 * inter / total


def score(name: str, truth: np.ndarray, prob: np.ndarray) -> SampleResult:
    pred = mask_from_probabilities(prob)
    iou, dice = iou_and_dice(truth, pred)
    tp, pp = percent_area(truth), percent_area(pred)
    return SampleResult(name, iou, dice, tp, pp, ri_from_percent(tp), ri_from_percent(pp))


@dataclass(frozen=True)
class Summary:
    count: int
    mean_iou: float
    mean_dice: float
    mean_abs_percent_error: float
    median_abs_percent_error: float
    ri_exact: float
    ri_within_one: float
    under_graded: float


def summarise(results: list[SampleResult]) -> Summary:
    if not results:
        raise ValueError("no samples to evaluate")
    errors = [abs(r.predicted_percent - r.true_percent) for r in results]
    n = len(results)
    return Summary(
        count=n,
        mean_iou=statistics.fmean(r.iou for r in results),
        mean_dice=statistics.fmean(r.dice for r in results),
        mean_abs_percent_error=statistics.fmean(errors),
        median_abs_percent_error=statistics.median(errors),
        ri_exact=sum(r.predicted_ri == r.true_ri for r in results) / n,
        ri_within_one=sum(abs(r.predicted_ri - r.true_ri) <= 1 for r in results) / n,
        under_graded=sum(r.predicted_ri < r.true_ri for r in results) / n,
    )


def report_markdown(summary: Summary, title: str, model_version: str) -> str:
    rows = [
        ("Samples", f"{summary.count}"),
        ("Mean IoU", f"{summary.mean_iou:.3f}"),
        ("Mean Dice", f"{summary.mean_dice:.3f}"),
        ("Area error, mean (percentage points)", f"{summary.mean_abs_percent_error:.3f}"),
        ("Area error, median (percentage points)", f"{summary.median_abs_percent_error:.3f}"),
        ("Ri exact", f"{summary.ri_exact:.1%}"),
        ("Ri within one step", f"{summary.ri_within_one:.1%}"),
        ("Ri under-graded", f"{summary.under_graded:.1%}"),
    ]
    lines = [f"### {title}", "", f"Model version `{model_version}`.", "", "| Metric | Value |", "|---|---|"]
    lines += [f"| {k} | {v} |" for k, v in rows]
    return "\n".join(lines) + "\n"


def load_pairs(images: Path, masks: Path) -> list[tuple[str, np.ndarray, np.ndarray]]:
    pairs = []
    for img_path in sorted(p for p in images.iterdir() if p.suffix.lower() in IMAGE_SUFFIXES):
        mask_path = masks / f"{img_path.stem}.png"
        if not mask_path.exists():
            raise FileNotFoundError(f"no mask for {img_path.name}")
        rgb = np.asarray(Image.open(img_path).convert("RGB"))
        truth = np.asarray(Image.open(mask_path).convert("L")) > 0
        if truth.shape != rgb.shape[:2]:
            raise ValueError(f"mask size does not match {img_path.name}")
        pairs.append((img_path.name, rgb, truth))
    return pairs


def evaluate(pairs: list[tuple[str, np.ndarray, np.ndarray]], predictor: Predictor) -> Summary:
    return summarise([score(name, truth, predictor.predict(rgb)) for name, rgb, truth in pairs])


def main(argv: list[str] | None = None) -> None:  # pragma: no cover - thin CLI over tested functions
    from .predictor import UNetPredictor

    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--images", type=Path, required=True)
    ap.add_argument("--masks", type=Path, required=True)
    ap.add_argument("--weights", type=Path, required=True)
    ap.add_argument("--version", required=True)
    ap.add_argument("--title", default="Public held-out test set")
    ap.add_argument("--out", type=Path, required=True)
    args = ap.parse_args(argv)
    summary = evaluate(load_pairs(args.images, args.masks), UNetPredictor(args.weights, args.version))
    args.out.write_text(report_markdown(summary, args.title, args.version))
    print(args.out.read_text())


if __name__ == "__main__":  # pragma: no cover
    main()
