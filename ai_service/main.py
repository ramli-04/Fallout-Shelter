"""FastAPI bridge to independent async actors and Kafka event transport."""
import asyncio
from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import HTMLResponse
from .inspector import PAGE
from .provider import load_env
from .engine import BusyError
from .runtime import AsyncRuntime
from contextlib import asynccontextmanager
load_env()
engine = AsyncRuntime()
@asynccontextmanager
async def lifespan(app):
    await engine.start()
    yield
    await engine.close()
app = FastAPI(title="ESSAIM concurrent agents", lifespan=lifespan)

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
@app.get("/metrics")
async def health():
    result = engine.health()
    groups = result.get('groups', {})
    return dict(result, service='CONNECTED',
        ollama_connected=any(g['provider'] == 'ollama' and g['status'] == 'CONNECTED' for g in groups.values()),
        model_available=any(g['status'] == 'CONNECTED' for g in groups.values()))

@app.post("/decide")
@app.post("/v1/decision", include_in_schema=False)
async def decide(packet: dict):
    try:
        return await engine.dispatch(packet)
    except BusyError as error:
        raise HTTPException(429, str(error)) from error
    except (ValueError, KeyError, TypeError) as error:
        raise HTTPException(422, str(error)) from error
    except Exception as error:
        raise HTTPException(503, type(error).__name__) from error

@app.post('/runs/{run}/invalidate')
async def invalidate(run: str):
    engine.invalid_runs.add(run)
    return {'invalidated': run}

@app.post('/experiments/{preset}')
async def experiment(preset: str):
    if preset not in ('A', 'B', 'C', 'D', '30', '120', 'rules_30', 'rules_120'):
        raise HTTPException(422, 'Unknown preset')
    if any(engine.active.values()):
        raise HTTPException(409, 'Wait for active inference before changing experiments')
    import json
    import os
    from pathlib import Path
    from .async_providers import OllamaProvider, GeminiProvider, GrokProvider, OpenAIProvider
    base = json.loads(Path(os.getenv('LLM_GROUP_CONFIG', 'config/llm_groups.json')).read_text())
    config = dict(base['A'], model='qwen2.5:1.5b') if preset == 'C' else base['C']
    classes = dict(ollama=OllamaProvider, gemini=GeminiProvider, grok=GrokProvider, openai=OpenAIProvider, compatible=OpenAIProvider)
    identity = json.dumps(config, sort_keys=True)
    if identity not in engine.provider_cache:
        engine.provider_cache[identity] = classes[config['provider']](config)
    engine.providers['C'] = engine.provider_cache[identity]
    engine.config['C'] = config
    await engine.providers['C'].health_check()
    return {'preset': preset, 'groups': engine.health()['groups']}

@app.post('/events')
async def events(packet: dict):
    topic = packet.get('topic')
    if topic not in ('agent.communications', 'world.events', 'shelter.events'):
        raise HTTPException(422, 'Unsupported bridge topic')
    await engine.bus.publish(topic, packet.get('payload', {}), packet.get('run_id', ''), packet.get('agent_id', ''), packet.get('correlation_id', ''))
    return {'status': engine.bus.status}
