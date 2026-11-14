import copy
import json
import unittest

from ai_service.contracts import observation, decision
from ai_service.langgraph_decisions import _compact_observation
from tests.test_ai_service import packet


class CognitiveContractTests(unittest.TestCase):
    def sample(self):
        raw = packet()['observation']
        raw['perceptions'] = [dict(kind='accident', id='V1', position=[3, 4], distance=2,
                                   severity=.7, confidence=.9, timestamp=9,
                                   director={'secret': 'HIDDEN'})]
        raw['experience'] = copy.deepcopy(raw['perceptions'])
        raw['cognitive_traits'] = dict(altruism=90, fear=25, world='HIDDEN')
        return raw

    def test_private_sensor_context_reaches_reasoning(self):
        clean = observation(self.sample())
        prompt = _compact_observation(clean)
        self.assertEqual(prompt['perceptions'][0]['kind'], 'accident')
        self.assertEqual(prompt['experience'][0]['timestamp'], 9)
        self.assertEqual(prompt['cognitive_traits']['altruism'], 90)
        self.assertNotIn('HIDDEN', str(prompt))

    def test_sensor_inputs_are_bounded(self):
        raw = self.sample()
        raw['perceptions'] *= 100
        self.assertEqual(len(observation(raw)['perceptions']), 24)

    def test_invalid_sensor_values_rejected(self):
        for key, value in [('position', [float('nan'), 0]), ('confidence', 1.5),
                           ('distance', -1), ('timestamp', {}), ('speed', float('inf'))]:
            with self.subTest(key=key):
                raw = self.sample()
                raw['perceptions'][0][key] = value
                with self.assertRaises(ValueError): observation(raw)

    def test_invalid_traits_rejected(self):
        raw = self.sample()
        raw['cognitive_traits']['fear'] = 200
        with self.assertRaises(ValueError): observation(raw)

    def test_active_evacuation_excludes_return_to_source_shelter(self):
        raw = self.sample()
        raw['excluded_shelters'] = ['S5']
        clean = observation(raw)
        self.assertEqual(_compact_observation(clean)['excluded_shelters'], ['S5'])
        with self.assertRaises(ValueError):
            decision(json.dumps(dict(action='MOVE_TO_SHELTER', target='S5', message='',
                                     reason='Return immediately', confidence=.8)), clean)

    def test_post_impact_transfer_requires_verified_destination(self):
        raw = self.sample()
        raw['requires_verified_shelter'] = True
        action = json.dumps(dict(action='MOVE_TO_SHELTER', target='S5', message='',
                                 reason='Transfer', confidence=.8))
        with self.assertRaises(ValueError): decision(action, observation(raw))
        raw['beliefs']['S5'].update(existence_probability=1, confidence=.95, safety_status='SAFE', unavailable=False)
        self.assertEqual(decision(action, observation(raw))['target'], 'S5')


class CognitiveGraphTests(unittest.IsolatedAsyncioTestCase):
    async def test_local_accident_selects_contextual_graph_branch(self):
        from ai_service.langgraph_decisions import LangGraphDecisionWorkflow
        from tests.test_langgraph_cognition import FakeStructuredModel, FakeProvider
        model = FakeStructuredModel(action="OBSERVE", target="")
        raw = CognitiveContractTests().sample()
        clean = observation(raw)
        workflow = LangGraphDecisionWorkflow(lambda _: model)
        result = await workflow.ainvoke(FakeProvider(), run_id="sensor-run", request_id="sensor-1",
                                        observation=clean, own_memory=[])
        self.assertIn("accident", result["stages"])
        self.assertIn("V1", model.prompts[0])
        self.assertNotIn("HIDDEN", model.prompts[0])
        self.assertEqual(result["decision"]["action"], "OBSERVE")


if __name__ == '__main__': unittest.main()
