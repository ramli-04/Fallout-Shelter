"""Real Godot-clock benchmark, never scripted model output.

Runs 30 first; runs 120 only after 30 applies at least one real decision.
Does not change the interactive preset or enable_120 setting.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import threading
from http.server import ThreadingHTTPServer
import sys
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from ai_service.pool import ModelPool
from ai_service.provider import load_env
from ai_service.server import handler_for


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', required=True)
    parser.add_argument('--speed', type=int, choices=(1, 2, 5, 10), default=1)
    parser.add_argument('--duration', type=int, choices=range(300, 601), default=300)
    parser.add_argument('--seed', type=int, default=42)
    parser.add_argument('--render', action='store_true', help='Run the actual city renderer and Director dashboard')
    parser.add_argument('--presets', nargs='+', choices=('30', '120', 'rules_30', 'rules_120'), default=['30', '120'])
    args = parser.parse_args()
    if '120' in args.presets and ('30' not in args.presets or args.presets.index('120') < args.presets.index('30')):
        parser.error('Measure 30 before 120 in the same run')
    os.chdir(ROOT)
    load_env()
    pool = ModelPool()
    health = pool.health()
    provider = pool.engines[pool.fallback_model].provider
    try:
        installation = {'ollama_version': provider.call('/api/version', timeout=3),
            'installed_models': provider.call('/api/tags', timeout=3)}
    except (OSError, ValueError):
        installation = {'ollama_version': 'unavailable', 'installed_models': []}
    provenance = dict(installation, **{
        'ai_config': json.loads((ROOT/'resources/ai_config.json').read_text()),
        'context': provider.context, 'inference_timeout': provider.timeout,
        'temperature': os.getenv('OLLAMA_TEMPERATURE', '0.3'),
        'max_tokens': os.getenv('OLLAMA_MAX_TOKENS', '128'),
        'concurrency': pool.concurrency})
    if any(not p.startswith('rules_') for p in args.presets) and health['status'] != 'CONNECTED':
        pool.close()
        raise SystemExit('Missing models or disconnected Ollama: ' + str(health['model_status']))
    if pool.mode != 'multi' and any(not p.startswith('rules_') for p in args.presets):
        pool.close()
        raise SystemExit('Heterogeneous benchmark requires LLM_POOL_MODE=multi')
    server = ThreadingHTTPServer(('127.0.0.1', 0), handler_for(pool))
    server.daemon_threads = True
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    directory = ROOT / 'outputs' / 'benchmarks'
    directory.mkdir(parents=True, exist_ok=True)
    passed_30 = False
    try:
        for preset in args.presets:
            if preset == '120' and not passed_30:
                raise SystemExit('30-agent run applied no timely LLM decision; 120 remains gated')
            suffix = '-render' if args.render else ''
            path = directory / f'{preset}-seed{args.seed}-{args.speed}x{suffix}.json'
            before = pool.health()
            measured_at = datetime.now(timezone.utc).isoformat()
            env = dict(os.environ, ESSAIM_TEST_URL=f'http://127.0.0.1:{server.server_port}',
                ESSAIM_BENCH_PRESET=preset, ESSAIM_BENCH_SEED=str(args.seed),
                ESSAIM_BENCH_DURATION=str(args.duration), ESSAIM_BENCH_SPEED=str(args.speed),
                ESSAIM_BENCH_RENDER=str(args.render).lower(),
                ESSAIM_BENCH_OUTPUT=str(path))
            samples = []
            done = threading.Event()
            def sample_gpu():
                while not done.is_set():
                    try:
                        row = subprocess.check_output(['nvidia-smi',
                            '--query-gpu=memory.total,memory.used', '--format=csv,noheader,nounits'],
                            text=True, timeout=5).splitlines()[0]
                        total, used = (int(v.strip()) for v in row.split(','))
                        samples.append({'total_mib': total, 'used_mib': used})
                    except (OSError, ValueError, subprocess.SubprocessError, IndexError):
                        pass
                    done.wait(1)
            sampler = threading.Thread(target=sample_gpu, daemon=True)
            sampler.start()
            try:
                subprocess.run([args.godot] + ([] if args.render else ['--headless']) +
                    ['--path', str(ROOT), '--script', 'res://tests/benchmark_llm_scaling.gd'],
                    env=env, check=True, timeout=args.duration/args.speed+90)
            finally:
                done.set()
                sampler.join(6)
            result = json.loads(path.read_text())
            result['final_backend_snapshot'] = pool.health()
            result['backend_metrics_delta'] = {name: {field:
                result['final_backend_snapshot']['per_model'][name][field] - before['per_model'][name][field]
                for field in ('requests', 'assigned_requests', 'completed', 'fallbacks',
                              'invalid_responses', 'input_tokens', 'output_tokens',
                              'latency_seconds', 'generation_seconds')} for name in pool.engines}
            result['transport'] = 'local Python HTTP adapter; same ModelPool/Engine as FastAPI'
            result['provenance'] = provenance
            result['measured_at_utc'] = measured_at
            result['gpu_samples'] = samples
            result['peak_total_gpu_used_mib'] = max((s['used_mib'] for s in samples), default=None)
            try:
                result['gpu_observation'] = subprocess.check_output(['nvidia-smi',
                    '--query-gpu=name,memory.total,memory.used', '--format=csv'], text=True, timeout=5).strip()
            except (OSError, subprocess.SubprocessError):
                result['gpu_observation'] = 'unavailable'
            path.write_text(json.dumps(result, indent=2), encoding='utf-8')
            passed_30 = passed_30 or (preset == '30' and result['timely_agents'] > 0)
            print(path, flush=True)
    finally:
        pool.close()
        server.shutdown()
        server.server_close()


if __name__ == '__main__':
    main()
