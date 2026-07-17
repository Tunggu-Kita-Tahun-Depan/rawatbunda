FROM python:3.14.0-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY requirements.txt pyproject.toml ./
COPY iburujuk_ml ./iburujuk_ml
COPY artifacts ./artifacts
COPY serve_backend.py ./serve_backend.py

RUN python -m pip install --no-cache-dir .

USER 65532:65532

EXPOSE 8081

CMD ["python", "-m", "iburujuk_ml.backend", "--host", "0.0.0.0", "--port", "8081"]
