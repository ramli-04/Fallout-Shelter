"""Measured provider requests; never enables cloud or installs models."""
import argparse
import asyncio
import json
import time
import uuid
from pathlib import Path
from .runtime import AsyncRuntime
from .provider import load_env


def packet(index, run, group):
    return dict(schema_version=1, run_id=run, request_id='1', group=group, observation=dict(
        profile=dict(id=f'A{index:03}', role='Authority' if index < 4 else 'Civilian',
                     primary_personality=['COOPERATIVE','SKEPTICAL','CAUTIOUS'][index % 3], risk_tolerance=index*3),
        position=[100+index, 100], destination='', goal='Find safety', simulation_time=10,
        estimated_time_remaining=400, beliefs={'S1':dict(position=[200,200], confidence=.6,
            existence_probability=1, source='Public information')}, memories=[], messages=[], nearby_agents=[]))


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--preset', choices=['A','B','C','D'], default='C')
    parser.add_argument('--kafka', action='store_true')
    args = parser.parse_args()
    load_env()
    config = json.loads(Path('config/llm_groups.json').read_text())
    if args.preset == 'C':
        config['C'] = dict(config['A'], model='qwen2.5:1.5b')
    runtime = AsyncRuntime(config)
    run = 'benchmark-' + uuid.uuid4().hex
    if args.kafka:
        await runtime.start()
        if runtime.bus.status != 'CONNECTED':
            raise RuntimeError('Kafka benchmark requires a connected broker')
    await asyncio.gather(*(p.health_check() for p in runtime.providers.values()))
    heartbeat_delays = []
    done = False
    async def heartbeat():
        previous = time.monotonic()
        while not done:
            await asyncio.sleep(.01)
            now = time.monotonic()
            heartbeat_delays.append(now-previous)
            previous = now
    ticker = asyncio.create_task(heartbeat())
    started = time.monotonic()
    try:
        if args.preset == 'A':
            results = [dict(rule_baseline=True) for _ in range(30)]
        else:
            results = await asyncio.gather(*(runtime.dispatch(packet(i, run, 'B' if args.preset == 'B' else 'ABC'[i//10])) for i in range(30)), return_exceptions=True)
        elapsed = time.monotonic()-started
        done = True
        await ticker
        report = dict(run_id=run, seed=42, population=30, preset=args.preset, elapsed_seconds=elapsed,
            maximum_event_loop_delay_seconds=max(heartbeat_delays, default=0),
            successful=sum(isinstance(r, dict) and 'decision' in r for r in results),
            fallback=sum(isinstance(r, dict) and r.get('fallback', False) for r in results),
            errors=sum(isinstance(r, Exception) for r in results),
            health=runtime.health(), model_info=await asyncio.gather(*(p.get_model_info() for p in runtime.providers.values())),
            provider_versions={g: await version(p) for g,p in runtime.providers.items()},
            results=[dict(error=type(r).__name__) if isinstance(r, Exception) else r for r in results],
            physical_gpu_parallelism='Not established by HTTP overlap; peak_active measures client requests only')
        target = Path('outputs/phase4') / (run + '.json')
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(report, indent=2))
        print(json.dumps(dict(path=str(target), elapsed_seconds=elapsed, successful=report['successful'],
            fallback=report['fallback'], errors=report['errors'], peak_active=runtime.peak,
            maximum_event_loop_delay_seconds=report['maximum_event_loop_delay_seconds'])))
    finally:
        await runtime.close()


async def version(provider):
    if provider.kind != 'ollama':
        return 'REST API; model identifier recorded; revision not exposed'
    try:
        return (await provider.client.get(provider.url+'/api/version')).json()
    except Exception:
        return 'unavailable'


if __name__ == '__main__':
    asyncio.run(main())
