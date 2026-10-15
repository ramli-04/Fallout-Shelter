"""Transport test only: scripted TEST_ONLY output is never a production provider."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import threading
import time
from http.server import ThreadingHTTPServer
from ai_service.engine import Engine
from ai_service.server import handler_for


class TransportTestProvider:
    model = 'TEST_ONLY_NO_LLM'
    def __init__(self, delay=0.35):
        self.delay = delay
    def health(self):
        return 'CONNECTED'
    def generate(self, system, prompt):
        time.sleep(self.delay)
        return {'message': {'content': json.dumps({'action': 'MOVE_TO_SHELTER',
            'target': 'S1', 'message': '', 'reason': 'TEST_ONLY transport intention', 'confidence': 0.8})}}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', required=True)
    parser.add_argument('--script', default='res://tests/test_phase3_http.gd')
    parser.add_argument('--inference-delay', type=float, default=0.35)
    parser.add_argument('--population', choices=('30', '120'), default='30')
    parser.add_argument('--parallel-pool', action='store_true')
    args = parser.parse_args()
    pool = None
    trace_directory = None
    if args.parallel_pool:
        import tempfile
        trace_directory = tempfile.TemporaryDirectory()
        os.environ['LLM_TRACE_PATH'] = str(Path(trace_directory.name) / 'traces.jsonl')
        from ai_service.pool import ModelPool, MODELS
        pool = ModelPool({model: TransportTestProvider(args.inference_delay) for model in MODELS}, concurrency=3)
    server = ThreadingHTTPServer(('127.0.0.1', 0), handler_for(pool or Engine(TransportTestProvider(args.inference_delay))))
    server.daemon_threads = True
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    env = dict(os.environ, ESSAIM_TEST_URL=f'http://127.0.0.1:{server.server_port}', ESSAIM_TEST_POPULATION=args.population)
    try:
        result = subprocess.run([args.godot, '--headless', '--path', str(Path(__file__).resolve().parents[1]),
            '--script', args.script], env=env, timeout=90)
        return result.returncode
    finally:
        if pool:
            pool.close()
            for worker in pool.workers: worker.join(3)
        server.shutdown()
        server.server_close()
        thread.join()
        if trace_directory: trace_directory.cleanup()


if __name__ == '__main__':
    raise SystemExit(main())
