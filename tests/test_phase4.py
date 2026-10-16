import asyncio
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import httpx
from ai_service.runtime import AsyncRuntime
from ai_service.async_providers import LLMProvider
from ai_service.events import Ledger
from tests.test_ai_service import packet

ANSWER = json.dumps(dict(action='MOVE_TO_SHELTER', target='S5', message='', reason='Check rumor', confidence=.8))


class Phase4Tests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.env = patch.dict(os.environ, {'LLM_TRACE_PATH': str(Path(self.tmp.name)/'trace.jsonl')})
        self.env.start()
        self.seen = []
        self.inflight = self.peak = 0
        self.release = asyncio.Event()
        async def handler(request):
            if request.url.path == '/api/tags':
                return httpx.Response(200, json={'models': [{'name': 'test'}]})
            self.seen.append(json.loads(request.content))
            self.inflight += 1
            self.peak = max(self.peak, self.inflight)
            await self.release.wait()
            self.inflight -= 1
            return httpx.Response(200, json={'message': {'content': ANSWER}, 'eval_count': 10})
        self.config = {g: dict(provider='ollama', model='test', url='http://test', concurrency=10) for g in 'ABC'}
        providers = {g: LLMProvider(c, httpx.AsyncClient(transport=httpx.MockTransport(handler))) for g,c in self.config.items()}
        self.runtime = AsyncRuntime(self.config, providers, Ledger(str(Path(self.tmp.name)/'ledger.sqlite')))

    async def asyncTearDown(self):
        self.release.set()
        await self.runtime.close()
        self.env.stop()
        self.tmp.cleanup()

    def request(self, i=0, group='A'):
        p = packet(f'A{i:03}')
        p['group'] = group
        return p

    async def test_thirty_independent_requests_and_memory_privacy(self):
        requests = [self.request(i, 'ABC'[i//10]) for i in range(30)]
        requests[0]['observation']['memories'] = [{'time': 0, 'text': 'ONLY_AGENT_ZERO'}]
        requests[0]['observation']['hidden_world'] = 'SECRET_WORLD'
        tasks = [asyncio.create_task(self.runtime.decide(p)) for p in requests]
        for _ in range(100):
            if self.peak == 30: break
            await asyncio.sleep(.001)
        self.assertEqual(self.peak, 30)
        self.assertTrue(all(a.active for a in self.runtime.actors.values()))
        self.release.set()
        results = await asyncio.gather(*tasks)
        self.assertTrue(all('decision' in r for r in results))
        self.assertNotIn('SECRET_WORLD', str(self.seen))
        self.assertEqual(sum('ONLY_AGENT_ZERO' in str(p) for p in self.seen), 1)
        self.assertEqual(len({id(a.memory) for a in self.runtime.actors.values()}), 30)

    async def test_capacity_fallback_and_duplicate(self):
        self.config['A']['concurrency'] = 1
        task = asyncio.create_task(self.runtime.decide(self.request()))
        await asyncio.sleep(.01)
        fallback = await self.runtime.decide(self.request(1))
        self.assertTrue(fallback['fallback'])
        self.release.set()
        result = await task
        again = await self.runtime.decide(self.request())
        self.assertEqual(again, result)
        self.assertEqual(len(self.seen), 1)

    async def test_stale_run_and_latest_observation(self):
        p = self.request()
        task = asyncio.create_task(self.runtime.decide(p))
        await asyncio.sleep(.01)
        from ai_service.engine import BusyError
        updated = self.request()
        updated['observation']['goal'] = 'new goal'
        with self.assertRaises(BusyError):
            await self.runtime.decide(updated)
        self.assertEqual(next(iter(self.runtime.actors.values())).latest['goal'], 'new goal')
        self.runtime.invalid_runs.add(p['run_id'])
        self.release.set()
        self.assertTrue((await task)['fallback'])

    async def test_missing_cloud_credentials_safe(self):
        provider = LLMProvider(dict(provider='gemini', model='configured-model', url='http://test', key_env='ABSENT_ESSAIM_KEY'))
        try:
            self.assertEqual(await provider.health_check(), 'UNAVAILABLE')
            with self.assertRaises(RuntimeError):
                await provider.generate_decision('', '')
        finally:
            await provider.client.aclose()

    async def test_rate_limit_no_retry_storm(self):
        calls = []
        async def handler(request):
            calls.append(request)
            return httpx.Response(429, headers={'Retry-After':'60'})
        provider = self.runtime.providers['A']
        await provider.client.aclose()
        provider.client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
        provider.status = 'CONNECTED'
        with self.assertRaises(httpx.HTTPStatusError):
            await provider.generate_decision('', '')
        with self.assertRaises(RuntimeError):
            await provider.generate_decision('', '')
        self.assertEqual(len(calls), 1)

    async def test_invalid_json_fallback(self):
        async def invalid(*args): return 'invalid', (0, 0)
        self.runtime.providers['A'].generate_decision = invalid
        result = await self.runtime.decide(self.request())
        self.assertTrue(result['fallback'])
        self.assertEqual(self.runtime.metrics['invalid_responses'], 1)

    async def test_extended_actions_use_common_validation(self):
        from ai_service.contracts import decision, observation
        obs = observation(self.request()['observation'])
        for action in ('DANCE', 'FLEE_RANDOMLY'):
            answer = json.dumps(dict(action=action, target='', message='', reason='My choice', confidence=.6))
            self.assertEqual(decision(answer,obs)['action'], action)
        unknown_help = json.dumps(dict(action='HELP_AGENT', target='UNSEEN', message='', reason='Help', confidence=.6))
        with self.assertRaises(ValueError):
            decision(unknown_help,obs)

    async def test_cloud_adapters_model_discovery_and_budget(self):
        for kind in ('gemini', 'grok', 'openai'):
            calls = []
            async def handler(request):
                calls.append(request)
                if request.method == 'GET':
                    return httpx.Response(200, json={'models':[{'name':'models/test-model', 'supportedGenerationMethods':['generateContent']}]} if kind == 'gemini' else {'data':[{'id':'test-model'}]})
                return httpx.Response(200, json={'candidates':[{'content':{'parts':[{'text':ANSWER}]}}]} if kind == 'gemini' else {'choices':[{'message':{'content':ANSWER}}]})
            config = dict(provider=kind, model='test-model', url='https://provider.test', key_env='TEST_CLOUD_KEY', request_budget=1, token_budget=10000)
            provider = LLMProvider(config, httpx.AsyncClient(transport=httpx.MockTransport(handler)))
            with patch.dict(os.environ, {'ESSAIM_CLOUD_ENABLED':'true', 'ESSAIM_LOCAL_ONLY':'false', 'TEST_CLOUD_KEY':'TEST_ONLY_SECRET'}):
                try:
                    self.assertEqual(await provider.health_check(), 'CONNECTED')
                    self.assertEqual((await provider.generate_decision('system', '{}'))[0], ANSWER)
                    with self.assertRaises(RuntimeError):
                        await provider.generate_decision('system', '{}')
                    self.assertEqual(sum(r.method == 'POST' for r in calls), 1)
                    self.assertNotIn('TEST_ONLY_SECRET', str(provider.get_metrics()))
                finally:
                    await provider.client.aclose()

    async def test_ledger_survives_restart(self):
        target = str(Path(self.tmp.name)/'restart.sqlite')
        ledger = Ledger(target)
        self.assertEqual(ledger.claim('stable-id'), (True, None))
        ledger.finish('stable-id', {'decision': 'cached'})
        ledger.db.close()
        restarted = Ledger(target)
        try:
            self.assertEqual(restarted.claim('stable-id'), (False, {'decision':'cached'}))
        finally:
            restarted.db.close()

    async def test_kafka_keeps_polling_during_inference_and_commits_in_order(self):
        from types import SimpleNamespace
        from ai_service.events import EventBus
        started = set()
        both_started = asyncio.Event()
        release = asyncio.Event()
        class Consumer:
            polls = 0
            commits = []
            async def getmany(self, **kwargs):
                self.polls += 1
                await asyncio.sleep(.001)
                if self.polls <= 2:
                    return {'partition': [SimpleNamespace(offset=self.polls-1, value=json.dumps({'payload':{'id':self.polls}}).encode())]}
                return {}
            async def commit(self, offsets):
                self.commits.append(offsets)
        async def callback(packet):
            started.add(packet['id'])
            if len(started) == 2:
                both_started.set()
            if packet['id'] == 1:
                await release.wait()
        bus = EventBus()
        bus.consumer = Consumer()
        task = asyncio.create_task(bus.consume(callback))
        try:
            await asyncio.wait_for(both_started.wait(), 3)
            self.assertEqual(started, {1,2})
            self.assertEqual(bus.consumer.commits, [])
            release.set()
            await asyncio.sleep(.03)
            self.assertEqual(bus.consumer.commits[-1], {'partition':2})
        finally:
            task.cancel()
            await asyncio.gather(task, return_exceptions=True)

    async def test_kafka_request_projection_drops_untrusted_fields(self):
        from unittest.mock import AsyncMock
        p = self.request()
        p['api_key'] = 'SECRET_NOT_ALLOWED'
        p['observation']['hidden_world'] = 'HIDDEN_NOT_ALLOWED'
        self.runtime.bus.status = 'CONNECTED'
        self.runtime.bus.request_decision = AsyncMock(return_value={})
        await self.runtime.dispatch(p)
        sent = self.runtime.bus.request_decision.call_args.args[0]
        self.assertNotIn('SECRET_NOT_ALLOWED', str(sent))
        self.assertNotIn('HIDDEN_NOT_ALLOWED', str(sent))
