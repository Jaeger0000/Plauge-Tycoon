# Backend

This directory contains the Python backend for the game.

## What It Does

The service exposes optimization endpoints for:

- crate packing
- delivery route planning
- factory assignment
- wood transport compatibility with the existing game logic

## Run It

```bash
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

If you prefer running the module directly:

```bash
python main.py
```

## API Docs

FastAPI generates interactive documentation automatically:

- Swagger UI: `/docs`
- ReDoc: `/redoc`
- OpenAPI JSON: `/openapi.json`

Open Swagger UI in a browser after starting the server to inspect the request and response models.

The request bodies shown in Swagger UI are populated from the model examples in `models.py`.

## Endpoints

- `GET /`
- `GET /health`
- `POST /solve/machine_placement`
- `POST /solve/packing`
- `POST /packing` (alias)
- `POST /solve/tsp`
- `POST /solve/transport`
- `POST /solve/full`

## Smoke Test

Run backend smoke tests after starting the API server:

```bash
bash scripts/smoke_test.sh
```

If your backend runs on a different host/port:

```bash
BACKEND_URL=http://127.0.0.1:8000 bash scripts/smoke_test.sh
```

The script checks:

- health endpoint
- transport solver endpoint
- machine placement solver endpoint
- packing solver endpoint
- tsp solver endpoint
- full chained solver endpoint

## Notes

The current solver is implemented in Python with FastAPI and is structured so it can later be replaced or extended with a full GAMSPy model.