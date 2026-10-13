"""Local FastAPI adapter; blocking inference runs in FastAPI's worker pool."""
from fastapi import FastAPI, HTTPException
from .provider import OllamaProvider, load_env
from .engine import Engine, BusyError
load_env()
engine = Engine(OllamaProvider(), max_pending=1)
app = FastAPI(title="ESSAIM local agent")

@app.get("/health")
def health():
    result = engine.health()
    return dict(result, service="CONNECTED", ollama_connected=result["status"] in ["CONNECTED", "DEGRADED", "MODEL_UNAVAILABLE"], model_available=result["status"] in ["CONNECTED", "DEGRADED"])

@app.post("/decide")
@app.post("/v1/decision", include_in_schema=False)
def decide(packet: dict):
    try:
        return engine.decide(packet)
    except BusyError as error:
        raise HTTPException(429, str(error)) from error
    except (ValueError, KeyError, TypeError) as error:
        raise HTTPException(422, str(error)) from error
    except Exception as error:
        raise HTTPException(503, type(error).__name__) from error
