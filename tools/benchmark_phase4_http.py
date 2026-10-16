"""Exercise the running HTTP -> Kafka -> actors -> Kafka -> HTTP bridge."""
import asyncio
import json
import time
import uuid
from pathlib import Path
import httpx
from ai_service.benchmark import packet


async def main():
    run = 'http-benchmark-' + uuid.uuid4().hex
    async with httpx.AsyncClient(timeout=35) as client:
        for attempt in range(60):
            try:
                before = (await client.get('http://127.0.0.1:8765/health')).json()
                if before.get('kafka') == 'CONNECTED':
                    break
            except httpx.HTTPError:
                before = {}
            await asyncio.sleep(.5)
        assert before['kafka'] == 'CONNECTED', 'Start Kafka before running this benchmark'
        started = time.monotonic()
        results = await asyncio.gather(*(client.post('http://127.0.0.1:8765/decide',
            json=packet(i, run, 'ABC'[i//10])) for i in range(30)))
        elapsed = time.monotonic()-started
        duplicate = await client.post('http://127.0.0.1:8765/decide', json=packet(0, run, 'A'))
        report = dict(run_id=run, population=30, elapsed_seconds=elapsed,
            status_codes=[r.status_code for r in results],
            successful=sum('decision' in r.json() for r in results),
            fallbacks=sum(r.json().get('fallback', False) for r in results),
            duplicate_identical=duplicate.json() == results[0].json(),
            health=(await client.get('http://127.0.0.1:8765/health')).json())
        target = Path('outputs/phase4')/(run+'.json')
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(report, indent=2))
        print(json.dumps({k:v for k,v in report.items() if k != 'health'}))


if __name__ == '__main__':
    asyncio.run(main())
