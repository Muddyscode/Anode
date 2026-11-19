# Anode measurement model

Step 1 of the grading pipeline ("Measure"): a U-Net segmentation model that outlines rust on a
photo of coated steel, served behind the Stage 3 measurement contract (`POST /measure`).

| Path | What |
|---|---|
| `anode_model/postprocess.py` | Probabilities → percent area, GeoJSON outline, confidence |
| `anode_model/predictor.py` | `UNetPredictor` (segmentation_models_pytorch, MIT; ResNet-18 encoder) |
| `anode_model/server.py` | FastAPI app: `POST /measure`, `GET /health` |
| `anode_model/evaluate.py` | Evaluation harness (public test set now, gold set in Stage 6b) |
| `anode_model/data.py` | Licence check, COCO → masks, deterministic splits, attribution |
| `anode_model/ri.py` | Ri from percent, reading `lib/grading/ri-cutoffs.json` (same cut-offs as the grading engine) |
| `notebooks/train_unet.ipynb` | Colab training notebook |
| `schemas/` | JSON Schemas generated from `contracts/findings.ts` (`npm run schemas`) |
| `Dockerfile` | Hugging Face Space image (CPU) |

## Contract and security

Request and response follow `schemas/measure-request.json` and `schemas/measure-response.json`;
the tests validate every response against them.

- Every request needs the shared secret in `X-Anode-Key`.
- Images are fetched only over HTTPS from hosts in `ANODE_ALLOWED_IMAGE_HOSTS` (Anode's Supabase
  storage), without following redirects, up to 20 MB, and must match the stated width and height.
- **Percent area** counts every rust pixel over the whole photo. **Outline** is the same mask
  simplified to 1.5 px for display. **Confidence** is the mean pixel certainty, max(p, 1 − p),
  over the region the model has an opinion about; the grading engine maps it to high, medium or
  low (D12). It will be recalibrated on the gold set.

## Train (Google Colab)

1. Open `notebooks/train_unet.ipynb` in Colab with a GPU runtime.
2. Add a Colab secret `ROBOFLOW_API_KEY` (free Roboflow account); optionally `HF_TOKEN`.
3. In step 1, add each dataset after checking its licence on its page. Only CC BY 4.0 or more
   permissive is accepted; the notebook refuses anything else and writes `ATTRIBUTION.md`.
4. Run all. The test split is held out by a hash of the file name and never trained on.
5. Commit `evaluation-public.md` into `docs/evaluation.md` and `ATTRIBUTION.md` into this folder.

## Deploy (Hugging Face Space, free CPU)

1. Create a private model repo for the weights and upload `anode-unet.pt` (the notebook can do it).
2. Create a Space with the Docker SDK. Copy `anode_model/`, `app/`, `Dockerfile`,
   `requirements-server.txt` and `../lib/grading/ri-cutoffs.json` into it.
3. Set Space secrets: `ANODE_API_KEY`, `HF_TOKEN`; variables: `ANODE_WEIGHTS_REPO`,
   `ANODE_MODEL_VERSION`, `ANODE_ALLOWED_IMAGE_HOSTS` (your Supabase storage host).
4. The free Space sleeps when idle; the first request after a pause is slow.

## Develop

```sh
python3 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt
.venv/bin/python -m pytest      # no torch needed: tests use a fake predictor
.venv/bin/ruff check . && .venv/bin/ruff format --check .
```
