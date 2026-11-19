"""ISO 4628-3 Ri from percent rusted, using the same cut-offs as the grading engine (D10, D12).

The cut-offs live in lib/grading/ri-cutoffs.json; the Docker image copies that file in and points
ANODE_RI_CUTOFFS at it.
"""

from __future__ import annotations

import json
import os
from functools import lru_cache
from pathlib import Path

_DEFAULT = Path(__file__).resolve().parents[2] / "lib" / "grading" / "ri-cutoffs.json"


@lru_cache(maxsize=1)
def cutoffs() -> list[tuple[int, float]]:
    path = Path(os.environ.get("ANODE_RI_CUTOFFS", _DEFAULT))
    bands = json.loads(path.read_text())["bands"]
    return [(int(b["ri"]), float(b["upTo"])) for b in bands]


def ri_from_percent(percent: float) -> int:
    """Lowest Ri whose published rusted area is at or above the measurement (rounding up)."""
    if not 0 <= percent <= 100:
        raise ValueError(f"percent rusted must be 0 to 100, got {percent}")
    for ri, up_to in cutoffs():
        if percent <= up_to:
            return ri
    raise AssertionError("the last band covers 100%")  # pragma: no cover
