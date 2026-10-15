"""One bounded priority scheduler, shared model clients and run/agent memory.

Clients are HTTP adapters, not model instances. Ollama owns model residency.
"""
import heapq
import os
import threading
import time
from datetime import datetime, timezone
from collections import OrderedDict, deque
from concurrent.futures import Future

from .engine import Engine, BusyError
from .provider import OllamaProvider
from .traces import TraceStore

MODELS = ('qwen2.5:0.5b', 'llama3.2:1b', 'qwen2.5:1.5b')


class ModelPool:
    def __init__(self, providers=None, concurrency=None, queue_limit=None):
        self.concurrency = int(os.getenv('LLM_CONCURRENCY', '3') if concurrency is None else concurrency)
        self.per_model_limit = int(os.getenv('LLM_PER_MODEL_CONCURRENCY', '1'))
        if not 1 <= self.per_model_limit <= 8: raise ValueError('Per-model concurrency must be 1..8')
        self.queue_limit = int(os.getenv('LLM_QUEUE_LIMIT', '128') if queue_limit is None else queue_limit)
        if not 1 <= self.concurrency <= 8 or not 1 <= self.queue_limit <= 512:
            raise ValueError('Concurrency must be 1..8; queue limit 1..512')
        self.queue_timeout = float(os.getenv('LLM_QUEUE_TIMEOUT', '20'))
        self.mode = os.getenv('LLM_POOL_MODE', 'multi')
        self.fallback_model = os.getenv('LLM_FALLBACK_MODEL', 'llama3.2:1b')
        if self.mode not in ('multi', 'single', 'rules') or self.fallback_model not in MODELS:
            raise ValueError('Invalid pool mode/fallback model')
        self.auto_fallback = os.getenv('LLM_AUTO_SINGLE', 'false').lower() == 'true'
        self.engines = {}
        self.traces = TraceStore()
        shared_memories = OrderedDict()
        shared_inference = threading.BoundedSemaphore(self.concurrency)
        shared_guard = threading.Lock()
        for name in MODELS:
            provider = providers[name] if providers else OllamaProvider(model=name)
            engine = Engine(provider, max_pending=self.concurrency, queue_timeout=self.queue_timeout)
            engine.memories = shared_memories
            engine.inference = shared_inference
            engine.guard = shared_guard
            engine.trace_store = self.traces
            self.engines[name] = engine
        self.condition = threading.Condition()
        self.queue = []
        self.pending = set()
        self.active = 0
        self.active_by_model = {name: 0 for name in MODELS}
        self.active_requests = {}
        self.sequence = 0
        self.started = time.monotonic()
        self.stopping = False
        self.per_model = {name: dict(requests=0, assigned_requests=0, completed=0, fallbacks=0,
            invalid_responses=0, input_tokens=0, output_tokens=0,
            latency_seconds=0.0, request_latency_seconds=0.0, generation_seconds=0.0) for name in MODELS}
        self.residency = {}
        self.residency_error = ''
        self.previous_resident = set()
        self.unloads = deque(maxlen=128)
        self.suspected_swaps = deque(maxlen=128)
        self.peak_size = 0
        self.peak_vram = 0
        self.budget = int(float(os.getenv('AI_MEMORY_BUDGET_GB', '10')) * 1_000_000_000)
        self.swap_warning = False
        self.workers = [threading.Thread(target=self._worker, daemon=True,
            name=f'llm-worker-{i}') for i in range(self.concurrency)]
        for worker in self.workers:
            worker.start()

    def submit(self, packet):
        name = packet.get('model', self.fallback_model)
        if name not in self.engines:
            raise ValueError('Unknown model tier')
        # Validate before consuming queue slots or performing inference.
        from .contracts import observation
        obs = observation(packet['observation'])
        for field in ('run_id', 'request_id'):
            if not isinstance(packet.get(field), str) or not 1 <= len(packet[field]) <= 128:
                raise ValueError('Invalid ' + field)
        if packet.get('schema_version') != 1:
            raise ValueError('Unsupported schema version')
        key = (packet['run_id'], obs['profile']['id'])
        urgency = packet.get('urgency', 0)
        if not isinstance(urgency, (float, int)) or not 0 <= urgency <= 100:
            raise ValueError('Urgency must be 0..100')
        future = Future()
        with self.condition:
            stats = self.per_model[name]
            stats['assigned_requests'] += 1
            if self.mode == 'rules' or self.stopping:
                stats['fallbacks'] += 1
                raise BusyError('Rule baseline / scheduler stopped')
            if key in self.pending or len(self.queue) >= self.queue_limit:
                stats['fallbacks'] += 1
                raise BusyError('Duplicate agent or queue full')
            self.pending.add(key)
            self.sequence += 1
            now = time.monotonic()
            # Aging makes equal-urgency requests FIFO and bounds starvation.
            heapq.heappush(self.queue, (now - urgency * 0.1, self.sequence,
                now, key, name, packet, future))
            self.condition.notify()
        return future

    def decide(self, packet):
        return self.submit(packet).result()

    def _worker(self):
        while True:
            with self.condition:
                self.condition.wait_for(lambda: self._eligible_index() is not None or (self.stopping and not self.queue))
                if self.stopping and not self.queue:
                    return
                index = self._eligible_index()
                if index is None: continue
                _, _, queued_at, key, assigned, packet, future = self.queue.pop(index)
                heapq.heapify(self.queue)
                self.active += 1
                actual = self.fallback_model if self.mode == 'single' else assigned
                self.active_by_model[actual] += 1
                self.active_requests[key] = dict(model=actual, agent_id=key[1], run_id=key[0], request_id=packet['request_id'])
                self.per_model[actual]['requests'] += 1
                started = time.monotonic()
            try:
                if time.monotonic() - queued_at > self.queue_timeout:
                    raise TimeoutError('Scheduler queue deadline expired')
                if future.cancelled():
                    raise TimeoutError('Caller cancelled request')
                # Prevent cancellation after inference begins; duplicate stays reserved.
                if not future.set_running_or_notify_cancel():
                    raise TimeoutError('Caller cancelled request')
                result = self.engines[actual].decide(packet)
                result.update(model=actual, assigned_model=assigned,
                    queue_latency_seconds=time.monotonic() - queued_at - result['latency_seconds'])
                with self.condition:
                    stats = self.per_model[actual]
                    stats['completed'] += 1
                    for field in ('input_tokens', 'output_tokens', 'invalid_responses',
                                  'latency_seconds', 'generation_seconds'):
                        stats[field] += result.get(field, 0)
                future.set_result(result)
            except Exception as error:
                with self.condition:
                    self.per_model[actual]['fallbacks'] += 1
                if not future.cancelled():
                    future.set_exception(error)
            finally:
                with self.condition:
                    self.per_model[actual]['request_latency_seconds'] += time.monotonic() - started
                    self.active -= 1
                    self.active_by_model[actual] -= 1
                    self.active_requests.pop(key, None)
                    self.pending.discard(key)
                    self.condition.notify_all()

    def _eligible_index(self):
        candidates = [(item[:2], i) for i, item in enumerate(self.queue)
            if self.active_by_model[self.fallback_model if self.mode == 'single' else item[4]] < self.per_model_limit]
        return min(candidates)[1] if candidates else None

    def monitor(self):
        provider = self.engines[self.fallback_model].provider
        try:
            models = provider.call('/api/ps', timeout=2)['models']
            resident = {m['name'] for m in models}
            now = time.monotonic()
            with self.condition:
                for name in self.previous_resident - resident:
                    self.unloads.append((now, name))
                    expiration = self.residency.get(name, {}).get('expires_at')
                    try:
                        early = datetime.fromisoformat(expiration.replace('Z', '+00:00')) > datetime.now(timezone.utc)
                    except (AttributeError, ValueError, TypeError):
                        early = False
                    if early and (self.active or self.queue): self.suspected_swaps.append((now, name))
                self.previous_resident = resident
                self.residency = {m['name']: {k: m.get(k) for k in
                    ('size', 'size_vram', 'expires_at', 'context_length')} for m in models}
                self.peak_size = max(self.peak_size, sum(m.get('size', 0) for m in models))
                self.peak_vram = max(self.peak_vram, sum(m.get('size_vram', 0) for m in models))
                self.swap_warning = sum(now - t < 120 for t, _ in self.suspected_swaps) >= 3
                over_budget = sum(m.get('size', 0) for m in models) > self.budget
                if self.auto_fallback and (self.swap_warning or over_budget):
                    self.mode = 'single'
                self.residency_error = ''
        except (OSError, ValueError, KeyError, AttributeError) as error:
            with self.condition:
                self.residency_error = type(error).__name__

    def health(self):
        statuses = {name: engine.provider.health() for name, engine in self.engines.items()}
        self.monitor()
        wanted = [self.fallback_model] if self.mode == 'single' else list(MODELS)
        good = sum(statuses[n] == 'CONNECTED' for n in wanted)
        status = 'CONNECTED' if good == len(wanted) else 'DEGRADED' if good else 'MODEL_UNAVAILABLE'
        if all(s == 'DISCONNECTED' for s in statuses.values()):
            status = 'DISCONNECTED'
        with self.condition:
            duration = max(time.monotonic() - self.started, 0.001)
            metrics = {name: dict(stats,
                average_latency_seconds=stats['latency_seconds'] / max(1, stats['completed']),
                tokens_per_second=stats['output_tokens'] / max(0.001, stats['generation_seconds']),
                decisions_per_second=stats['completed'] / duration) for name, stats in self.per_model.items()}
            for name in MODELS:
                engine_metrics = self.engines[name].metrics
                metrics[name]['invalid_responses'] = engine_metrics.get('invalid_responses', 0)
                metrics[name]['input_tokens'] = engine_metrics.get('all_input_tokens', 0)
                metrics[name]['output_tokens'] = engine_metrics.get('all_output_tokens', 0)
                metrics[name]['generation_seconds'] = engine_metrics.get('all_generation_seconds', 0.0)
                metrics[name]['tokens_per_second'] = metrics[name]['output_tokens'] / max(0.001, metrics[name]['generation_seconds'])
                metrics[name]['average_request_latency_seconds'] = metrics[name]['request_latency_seconds'] / max(1, metrics[name]['requests'])
            return dict(status=status, model=self.fallback_model, mode=self.mode,
                model_status=statuses, per_model=metrics, active=self.active,
                pending=len(self.queue), concurrency=self.concurrency, queue_limit=self.queue_limit,
                per_model_concurrency=self.per_model_limit, active_by_model=dict(self.active_by_model),
                active_requests=list(self.active_requests.values()), trace_write_error=self.traces.write_error,
                residency=dict(self.residency), residency_error=self.residency_error,
                observed_unloads=len(self.unloads), suspected_swaps=len(self.suspected_swaps), swap_warning=self.swap_warning,
                peak_model_bytes=self.peak_size, peak_vram_bytes=self.peak_vram,
                memory_budget_bytes=self.budget,
                memory_budget_exceeded=sum(m.get('size') or 0 for m in self.residency.values()) > self.budget,
                metrics={'completed': sum(s['completed'] for s in self.per_model.values())})

    def close(self):
        with self.condition:
            self.stopping = True
            self.condition.notify_all()
