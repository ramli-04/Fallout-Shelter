import threading
import time
import unittest
import tempfile
from unittest.mock import patch

from ai_service.engine import BusyError
from ai_service.pool import ModelPool, MODELS
from tests.test_ai_service import packet, TestProvider


class BlockingProvider(TestProvider):
    def __init__(self, event, counter, model):
        super().__init__()
        self.event, self.counter, self.model = event, counter, model

    def generate(self, system, prompt):
        with self.counter['lock']:
            self.counter['active'] += 1
            self.counter['peak'] = max(self.counter['peak'], self.counter['active'])
            self.counter['order'].append(self.model)
        self.event.wait(2)
        try:
            return super().generate(system, prompt)
        finally:
            with self.counter['lock']:
                self.counter['active'] -= 1


class PoolTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        environment = patch.dict('os.environ', {'LLM_TRACE_PATH': directory.name + '/traces.jsonl'})
        environment.start()
        self.addCleanup(environment.stop)
        self.event = threading.Event()
        self.counter = dict(lock=threading.Lock(), active=0, peak=0, order=[])
        self.providers = {m: BlockingProvider(self.event, self.counter, m) for m in MODELS}
        self.pool = ModelPool(self.providers, concurrency=1, queue_limit=2)

    def tearDown(self):
        self.event.set()
        self.pool.close()
        for worker in self.pool.workers:
            worker.join(3)

    def wait_active(self):
        deadline = time.monotonic()+2
        while not self.counter['active'] and time.monotonic() < deadline:
            time.sleep(0.005)
        self.assertEqual(self.counter['active'], 1)

    def test_global_limit_priority_bounds_and_duplicate(self):
        first = self.pool.submit(dict(packet(), model=MODELS[0]))
        self.wait_active()
        low = self.pool.submit(dict(packet('A002'), model=MODELS[1], urgency=0))
        high = self.pool.submit(dict(packet('A003'), model=MODELS[2], urgency=100))
        with self.assertRaises(BusyError): self.pool.submit(packet('A004'))
        with self.assertRaises(BusyError): self.pool.submit(packet())
        self.event.set()
        for future in (first, low, high): self.assertIn('decision', future.result(3))
        self.assertEqual(self.counter['peak'], 1)
        self.assertEqual(self.counter['order'], [MODELS[0], MODELS[2], MODELS[1]])

    def test_memory_survives_switch_to_single_and_agent_isolation(self):
        self.event.set()
        req = dict(packet(), model=MODELS[0])
        req['observation']['memories'][0]['text'] = 'private-pool-sentinel'
        self.pool.decide(req)
        self.pool.mode = 'single'
        result = self.pool.decide(dict(packet(), model=MODELS[2]))
        self.assertEqual(result['model'], 'llama3.2:1b')
        self.assertIn('private-pool-sentinel', self.providers['llama3.2:1b'].calls[-1][1])
        self.pool.decide(packet('A002'))
        self.assertNotIn('private-pool-sentinel', self.providers['llama3.2:1b'].calls[-1][1])

    def test_queue_timeout_and_rule_mode(self):
        self.pool.queue_timeout = 0.01
        first = self.pool.submit(packet())
        self.wait_active()
        second = self.pool.submit(packet('A002'))
        time.sleep(0.03)
        self.event.set()
        first.result(3)
        with self.assertRaises(TimeoutError): second.result(3)
        self.pool.mode = 'rules'
        with self.assertRaises(BusyError): self.pool.submit(packet('A003'))

    def test_residency_unload_detection_and_budget(self):
        provider = self.providers['llama3.2:1b']
        entries = []
        provider.call = lambda *args, **kwargs: {'models': list(entries)}
        for _ in range(3):
            entries[:] = [{'name': MODELS[0], 'size': 100, 'size_vram': 80,
                'expires_at': '2099-01-01T00:00:00+00:00'}]
            self.pool.monitor()
            entries.clear()
            self.pool.active = 1
            self.pool.monitor()
            self.pool.active = 0
        self.assertTrue(self.pool.swap_warning)
        self.pool.auto_fallback = True
        self.pool.monitor()
        self.assertEqual(self.pool.mode, 'single')
        self.assertEqual(self.pool.peak_vram, 80)

    def test_configurable_concurrency_including_same_model(self):
        pool = ModelPool(self.providers, concurrency=2, queue_limit=2)
        pool.per_model_limit = 2
        try:
            futures = [pool.submit(dict(packet(f'A{i:03d}'), model=MODELS[0])) for i in range(2)]
            deadline = time.monotonic()+2
            while self.counter['active'] < 2 and time.monotonic() < deadline:
                time.sleep(0.005)
            self.assertEqual(self.counter['active'], 2)
            self.event.set()
            for future in futures: future.result(3)
            self.assertEqual(self.counter['peak'], 2)
        finally:
            pool.close()
            for worker in pool.workers: worker.join(3)

    def test_natural_expiry_does_not_trigger_swap_fallback(self):
        provider = self.providers['llama3.2:1b']
        entries = []
        provider.call = lambda *args, **kwargs: {'models': list(entries)}
        self.pool.auto_fallback = True
        for _ in range(3):
            entries[:] = [{'name': MODELS[0], 'size': 100, 'size_vram': 80,
                'expires_at': '2000-01-01T00:00:00+00:00'}]
            self.pool.monitor()
            entries.clear()
            self.pool.monitor()
        self.assertFalse(self.pool.swap_warning)
        self.assertEqual(self.pool.mode, 'multi')

    def test_three_models_overlap_without_busy_model_blocking_others(self):
        pool = ModelPool(self.providers, concurrency=3, queue_limit=8)
        try:
            futures = [pool.submit(dict(packet('A001'), model=MODELS[0]))]
            self.wait_active()
            futures.append(pool.submit(dict(packet('A002'), model=MODELS[0], urgency=100)))
            futures.extend(pool.submit(dict(packet(f'A{i+3:03d}'), model=model))
                for i, model in enumerate(MODELS[1:]))
            deadline = time.monotonic()+2
            while self.counter['active'] < 3 and time.monotonic() < deadline: time.sleep(.005)
            self.assertEqual(self.counter['active'], 3)
            self.assertEqual(pool.active_by_model, dict.fromkeys(MODELS, 1))
            self.event.set()
            for future in futures: future.result(3)
            self.assertEqual(self.counter['peak'], 3)
        finally:
            self.event.set()
            pool.close()
            for worker in pool.workers: worker.join(3)
