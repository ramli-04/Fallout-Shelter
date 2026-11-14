"""FastAPI bridge to independent async actors and Kafka event transport."""
import asyncio
from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import HTMLResponse
from .inspector import PAGE
from .provider import load_env
from .engine import BusyError
from .runtime import AsyncRuntime
from .social_events import SocialEventStore
from contextlib import asynccontextmanager
load_env()
engine = AsyncRuntime()
social_store = SocialEventStore(engine.ledger.db)
social_publish_lock = asyncio.Lock()
@asynccontextmanager
async def lifespan(app):
    await engine.start()
    yield
    await engine.close()
app = FastAPI(title="ESSAIM concurrent agents", lifespan=lifespan)

@app.post('/social/population')
async def social_population(config: dict):
    from .social_population import generate
    try:
        return await asyncio.to_thread(generate, config)
    except ValueError as error:
        raise HTTPException(422,str(error)) from error

@app.post('/social/providers')
async def social_providers(groups: dict):
    import os
    from .async_providers import OllamaProvider, GeminiProvider, GrokProvider, OpenAIProvider
    classes=dict(ollama=OllamaProvider,gemini=GeminiProvider,grok=GrokProvider,openai=OpenAIProvider)
    if set(groups)!=set(engine.config): raise HTTPException(422,'Expected A/B/C provider groups')
    if any(engine.active.values()): raise HTTPException(409,'Active inference must finish before provider changes')
    configs={}
    for group, value in groups.items():
        if not isinstance(value,dict) or value.get('provider') not in classes or not isinstance(value.get('model'),str) or not 1<=len(value['model'])<=120:
            raise HTTPException(422,'Invalid provider/model')
        provider=value['provider']
        limit=value.get('concurrency',2 if provider=='ollama' else 4)
        if type(limit) not in (int,float) or int(limit)!=limit or not 1<=limit<=16: raise HTTPException(422,'Invalid provider concurrency')
        if provider!='ollama' and (os.getenv('ESSAIM_CLOUD_ENABLED','false').lower()!='true' or os.getenv('ESSAIM_LOCAL_ONLY','true').lower()=='true'):
            raise HTTPException(422,'Cloud providers require backend opt-in')
        configs[group]=dict(engine.config[group],provider=provider,model=value['model'],concurrency=int(limit))
        if provider=='ollama': configs[group]['url']=os.getenv('OLLAMA_URL','http://127.0.0.1:11434')
        else:
            key_env={'gemini':'GEMINI_API_KEY','grok':'XAI_API_KEY','openai':'OPENAI_API_KEY'}[provider]
            if not os.getenv(key_env): raise HTTPException(422,'Provider credentials unavailable')
            configs[group].update(key_env=key_env,url={'gemini':'https://generativelanguage.googleapis.com/v1beta','grok':'https://api.x.ai/v1','openai':'https://api.openai.com/v1'}[provider])
    previous=dict(engine.providers)
    monitor=getattr(engine,'monitor_task',None)
    if monitor:
        monitor.cancel(); await asyncio.gather(monitor,return_exceptions=True)
    engine.config.update(configs)
    engine.providers={g:classes[c['provider']](c) for g,c in configs.items()}
    await engine.cognitive.reset_models()
    # Close all previous adapters, including cached experiment providers.
    adapters={id(p):p for p in [*previous.values(),*engine.provider_cache.values()]}
    await asyncio.gather(*(p.client.aclose() for p in adapters.values()))
    engine.provider_cache={}
    import json
    engine.provider_cache[json.dumps(configs['C'],sort_keys=True)]=engine.providers['C']
    await asyncio.gather(*(p.health_check() for p in engine.providers.values()))
    engine.model_info={}
    if monitor: engine.monitor_task=asyncio.create_task(engine.monitor())
    return {'groups':engine.health()['groups']}

@app.post('/social/events')
async def social_events(packet: dict):
    batch=packet.get('events',[])
    if not isinstance(batch,list) or not 1<=len(batch)<=32:
        raise HTTPException(422,'Expected 1–32 events')
    async with social_publish_lock:
        try:
            accepted=sum(social_store.accept(event) for event in batch)
        except (ValueError,TypeError) as error:
            raise HTTPException(422,str(error)) from error
        if engine.bus.producer is not None:
            for event in social_store.pending():
                event_type = event['event_type']
                topic = ('shelter.events' if event_type.startswith('shelter.') or event_type == 'agent.shelter_intent' else
                         'agent.communications' if event_type.startswith(('phone.', 'social.')) or event_type == 'agent.communication' else
                         'agent.observations' if event_type == 'agent.observation' else
                         'agent.decisions' if event_type == 'agent.decision' else 'world.events')
                delivered=await engine.bus.publish(topic,event,event['run_id'],event['source_entity'],event['event_id'],event_type=event_type)
                if delivered: social_store.mark_published(event['event_id'])
                else: break
    return {'accepted':accepted,'durable':True,'kafka':engine.bus.status}

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

@app.post("/shelter/decision")
async def decide_shelter(packet: dict):
    try:
        return await engine.decide_shelter(packet)
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
    await engine.cognitive.reset_models()
    await engine.providers['C'].health_check()
    return {'preset': preset, 'groups': engine.health()['groups']}

@app.post('/events')
async def events(packet: dict):
    topic = packet.get('topic')
    if topic not in ('agent.communications', 'world.events', 'shelter.events'):
        raise HTTPException(422, 'Unsupported bridge topic')
    await engine.bus.publish(topic, packet.get('payload', {}), packet.get('run_id', ''), packet.get('agent_id', ''), packet.get('correlation_id', ''))
    return {'status': engine.bus.status}
