import json
import tempfile
import unittest
from pathlib import Path
from fastapi.testclient import TestClient
from ai_service.engine import Engine
from ai_service.traces import TraceStore
from tests.test_ai_service import packet, TestProvider


class TraceTests(unittest.TestCase):
    def test_restart_marks_unfinished_attempts_interrupted(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'traces.jsonl'
            TraceStore(path).start(model='llama3.2:1b', agent_id='A001')
            self.assertEqual(TraceStore(path).list()[0]['status'], 'INTERRUPTED')

    def test_raw_invalid_output_retry_and_exact_prompts_survive_restart(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'traces.jsonl'
            store = TraceStore(path)
            provider = TestProvider()
            valid = provider.generate
            attempts = []
            def generate(system, prompt):
                attempts.append((system, prompt))
                return {'message': {'content': '{}'}} if len(attempts) == 1 else valid(system, prompt)
            provider.generate = generate
            engine = Engine(provider)
            engine.trace_store = store
            engine.decide(packet())
            records = list(reversed(store.list()))
            self.assertEqual([r['status'] for r in records], ['INVALID', 'VALID'])
            self.assertEqual(records[0]['raw_answer'], '{}')
            self.assertTrue(records[0]['error'])
            self.assertEqual([(r['system_prompt'], r['prompt']) for r in records], attempts)
            restored = TraceStore(path)
            self.assertEqual(restored.list(), store.list())
            self.assertEqual(len(restored.list(agent='other')), 0)

    def test_error_retention_and_bounded_history(self):
        with tempfile.TemporaryDirectory() as directory:
            store = TraceStore(Path(directory)/'traces.jsonl', capacity=2)
            provider = TestProvider()
            provider.generate = lambda *_: (_ for _ in ()).throw(TimeoutError('inference deadline'))
            engine = Engine(provider)
            engine.trace_store = store
            for i in range(3):
                with self.assertRaises(TimeoutError): engine.decide(packet(f'A{i}'))
            self.assertEqual(len(store.list()), 2)
            self.assertTrue(all(r['status'] == 'ERROR' for r in store.list()))
            self.assertIn('inference deadline', store.list()[0]['error'])

    def test_inspector_api_filters_summaries_and_detail(self):
        from ai_service import main
        original = main.engine.traces
        with tempfile.TemporaryDirectory() as directory:
            try:
                main.engine.traces = TraceStore(Path(directory)/'traces.jsonl')
                identity = main.engine.traces.start(model='llama3.2:1b', agent_id='A001',
                    run_id='test', system_prompt='private-system', prompt='<script>bad()</script>')
                client = TestClient(main.app)
                self.assertEqual(client.get('/inspector').status_code, 200)
                result = client.get('/traces?model=llama3.2:1b&agent=A001&run=test').json()['items']
                self.assertEqual(len(result), 1)
                self.assertNotIn('prompt', result[0])
                self.assertEqual(client.get('/traces?agent=A002').json()['items'], [])
                self.assertEqual(client.get('/traces/'+identity).json()['system_prompt'], 'private-system')
                self.assertEqual(client.get('/traces/missing').status_code, 404)
                self.assertEqual(client.get('/traces?limit=10000').status_code, 422)
            finally:
                main.engine.traces = original
