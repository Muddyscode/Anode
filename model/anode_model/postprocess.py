"""From a probability map to the measure contract: percent area, outline polygons, confidence."""

from __future__ import annotations

import cv2
import numpy as np

THRESHOLD = 0.5
"""Pixel probability at or above which a pixel counts as rust."""

OPINION = 0.2
"""Pixels above this probability are where the model has an opinion; used for confidence."""

SIMPLIFY_PX = 1.5
"""Polygon simplification tolerance in image pixels (outline only; area uses every pixel)."""


def mask_from_probabilities(prob: np.ndarray, threshold: float = THRESHOLD) -> np.ndarray:
    if prob.ndim != 2:
        raise ValueError("probabilities must be a 2-D array")
    return prob >= threshold


def percent_area(mask: np.ndarray) -> float:
    """Percent of the photo's pixels that are rust, 0 to 100."""
    if mask.size == 0:
        raise ValueError("empty mask")
    return float(100.0 * np.count_nonzero(mask) / mask.size)


def confidence(prob: np.ndarray, mask: np.ndarray) -> float:
    """Mean pixel certainty, max(p, 1 - p), over the region the model has an opinion about.

    The region is the predicted rust plus every pixel above OPINION. With no such pixels (a clean
    surface) it is the whole photo. The value lies between 0.5 and 1; it is mapped to high, medium
    or low by the grading engine (D12) and will be recalibrated on the gold set.
    """
    region = mask | (prob > OPINION)
    sample = prob[region] if region.any() else prob.ravel()
    certainty = np.maximum(sample, 1.0 - sample)
    return float(np.clip(certainty.mean(), 0.0, 1.0))


def outline(mask: np.ndarray) -> dict:
    """GeoJSON MultiPolygon in image-pixel coordinates (contract A12): outer rings with their holes."""
    m = mask.astype(np.uint8)
    contours, hierarchy = cv2.findContours(m, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_SIMPLE)
    polygons: list[list[list[list[float]]]] = []
    if hierarchy is None:
        return {"type": "MultiPolygon", "coordinates": polygons}
    hierarchy = hierarchy[0]

    def ring(contour: np.ndarray) -> list[list[float]] | None:
        approx = cv2.approxPolyDP(contour, SIMPLIFY_PX, True).reshape(-1, 2)
        if len(approx) < 3:
            return None
        points = [[float(x), float(y)] for x, y in approx]
        return points + [points[0]]  # closed ring, at least 4 positions

    for i, contour in enumerate(contours):
        if hierarchy[i][3] != -1:
            continue  # a hole; added with its parent below
        outer = ring(contour)
        if outer is None:
            continue
        rings = [outer]
        child = hierarchy[i][2]
        while child != -1:
            hole = ring(contours[child])
            if hole is not None:
                rings.append(hole)
            child = hierarchy[child][0]
        polygons.append(rings)
    return {"type": "MultiPolygon", "coordinates": polygons}


def measure(prob: np.ndarray, model_name: str, model_version: str) -> dict:
    """The full measure response for one probability map."""
    mask = mask_from_probabilities(prob)
    return {
        "modelName": model_name,
        "modelVersion": model_version,
        "percentAreaRusted": round(percent_area(mask), 4),
        "outline": outline(mask),
        "modelConfidence": round(confidence(prob, mask), 4),
    }
