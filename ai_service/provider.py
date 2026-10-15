"""One shared provider; no per-agent model instances or automatic downloads."""
import json
import os
import time
from typing import Protocol
from urllib.request import Request, urlopen
from .contracts import DECISION_SCHEMA


def load_env(path='.env'):
    from pathlib import Path
    if Path(path).exists():
        for line in Path(path).read_text(encoding='utf-8-sig').splitlines():
            if line.strip() and not line.lstrip().startswith('#') and '=' in line:
                key, value = line.split('=', 1)
                os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


class Provider(Protocol):
    model: str
    def health(self) -> str: ...
    def generate(self, system: str, prompt: str) -> dict: ...


class OllamaProvider:
    def __init__(self, model=None):
        self.url = os.getenv('OLLAMA_URL', 'http://127.0.0.1:11434').rstrip('/')
        self.model = model or os.getenv('OLLAMA_MODEL', 'llama3.2:1b')
        self.timeout = float(os.getenv('INFERENCE_TIMEOUT', '30'))
        self.context = int(os.getenv('OLLAMA_NUM_CTX', '2048'))

    def call(self, path, payload=None, timeout=None):
        request = Request(self.url + path,
            data=json.dumps(payload).encode() if payload is not None else None,
            headers={'Content-Type': 'application/json'})
        with urlopen(request, timeout=timeout or self.timeout) as response:
            return json.load(response)

    def health(self):
        try:
            names = [m['name'] for m in self.call('/api/tags', timeout=2)['models']]
            wanted = self.model if ':' in self.model else self.model + ':latest'
            return 'CONNECTED' if wanted in names else 'MODEL_UNAVAILABLE'
        except (OSError, ValueError, KeyError):
            return 'DISCONNECTED'

    def payload(self, system, prompt):
        return {'model': self.model, 'stream': False,
            'format': DECISION_SCHEMA, 'keep_alive': os.getenv('OLLAMA_KEEP_ALIVE', '2m'),
            'messages': [{'role': 'system', 'content': system},
                         {'role': 'user', 'content': prompt}],
            'options': {'temperature': float(os.getenv('OLLAMA_TEMPERATURE', '0.3')), 'num_ctx': self.context, 'num_predict': int(os.getenv('OLLAMA_MAX_TOKENS', '128'))}}

    def generate(self, system, prompt):
        remaining = max(0.1, getattr(self, 'deadline', time.monotonic() + self.timeout) - time.monotonic())
        return self.call('/api/chat', self.payload(system, prompt), timeout=remaining)
