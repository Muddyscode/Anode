"""Training-data helpers used by the Colab notebook: licence checks, masks, splits, attribution.

Kept here (not in the notebook) so they are tested in CI.
"""

from __future__ import annotations

import hashlib
from dataclasses import dataclass

import cv2
import numpy as np

# Decision (Stage 6): only datasets under these licences, with attribution recorded in the repo.
ALLOWED_LICENCES = {"cc by 4.0", "cc0 1.0", "public domain", "mit"}


@dataclass(frozen=True)
class Dataset:
    """One training source. `licence` is copied by a person from the dataset's page."""

    name: str
    url: str
    licence: str
    workspace: str
    project: str
    version: int


def check_licence(ds: Dataset) -> None:
    if ds.licence.strip().lower() not in ALLOWED_LICENCES:
        raise ValueError(f"{ds.name}: licence {ds.licence!r} is not allowed; use CC BY 4.0 or more permissive")


def attribution_markdown(datasets: list[Dataset]) -> str:
    lines = ["# Training data attribution", "", "| Dataset | Licence | Source |", "|---|---|---|"]
    for ds in datasets:
        check_licence(ds)
        lines.append(f"| {ds.name} (v{ds.version}) | {ds.licence} | {ds.url} |")
    return "\n".join(lines) + "\n"


def coco_masks(coco: dict, rust_categories: set[str] | None = None) -> dict[str, np.ndarray]:
    """Binary rust masks per image file from COCO polygon annotations.

    rust_categories: category names that count as rust; None means every category.
    Images with no rust annotation get an empty mask (they teach the model what clean steel is).
    """
    names = {c["id"]: c["name"] for c in coco.get("categories", [])}
    masks: dict[int, np.ndarray] = {}
    files: dict[int, str] = {}
    for img in coco["images"]:
        masks[img["id"]] = np.zeros((img["height"], img["width"]), dtype=np.uint8)
        files[img["id"]] = img["file_name"]
    for ann in coco.get("annotations", []):
        if rust_categories is not None and names.get(ann["category_id"]) not in rust_categories:
            continue
        seg = ann.get("segmentation")
        if not isinstance(seg, list):
            raise ValueError(f"annotation {ann.get('id')} is not a polygon (RLE masks are not supported)")
        for poly in seg:
            pts = np.asarray(poly, dtype=np.float64).reshape(-1, 2)
            if len(pts) >= 3:
                cv2.fillPoly(masks[ann["image_id"]], [np.round(pts).astype(np.int32)], 1)
    return {files[i]: m.astype(bool) for i, m in masks.items()}


def split_of(file_name: str, seed: str = "anode", val: float = 0.1, test: float = 0.1) -> str:
    """Deterministic train/val/test assignment from a hash of the file name and a seed."""
    if not 0 < val < 1 or not 0 < test < 1 or val + test >= 1:
        raise ValueError("val and test must be fractions with val + test < 1")
    h = int(hashlib.sha256(f"{seed}:{file_name}".encode()).hexdigest()[:8], 16) / 0xFFFFFFFF
    if h < test:
        return "test"
    if h < test + val:
        return "val"
    return "train"
