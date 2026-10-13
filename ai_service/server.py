"""Legacy test transport and compatibility CLI for the FastAPI service."""
import argparse
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from .engine import Engine, BusyError
from .provider import OllamaProvider, load_env


def handler_for(engine):
    class Handler(BaseHTTPRequestHandler):
        def reply(self, code, payload):
            body = json.dumps(payload, allow_nan=False).encode()
            self.send_response(code)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            try:
                self.wfile.write(body)
            except (BrokenPipeError, ConnectionResetError):
                pass

        def do_GET(self):
            if self.path in ['/health', '/metrics']:
                self.reply(200, engine.health())
            else:
                self.reply(404, {'error': 'Unknown endpoint'})

        def do_POST(self):
            if self.path not in ['/v1/decision', '/decide']:
                self.reply(404, {'error': 'Unknown endpoint'})
                return
            self.connection.settimeout(5)
            try:
                length = int(self.headers.get('Content-Length', '0'))
                if not 0 < length <= 65536:
                    self.reply(413, {'error': 'Body must be 1–65536 bytes'})
                    return
                packet = json.loads(self.rfile.read(length))
                self.reply(200, engine.decide(packet))
            except BusyError as error:
                self.reply(429, {'status': 'DEGRADED', 'error': str(error)})
            except (ValueError, KeyError, TypeError, AttributeError) as error:
                self.reply(422, {'status': 'DEGRADED', 'error': str(error)})
            except Exception as error:
                self.reply(503, {'status': 'DEGRADED', 'error': type(error).__name__})

        def log_message(self, fmt, *args):
            pass
    return Handler


def main():
    load_env()
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    provider = OllamaProvider()
    status = provider.health()
    print(f'{status}: {provider.model} at {provider.url}', flush=True)
    if args.check:
        return 0 if status == 'CONNECTED' else 1
    import uvicorn
    uvicorn.run('ai_service.main:app', host='127.0.0.1', port=int(os.getenv('AI_PORT', '8765')))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
