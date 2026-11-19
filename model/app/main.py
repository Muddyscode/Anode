"""Entry point for the Hugging Face Space: uvicorn app.main:app --port 7860"""

from anode_model.predictor import load_predictor_from_env
from anode_model.server import Settings, create_app

app = create_app(load_predictor_from_env(), Settings.from_env())
