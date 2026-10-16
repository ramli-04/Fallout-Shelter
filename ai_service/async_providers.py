"""Asynchronous adapters. Credentials never leave this module in event payloads."""
import os
import copy
import json
import time
import httpx
from .contracts import DECISION_SCHEMA


class LLMProvider:
    def __init__(self, config, client=None):
        self.config = config
        self.kind = config['provider']
        self.model = os.path.expandvars(config.get('model', ''))
        self.client = client or httpx.AsyncClient(timeout=config.get('timeout', 25))
        self.status = 'UNCHECKED'
        self.cooldown = 0.0
        self.failures = 0
        self.metrics = dict(requests=0, completed=0, errors=0, rate_limits=0,
                            input_tokens=0, output_tokens=0, latency_seconds=0.0,
                            invalid_responses=0, fallbacks=0, active_requests=0, peak_active_requests=0)
        self.reserved_tokens = 0

    @property
    def available(self):
        if self.kind == 'ollama':
            return True
        return (os.getenv('ESSAIM_CLOUD_ENABLED', 'false').lower() == 'true'
                and os.getenv('ESSAIM_LOCAL_ONLY', 'true').lower() != 'true'
                and bool(os.getenv(self.config.get('key_env', ''), ''))
                and bool(self.model) and '$' not in self.model)

    def headers(self):
        if self.kind == 'ollama':
            return {}
        key = os.getenv(self.config.get('key_env', ''), '')
        return {'x-goog-api-key': key} if self.kind == 'gemini' else {'Authorization': 'Bearer ' + key}

    @property
    def url(self):
        return os.path.expandvars(self.config['url']).rstrip('/')

    async def health_check(self):
        if not self.available:
            self.status = 'UNAVAILABLE'
            return self.status
        try:
            path = '/api/tags' if self.kind == 'ollama' else '/models'
            response = await self.client.get(self.url + path, headers=self.headers())
            response.raise_for_status()
            data = response.json()
            names = ([m['name'] for m in data['models']] if self.kind == 'ollama' else
                     [m['name'].removeprefix('models/') for m in data.get('models', [])
                      if 'generateContent' in m.get('supportedGenerationMethods', [])]
                     if self.kind == 'gemini' else [m['id'] for m in data['data']])
            self.status = 'CONNECTED' if self.model in names else 'MODEL_UNAVAILABLE'
        except (httpx.HTTPError, ValueError, KeyError, RuntimeError):
            self.status = 'DISCONNECTED'
        return self.status

    async def get_model_info(self):
        result = dict(provider=self.kind, model=self.model, status=self.status)
        if self.kind == 'ollama':
            try:
                response = await self.client.get(self.url + '/api/ps')
                response.raise_for_status()
                result['residency'] = response.json()['models']
                version = await self.client.get(self.url + '/api/version')
                result['engine_version'] = version.json().get('version', 'unknown')
            except (httpx.HTTPError, ValueError, KeyError, RuntimeError):
                result['residency'] = None
        return result

    def get_metrics(self):
        m = self.metrics
        return dict(m, average_latency_seconds=m['latency_seconds']/max(1, m['requests']),
                    tokens_per_second=m['output_tokens']/max(.001, m['latency_seconds']),
                    estimated_cost=(m['input_tokens']*self.config.get('input_price_per_million', 0)
                        + m['output_tokens']*self.config.get('output_price_per_million', 0))/1e6,
                    pricing_configured='input_price_per_million' in self.config)

    async def generate_decision(self, system, prompt):
        if not self.available or time.monotonic() < self.cooldown:
            raise RuntimeError('Provider disabled or cooling down')
        if self.status == 'UNCHECKED':
            await self.health_check()
        if self.status != 'CONNECTED':
            raise RuntimeError('Model unavailable')
        maximum = int(self.config.get('max_tokens', 128))
        # Conservative reservation prevents concurrent requests overspending a token budget.
        reservation = len(system.encode()) + len(prompt.encode()) + maximum
        if self.kind != 'ollama':
            if self.metrics['requests'] >= self.config.get('request_budget', 100):
                raise RuntimeError('Request budget exhausted')
            if self.reserved_tokens + reservation > self.config.get('token_budget', 100000):
                raise RuntimeError('Token budget exhausted')
            self.reserved_tokens += reservation
        self.metrics['requests'] += 1
        started = time.monotonic()
        messages = [{'role': 'system', 'content': system}, {'role': 'user', 'content': prompt}]
        if self.kind == 'ollama':
            path = '/api/chat'
            schema = copy.deepcopy(DECISION_SCHEMA)
            try:
                private = json.loads(prompt).get('observation', {})
            except (ValueError, AttributeError):
                private = {}
            schema['properties']['target']['enum'] = ['', *private.get('beliefs', {}),
                *(a['id'] for a in private.get('nearby_agents', []))]
            payload = dict(model=self.model, messages=messages, stream=False, format=schema,
                           keep_alive=self.config.get('keep_alive', '2m'),
                           options=dict(num_ctx=self.config.get('context', 2048), num_predict=maximum))
        elif self.kind == 'gemini':
            path = '/models/' + self.model + ':generateContent'
            payload = dict(systemInstruction={'parts': [{'text': system}]},
                contents=[{'role': 'user', 'parts': [{'text': prompt}]}],
                generationConfig={'maxOutputTokens': maximum, 'responseMimeType': 'application/json'})
        else:
            path = '/chat/completions'
            payload = dict(model=self.model, messages=messages, max_tokens=maximum,
                           response_format={'type': 'json_object'})
        try:
            self.metrics['active_requests'] += 1
            self.metrics['peak_active_requests'] = max(self.metrics['peak_active_requests'], self.metrics['active_requests'])
            response = await self.client.post(self.url + path, json=payload, headers=self.headers())
            if response.status_code == 429 or response.status_code >= 500:
                self.failures += 1
                self.metrics['rate_limits'] += int(response.status_code == 429)
                try:
                    delay = float(response.headers.get('retry-after', 0))
                except ValueError:
                    from email.utils import parsedate_to_datetime
                    from datetime import datetime, timezone
                    try:
                        delay = (parsedate_to_datetime(response.headers['retry-after']) - datetime.now(timezone.utc)).total_seconds()
                    except (ValueError, KeyError, TypeError):
                        delay = 0
                self.cooldown = time.monotonic() + max(delay, min(300, 2**min(self.failures, 8)))
            response.raise_for_status()
            data = response.json()
            if self.kind == 'ollama':
                text = data['message']['content']
                usage = (data.get('prompt_eval_count', 0), data.get('eval_count', 0))
            elif self.kind == 'gemini':
                text = ''.join(p.get('text', '') for p in data['candidates'][0]['content']['parts'])
                usage = (data.get('usageMetadata', {}).get('promptTokenCount', 0), data.get('usageMetadata', {}).get('candidatesTokenCount', 0))
            else:
                text = data['choices'][0]['message']['content']
                usage = (data.get('usage', {}).get('prompt_tokens', 0), data.get('usage', {}).get('completion_tokens', 0))
            self.metrics['input_tokens'] += usage[0]
            self.metrics['output_tokens'] += usage[1]
            self.metrics['completed'] += 1
            self.failures = 0
            return text, usage
        except Exception:
            self.metrics['errors'] += 1
            raise
        finally:
            self.metrics['active_requests'] -= 1
            self.metrics['latency_seconds'] += time.monotonic() - started

    async def generate_message(self, system, prompt):
        return await self.generate_decision(system, prompt)


class OllamaProvider(LLMProvider):
    pass


class GeminiProvider(LLMProvider):
    pass


class GrokProvider(LLMProvider):
    pass


class OpenAIProvider(LLMProvider):
    pass
