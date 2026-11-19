"""Predictors: anything that turns an RGB photo into a per-pixel rust probability map."""

from __future__ import annotations

import os
from pathlib import Path
from typing import Protocol

import cv2
import numpy as np

from . import MODEL_NAME


class Predictor(Protocol):
    model_name: str
    model_version: str

    def predict(self, rgb: np.ndarray) -> np.ndarray:
        """rgb: H x W x 3 uint8. Returns H x W float probabilities in 0..1."""
        ...


IMAGENET_MEAN = np.array([0.485, 0.456, 0.406], dtype=np.float32)
IMAGENET_STD = np.array([0.229, 0.224, 0.225], dtype=np.float32)


class UNetPredictor:
    """U-Net (segmentation_models_pytorch, MIT) with a ResNet-18 encoder, run on CPU."""

    model_name = MODEL_NAME

    def __init__(self, weights: Path, model_version: str, input_size: int = 512) -> None:
        import segmentation_models_pytorch as smp  # heavy imports only when serving
        import torch

        self._torch = torch
        self.model_version = model_version
        self.input_size = input_size
        self.model = smp.Unet(encoder_name="resnet18", encoder_weights=None, in_channels=3, classes=1)
        state = torch.load(weights, map_location="cpu", weights_only=True)
        self.model.load_state_dict(state)
        self.model.eval()

    def predict(self, rgb: np.ndarray) -> np.ndarray:
        h, w = rgb.shape[:2]
        resized = cv2.resize(rgb, (self.input_size, self.input_size), interpolation=cv2.INTER_AREA)
        x = (resized.astype(np.float32) / 255.0 - IMAGENET_MEAN) / IMAGENET_STD
        tensor = self._torch.from_numpy(x.transpose(2, 0, 1)).unsqueeze(0)
        with self._torch.inference_mode():
            logits = self.model(tensor)[0, 0].numpy()
        prob = 1.0 / (1.0 + np.exp(-logits))
        return cv2.resize(prob, (w, h), interpolation=cv2.INTER_LINEAR).astype(np.float32)


def load_predictor_from_env() -> Predictor:  # pragma: no cover - needs torch and real weights
    """ANODE_MODEL_WEIGHTS: local file. If missing and ANODE_WEIGHTS_REPO is set, the weights are
    downloaded from that (private) Hugging Face model repository using HF_TOKEN."""
    weights = Path(os.environ.get("ANODE_MODEL_WEIGHTS", "weights/anode-unet.pt"))
    if not weights.exists() and os.environ.get("ANODE_WEIGHTS_REPO"):
        from huggingface_hub import hf_hub_download

        weights = Path(hf_hub_download(os.environ["ANODE_WEIGHTS_REPO"], "anode-unet.pt", token=os.environ.get("HF_TOKEN")))
    version = os.environ.get("ANODE_MODEL_VERSION", "unversioned")
    return UNetPredictor(weights, version)
