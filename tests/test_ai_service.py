import json
import threading
import unittest
from http.server import ThreadingHTTPServer
from urllib.request import Request, urlopen
from urllib.error import HTTPError
from ai_service.contracts import observation, decision
from ai_service.engine import Engine, BusyError
from ai_service.server import handler_for
from ai_service.provider import OllamaProvider


def packet(agent='A001', run='test-run'):
    return {'schema_version': 1, 'run_id': run, 'request_id': '1', 'observation': {
        'profile': {'id': agent, 'role': 'Civilian', 'primary_personality': 'SKEPTICAL'},
        'position': [1, 2], 'destination': '', 'goal': 'Find safety',
        'simulation_time': 10, 'estimated_time_remaining': 400,
        'beliefs': {'S5': {'position': [100, 100], 'existence_probability': 0.5,
                          'source': 'Rumor', 'confidence': 0.4}},
        'memories': [{'time': 1, 'text': 'My private experience'}],
        'messages': [{'claim': 'S5 exists', 'original_source': 'A003',
                      'current_speaker': 'A004', 'kind': 'rumor'}], 'nearby_agents': []}}


class TestProvider:
    model = 'TEST_ONLY'
    def __init__(self):
        self.calls = []
    def health(self):
        return 'CONNECTED'
    def generate(self, system, prompt):
        self.calls.append((system, prompt))
        return {'message': {'content': json.dumps({'action': 'MOVE_TO_SHELTER',
            'target': 'S5', 'message': '', 'reason': 'Investigate rumor', 'confidence': 0.8})}, 'eval_count': 12}


class ServiceTests(unittest.TestCase):
    def setUp(self):
        import tempfile
        from unittest.mock import patch
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        environment = patch.dict('os.environ', {'LLM_TRACE_PATH': directory.name + '/traces.jsonl'})
        environment.start()
        self.addCleanup(environment.stop)

    def test_nested_hidden_fields_do_not_reach_prompt(self):
        request = packet()
        secret = 'HIDDEN_WORLD_SENTINEL'
        request['observation']['director'] = secret
        request['observation']['countdown_seconds'] = secret
        request['observation']['profile']['world'] = secret
        request['observation']['beliefs']['S5']['observation_signature'] = secret
        request['observation']['beliefs']['S5']['exists'] = secret
        request['observation']['messages'][0]['evidence'] = {'supply_level': secret}
        provider = TestProvider()
        Engine(provider).decide(request)
        self.assertNotIn(secret, str(provider.calls))
        self.assertIn('A003', provider.calls[0][1])
        self.assertIn('0.5', provider.calls[0][1])

    def test_complex_allowed_scalar_rejected(self):
        request = packet()['observation']
        request['beliefs']['S5']['source'] = {'world': 'secret'}
        with self.assertRaises(ValueError):
            observation(request)

    def test_agent_and_run_memory_isolation_and_bounds(self):
        provider = TestProvider()
        engine = Engine(provider)
        request = packet()
        request['observation']['memories'][0]['text'] = 'A001_PRIVATE_SENTINEL'
        engine.decide(request)
        engine.decide(packet('A002'))
        engine.decide(packet('A001', 'new-run'))
        self.assertNotIn('A001_PRIVATE_SENTINEL', provider.calls[1][1])
        self.assertNotIn('A001_PRIVATE_SENTINEL', provider.calls[2][1])
        for i in range(30):
            request['observation']['memories'] = [{'time': i, 'text': f'Observed important {i}'}]
            engine.decide(request)
        memory = engine.memories[('test-run', 'A001')]
        self.assertLessEqual(len(memory['recent']), 12)
        self.assertLessEqual(len(memory['important']), 8)
        self.assertTrue(memory['summary'])

    def test_decision_validation(self):
        obs = observation(packet()['observation'])
        for data in [ {'action': 'HACK'}, {'action': 'HELP_AGENT', 'target': 'A099', 'message': '', 'reason': 'help'},
                      {'action': 'MOVE_TO_SHELTER', 'target': 'S9', 'message': '', 'reason': 'go'} ]:
            with self.assertRaises(ValueError):
                decision(json.dumps(data), obs)
        with self.assertRaises(ValueError):
            decision('```json\n{}\n```', obs)

    def test_http_contract_and_invalid_body(self):
        engine = Engine(TestProvider())
        server = ThreadingHTTPServer(('127.0.0.1', 0), handler_for(engine))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        url = f'http://127.0.0.1:{server.server_port}'
        try:
            with urlopen(url+'/health') as response:
                self.assertEqual(json.load(response)['status'], 'CONNECTED')
            req = Request(url+'/v1/decision', data=json.dumps(packet()).encode())
            with urlopen(req) as response:
                result = json.load(response)
                self.assertEqual(result['request_id'], '1')
                self.assertEqual(result['provider'], 'LOCAL_LLM')
            with self.assertRaises(HTTPError) as caught:
                urlopen(Request(url+'/v1/decision', data=b'[]'))
            self.assertEqual(caught.exception.code, 422)
            caught.exception.close()
        finally:
            server.shutdown()
            server.server_close()
            thread.join()

    def test_scheduler_serializes_and_limits_queue(self):
        provider = TestProvider()
        entered = threading.Event()
        release = threading.Event()
        original = provider.generate
        def blocked(system, prompt):
            entered.set()
            release.wait(2)
            return original(system, prompt)
        provider.generate = blocked
        engine = Engine(provider, max_pending=1)
        worker = threading.Thread(target=lambda: engine.decide(packet()))
        worker.start()
        self.assertTrue(entered.wait(2))
        try:
            with self.assertRaises(BusyError):
                engine.decide(packet('A002'))
        finally:
            release.set()
            worker.join()
        self.assertEqual(len(provider.calls), 1)

    def test_failure_marks_degraded_and_recovery(self):
        provider = TestProvider()
        original = provider.generate
        provider.generate = lambda *_: {'message': {'content': 'invalid'}}
        engine = Engine(provider)
        with self.assertRaises(ValueError):
            engine.decide(packet())
        self.assertEqual(engine.health()['status'], 'DEGRADED')
        provider.generate = original
        engine.decide(packet())
        self.assertEqual(engine.health()['status'], 'CONNECTED')

    def test_fastapi_async_runtime_endpoints(self):
        from fastapi.testclient import TestClient
        from ai_service import main
        from unittest.mock import AsyncMock, patch
        with patch.object(main.engine, 'dispatch', new=AsyncMock(return_value={'run_id': 'test-run'})):
            client = TestClient(main.app)
            self.assertEqual(client.get('/health').status_code, 200)
            self.assertEqual(client.post('/decide', json=packet()).json()['run_id'], 'test-run')

    def test_ollama_model_check_and_shared_options(self):
        provider = OllamaProvider()
        provider.call = lambda *_args, **_kwargs: {'models': [{'name': provider.model}]}
        self.assertEqual(provider.health(), 'CONNECTED')
        provider.call = lambda *_args, **_kwargs: {'models': []}
        self.assertEqual(provider.health(), 'MODEL_UNAVAILABLE')
        seen = []
        provider.call = lambda *args, **kwargs: seen.append(args) or {}
        provider.generate('personality', 'private observation')
        self.assertEqual(seen[0][0], '/api/chat')
        self.assertEqual(seen[0][1]['options']['num_ctx'], 2048)
        self.assertFalse(seen[0][1]['stream'])


if __name__ == '__main__':
    unittest.main()
