from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from logging_service import RequestResponseLogger
from routes import router

app = FastAPI(
    title="Joes Gamspy Solver",
    description=(
        "Optimization backend for packing, routing, and factory assignment. "
        "Swagger UI is available at /docs and ReDoc at /redoc."
    ),
    version="0.2.0",
    docs_url="/docs",
    redoc_url="/redoc",
    openapi_url="/openapi.json",
)

# Add request/response logging middleware
app.add_middleware(RequestResponseLogger)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(router)


@app.get("/", summary="API info")
def root() -> dict[str, str]:
    return {
        "name": app.title,
        "docs": "/docs",
        "redoc": "/redoc",
        "openapi": "/openapi.json",
    }


@app.get("/health", summary="Health check")
def health() -> dict[str, str]:
    return {"status": "ok"}


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8000)
