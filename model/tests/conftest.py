import io
import json
from pathlib import Path

import numpy as np
import pytest
from PIL import Image

SCHEMAS = Path(__file__).resolve().parents[1] / "schemas"


class FakePredictor:
    """Returns a fixed probability map: `level` inside `mask`, `background` elsewhere."""

    model_name = "fake-model"
    model_version = "test-1"

    def __init__(self, mask: np.ndarray, level: float = 0.95, background: float = 0.02) -> None:
        self.mask, self.level, self.background = mask, level, background

    def predict(self, rgb: np.ndarray) -> np.ndarray:
        assert rgb.shape[:2] == self.mask.shape
        return np.where(self.mask, self.level, self.background).astype(np.float32)


def square_mask(h: int = 100, w: int = 200, box: tuple[int, int, int, int] = (20, 30, 60, 90)) -> np.ndarray:
    m = np.zeros((h, w), dtype=bool)
    y0, x0, y1, x1 = box
    m[y0:y1, x0:x1] = True
    return m


def png_bytes(w: int, h: int) -> bytes:
    buf = io.BytesIO()
    Image.new("RGB", (w, h), (120, 80, 60)).save(buf, format="PNG")
    return buf.getvalue()


@pytest.fixture
def response_schema() -> dict:
    return json.loads((SCHEMAS / "measure-response.json").read_text())


@pytest.fixture
def request_schema() -> dict:
    return json.loads((SCHEMAS / "measure-request.json").read_text())
