"""Real HTTP/Ollama probe with synthetic observations, not a population benchmark."""
import json
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.error import HTTPError

MODELS = ('qwen2.5:0.5b', 'llama3.2:1b', 'qwen2.5:1.5b')
URL = 'http://127.0.0.1:8765'


def main():
    run_id = 'parallel-probe-' + uuid.uuid4().hex
    def request(index, model):
        observation = dict(profile=dict(id=f'PROBE{index}', role='Civilian', primary_personality='CAUTIOUS'),
            position=[0, 0], destination='', goal='Find safety', simulation_time=0,
            estimated_time_remaining=300, memories=[], messages=[], nearby_agents=[],
            beliefs={'S1': {'position': [100, 100], 'confidence': .8, 'source': 'Observation'}})
        packet = dict(schema_version=1, run_id=run_id, request_id='1', model=model, observation=observation)
        try:
            with urlopen(Request(URL+'/decide', data=json.dumps(packet).encode(),
                headers={'Content-Type': 'application/json'}), timeout=60) as response:
                return dict(model=model, http_status=response.status, result=json.load(response))
        except HTTPError as error:
            return dict(model=model, http_status=error.code, error=error.read().decode())
    observations = []
    with ThreadPoolExecutor(max_workers=3) as executor:
        futures = [executor.submit(request, i, model) for i, model in enumerate(MODELS)]
        while not all(f.done() for f in futures):
            with urlopen(URL+'/health', timeout=10) as response:
                health = json.load(response)
            observations.append({k: health[k] for k in ('active', 'active_by_model', 'pending', 'peak_vram_bytes')})
            time.sleep(.05)
        results = [f.result() for f in futures]
    with urlopen(URL+'/traces?run='+run_id, timeout=5) as response:
        records = json.load(response)['items']
    peak = max((s['active'] for s in observations), default=0)
    target = Path('outputs/benchmarks/parallel_probe.json')
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(dict(run_id=run_id, peak_active=peak, samples=observations,
        results=results, traces=records), indent=2), encoding='utf-8')
    print(json.dumps(dict(run_id=run_id, peak_active=peak,
        http_statuses=[r['http_status'] for r in results], trace_attempts=len(records), report=str(target))))
    if peak != 3: raise SystemExit('Did not observe all three models active together')


if __name__ == '__main__': main()
