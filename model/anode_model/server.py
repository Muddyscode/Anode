"""The measurement API (Stage 3 outbound contract 1): POST /measure, GET /health.

Called only by Anode's server. Security:
  - every request carries the shared secret in the X-Anode-Key header;
  - images are fetched only over HTTPS from allow-listed hosts (Anode's Supabase storage),
    without following redirects, with a size cap and a timeout.
"""

from __future__ import annotations

import hmac
import io
import os
from dataclasses import dataclass, field
from typing import Annotated
from urllib.parse import urlparse

import httpx
import numpy as np
from fastapi import Depends, FastAPI, Header, HTTPException
from PIL import Image, UnidentifiedImageError
from pydantic import BaseModel, ConfigDict, Field, HttpUrl

from .postprocess import measure
from .predictor import Predictor

MAX_IMAGE_BYTES = 20 * 1024 * 1024  # the inspection-photos bucket limit
MAX_PIXELS = 20000 * 20000


class MeasureRequest(BaseModel):
    """Mirrors MeasureRequest in contracts/findings.ts (tests check it against model/schemas)."""

    model_config = ConfigDict(extra="forbid", strict=True)
    imageUrl: HttpUrl
    widthPx: Annotated[int, Field(gt=0)]
    heightPx: Annotated[int, Field(gt=0)]
    mmPerPx: Annotated[float, Field(gt=0)]


@dataclass
class Settings:
    api_key: str
    allowed_hosts: frozenset[str]
    timeout_s: float = 20.0
    max_bytes: int = MAX_IMAGE_BYTES

    @classmethod
    def from_env(cls) -> Settings:
        key = os.environ.get("ANODE_API_KEY", "")
        hosts = frozenset(h.strip().lower() for h in os.environ.get("ANODE_ALLOWED_IMAGE_HOSTS", "").split(",") if h.strip())
        if not key or not hosts:
            raise RuntimeError("ANODE_API_KEY and ANODE_ALLOWED_IMAGE_HOSTS must be set")
        return cls(api_key=key, allowed_hosts=hosts)


@dataclass
class Fetcher:
    """Downloads an image with the security rules above. A transport can be injected for tests."""

    settings: Settings
    transport: httpx.BaseTransport | None = field(default=None)

    def fetch(self, url: str) -> bytes:
        parsed = urlparse(url)
        if parsed.scheme != "https" or (parsed.hostname or "").lower() not in self.settings.allowed_hosts:
            raise HTTPException(status_code=422, detail="imageUrl must be an https URL on an allowed host")
        try:
            with httpx.Client(transport=self.transport, timeout=self.settings.timeout_s, follow_redirects=False) as client:
                with client.stream("GET", url) as res:
                    if res.status_code != 200:
                        raise HTTPException(status_code=502, detail=f"image download failed with status {res.status_code}")
                    chunks, size = [], 0
                    for chunk in res.iter_bytes():
                        size += len(chunk)
                        if size > self.settings.max_bytes:
                            raise HTTPException(status_code=413, detail="image is larger than 20 MB")
                        chunks.append(chunk)
                    return b"".join(chunks)
        except httpx.HTTPError as err:
            raise HTTPException(status_code=502, detail="image download failed") from err


def decode(data: bytes, width: int, height: int) -> np.ndarray:
    Image.MAX_IMAGE_PIXELS = MAX_PIXELS
    try:
        img = Image.open(io.BytesIO(data))
        img.load()
    except (UnidentifiedImageError, OSError, Image.DecompressionBombError) as err:
        raise HTTPException(status_code=422, detail="imageUrl is not a readable image") from err
    if img.size != (width, height):
        raise HTTPException(status_code=422, detail=f"image is {img.size[0]}x{img.size[1]}, request says {width}x{height}")
    return np.asarray(img.convert("RGB"))


def create_app(predictor: Predictor, settings: Settings, transport: httpx.BaseTransport | None = None) -> FastAPI:
    app = FastAPI(title="Anode measurement model", docs_url=None, redoc_url=None, openapi_url=None)
    fetcher = Fetcher(settings, transport)

    def authorised(x_anode_key: Annotated[str, Header()] = "") -> None:
        if not hmac.compare_digest(x_anode_key.encode(), settings.api_key.encode()):
            raise HTTPException(status_code=401, detail="missing or wrong X-Anode-Key")

    @app.get("/health")
    def health() -> dict:
        return {"ok": True, "modelName": predictor.model_name, "modelVersion": predictor.model_version}

    @app.post("/measure", dependencies=[Depends(authorised)])
    def measure_photo(req: MeasureRequest) -> dict:
        rgb = decode(fetcher.fetch(str(req.imageUrl)), req.widthPx, req.heightPx)
        prob = predictor.predict(rgb)
        if prob.shape != rgb.shape[:2]:
            raise HTTPException(status_code=500, detail="predictor returned the wrong shape")
        # Phase 1 reports areas, not sizes, so mmPerPx is accepted but not used yet.
        return measure(prob, predictor.model_name, predictor.model_version)

    return app
