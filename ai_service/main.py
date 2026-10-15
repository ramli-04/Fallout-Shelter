"""Async FastAPI adapter; bounded ModelPool workers own blocking inference."""
import asyncio
from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import HTMLResponse
from .inspector import PAGE
from .provider import load_env
from .engine import BusyError
from .pool import ModelPool
load_env()
engine = ModelPool()
app = FastAPI(title="ESSAIM local agent")

@app.get('/inspector', response_class=HTMLResponse)
def inspector():
    return PAGE

@app.get('/traces')
def traces(model: str = '', agent: str = '', run: str = '', limit: int = Query(100, ge=1, le=300)):
    items = engine.traces.list(model=model, agent=agent, run=run, limit=limit)
    return {'items': [{k: v for k, v in record.items() if k not in
        ('system_prompt', 'prompt', 'request_payload', 'raw_response', 'raw_answer', 'decision', 'error')}
        for record in items], 'capacity': engine.traces.capacity}

@app.get('/traces/{identity}')
def trace_detail(identity: str):
    for record in engine.traces.list(limit=engine.traces.capacity):
        if record['trace_id'] == identity: return record
    raise HTTPException(404, 'Trace is outside the recent-history window')

@app.get("/health")
def health():
    result = engine.health()
    return dict(result, service="CONNECTED", ollama_connected=result["status"] in ["CONNECTED", "DEGRADED", "MODEL_UNAVAILABLE"], model_available=result["status"] in ["CONNECTED", "DEGRADED"])

@app.post("/decide")
@app.post("/v1/decision", include_in_schema=False)
async def decide(packet: dict):
    try:
        return await asyncio.wrap_future(engine.submit(packet))
    except BusyError as error:
        raise HTTPException(429, str(error)) from error
    except (ValueError, KeyError, TypeError) as error:
        raise HTTPException(422, str(error)) from error
    except Exception as error:
        raise HTTPException(503, type(error).__name__) from error
