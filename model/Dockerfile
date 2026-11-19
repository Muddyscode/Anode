# Anode measurement model for a Hugging Face Space (Docker SDK, CPU basic, port 7860).
# Build context: this model/ directory, with lib/grading/ri-cutoffs.json copied in next to it
# (see model/README.md, "Deploy").
FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1 \
    ANODE_RI_CUTOFFS=/app/ri-cutoffs.json

RUN useradd --create-home --uid 1000 anode
WORKDIR /app

RUN pip install --index-url https://download.pytorch.org/whl/cpu torch==2.7.1 torchvision==0.22.1
COPY requirements-server.txt .
RUN pip install -r requirements-server.txt

COPY anode_model ./anode_model
COPY app ./app
COPY ri-cutoffs.json ./ri-cutoffs.json

USER anode
EXPOSE 7860
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "7860", "--workers", "1"]
