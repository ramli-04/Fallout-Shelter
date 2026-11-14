import asyncio
import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

from langchain_core.documents import Document

from ai_service.cognitive_retrieval import PrivateKnowledgeRetriever, private_documents, retrieve_private_context
from ai_service.cognitive_tools import build_cognitive_tools, tool_for_decision
from ai_service.contracts import observation
from ai_service.events import EventBus
from ai_service.langgraph_decisions import InvalidDecisionResponse, LangGraphDecisionWorkflow, create_langchain_model
from ai_service.schemas import Decision
from tests.test_ai_service import packet


class FakeStructuredModel:
    def __init__(self, action="MOVE_TO_SHELTER", target="S5", message="", error=None):
        self.action = action
        self.target = target
        self.message = message
        self.error = error
        self.prompts = []

    async def ainvoke(self, prompt_value):
        prompt = prompt_value.to_string()
        self.prompts.append(prompt)
        if self.error:
            raise self.error
        result = Decision(action=self.action, target=self.target, message=self.message,
                          reason="Use known evidence", confidence=0.8)
        return {"parsed": result, "raw": SimpleNamespace(content="{}", usage_metadata={
            "input_tokens": 11, "output_tokens": 7}, response_metadata={})}


class FakeShelterModel:
    def __init__(self, action="SHARE", target="CHILD1", reason="A dependent needs food"):
        self.action = action
        self.target = target
        self.reason = reason
        self.prompts = []

    async def ainvoke(self, prompt_value):
        self.prompts.append(prompt_value.to_string())
        return {"action": self.action, "target": self.target, "reason": self.reason}


class FakeProvider:
    kind = "ollama"
    model = "offline-test"


class LangGraphCognitionTests(unittest.IsolatedAsyncioTestCase):
    async def test_shelter_token_usage_survives_graph(self):
        class MeteredShelterModel(FakeShelterModel):
            async def ainvoke(self, prompt_value):
                return {"parsed": await super().ainvoke(prompt_value),
                        "raw": SimpleNamespace(usage_metadata={"input_tokens": 31, "output_tokens": 9})}
        workflow = LangGraphDecisionWorkflow(shelter_model_factory=lambda _: MeteredShelterModel())
        result = await workflow.ainvoke_shelter(FakeProvider(), run_id="tokens", request_id="r1",
            profile={"id": "A001"}, context={}, allowed_actions=["SHARE"], allowed_targets=["CHILD1"])
        self.assertEqual(result["usage"], (31, 9))
        self.assertEqual(result["decision"]["action"], "SHARE")

    def setUp(self):
        self.obs = observation(packet()["observation"])

    async def test_graph_runs_all_cognitive_stages_and_emits_private_decision(self):
        model = FakeStructuredModel()
        events = []

        async def sink(topic, event_type, payload, state):
            events.append((topic, event_type, payload, state["run_id"]))

        workflow = LangGraphDecisionWorkflow(lambda _: model, sink)
        result = await workflow.ainvoke(FakeProvider(), run_id="run-a", request_id="r1",
                                        observation=self.obs, own_memory=[])
        self.assertEqual(result["decision"]["action"], "MOVE_TO_SHELTER")
        self.assertEqual(result["usage"], (11, 7))
        self.assertIn("retrieve_relevant_memory", result["stages"])
        self.assertIn("evaluate_needs", result["stages"])
        self.assertIn("validate_action", result["stages"])
        self.assertIn("commit_decision", result["stages"])
        self.assertTrue(any(event[1] == "agent.belief_updated" for event in events))
        self.assertNotIn("complete_world_state", model.prompts[0])

    async def test_agent_memories_do_not_cross_retrieval_or_prompt_boundaries(self):
        model = FakeStructuredModel()
        workflow = LangGraphDecisionWorkflow(lambda _: model)
        first = observation(packet("A001")["observation"])
        second = observation(packet("A002")["observation"])
        await workflow.ainvoke(FakeProvider(), run_id="run-a", request_id="1", observation=first,
                               own_memory=[{"time": 1, "text": "PRIVATE_A001_MEMORY_TOKEN shelter observation"}])
        await workflow.ainvoke(FakeProvider(), run_id="run-a", request_id="2", observation=second,
                               own_memory=[{"time": 1, "text": "PRIVATE_A002_MEMORY_TOKEN shelter observation"}])
        self.assertIn("PRIVATE_A001_MEMORY_TOKEN", model.prompts[0])
        self.assertNotIn("PRIVATE_A002_MEMORY_TOKEN", model.prompts[0])
        self.assertIn("PRIVATE_A002_MEMORY_TOKEN", model.prompts[1])
        self.assertNotIn("PRIVATE_A001_MEMORY_TOKEN", model.prompts[1])

    async def test_accident_branch_and_validated_communication_tool(self):
        observation_data = packet()["observation"]
        observation_data["nearby_agents"] = [{"id": "AUTH1", "role": "Authority", "position": [2, 2], "state": "PATROL"}]
        observation_data["social_beliefs"] = {"accident:V1": {"claimed_value": "collision nearby",
            "source": "A010", "confidence": 0.7, "evidence": "direct observation", "status": "KNOWN"}}
        obs = observation(observation_data)
        model = FakeStructuredModel(action="COMMUNICATE", target="AUTH1",
                                    message="Emergency assistance requested: vehicle collision")
        events = []

        async def sink(topic, event_type, payload, state):
            events.append((topic, event_type, payload))

        result = await LangGraphDecisionWorkflow(lambda _: model, sink).ainvoke(
            FakeProvider(), run_id="run-a", request_id="accident", observation=obs, own_memory=[])
        self.assertIn("accident", result["stages"])
        self.assertEqual(result["decision"]["target"], "AUTH1")
        self.assertTrue(any(event[0] == "agent.communications" for event in events))

    async def test_provider_exception_is_propagated_for_runtime_fallback(self):
        model = FakeStructuredModel(error=TimeoutError("provider timed out"))
        workflow = LangGraphDecisionWorkflow(lambda _: model)
        with self.assertRaises(TimeoutError):
            await workflow.ainvoke(FakeProvider(), run_id="run-a", request_id="timeout",
                                   observation=self.obs, own_memory=[])

    async def test_shelter_langgraph_validates_bounded_family_resource_choices(self):
        model = FakeShelterModel()
        workflow = LangGraphDecisionWorkflow(shelter_model_factory=lambda _: model)
        result = await workflow.ainvoke_shelter(FakeProvider(), run_id="run-shelter",
            request_id="family-food", profile={"id": "A001", "occupation": "Parent"},
            context={"activity": "DISTRIBUTE_RESOURCES", "dependent_needs_food": True},
            allowed_actions=["CONTINUE", "SHARE"], allowed_targets=["CHILD1"])
        self.assertEqual(result["decision"], {"action": "SHARE", "target": "CHILD1",
                                               "reason": "A dependent needs food"})
        self.assertEqual(result["stages"], ["assess_needs_and_constraints", "choose_shelter_response",
                                             "validate_shelter_choice", "commit_shelter_choice"])
        self.assertIn("DISTRIBUTE_RESOURCES", model.prompts[0])

        invalid = LangGraphDecisionWorkflow(shelter_model_factory=lambda _: FakeShelterModel(action="TELEPORT"))
        with self.assertRaises(InvalidDecisionResponse):
            await invalid.ainvoke_shelter(FakeProvider(), run_id="run-shelter", request_id="bad-choice",
                profile={"id": "A001"}, context={}, allowed_actions=["CONTINUE", "SHARE"])

    def test_action_tools_recheck_phone_family_and_authority_permissions(self):
        _, civilian_tools, civilian_available = build_cognitive_tools(self.obs)
        self.assertNotIn("ISSUE_ALERT", civilian_tools)
        self.assertNotIn("issue_authority_order", civilian_available)
        self.assertNotIn("CALL", civilian_tools)

        with_phone = packet()["observation"]
        with_phone["profile"].update(has_phone=True)
        with_phone["family_relationships"] = {"CHILD1": "child"}
        _, phone_tools, phone_available = build_cognitive_tools(observation(with_phone))
        self.assertIn("CALL", phone_tools)
        self.assertIn("call_family_member", phone_available)
        with self.assertRaises(ValueError):
            phone_tools["CALL"].invoke({"target": "UNKNOWN", "message": "", "reason": "", "confidence": 0.5})

        authority = packet()["observation"]
        authority["profile"]["role"] = "Authority"
        _, authority_tools, _ = build_cognitive_tools(observation(authority))
        self.assertIn("ISSUE_ALERT", authority_tools)
        self.assertEqual(tool_for_decision("ISSUE_ALERT", authority_tools).name, "issue_authority_order")

    def test_retrieval_returns_private_road_and_memory_provenance(self):
        data = packet()["observation"]
        data["social_beliefs"] = {"road:R17": {"claimed_value": "closed", "source": "A003",
            "confidence": 0.9, "evidence": "direct observation", "status": "KNOWN"}}
        obs = observation(data)
        docs = private_documents(obs, [{"time": 12, "text": "I saw road R17 blocked."}])
        retriever = PrivateKnowledgeRetriever(documents=docs, agent_id="A001", role="Civilian", k=6)
        found = retriever.invoke("road R17 closed traffic blocked")
        sources = {doc.metadata.get("source_id") for doc in found}
        self.assertIn("belief:social:A001:road:R17", sources)
        self.assertTrue(any(source.startswith("memory:A001:") for source in sources))
        map_sources = {doc.metadata.get("source_id") for doc in
                       retrieve_private_context(obs, [], "known city map shelter positions")}
        self.assertIn("map_view:A001:10", map_sources)

        isolated = PrivateKnowledgeRetriever(documents=[
            Document(page_content="family private token location", metadata={"visibility": "private", "owner_id": "A002"}),
            Document(page_content="public shelter procedure", metadata={"visibility": "public"}),
        ], agent_id="A001", role="Civilian")
        result = isolated.invoke("family private token shelter procedure")
        self.assertFalse(any("private token" in doc.page_content for doc in result))
        self.assertTrue(any(doc.metadata.get("visibility") == "public" for doc in result))

    def test_langchain_adapter_factory_supports_ollama_and_optional_clouds(self):
        from unittest.mock import patch
        providers = [
            ("ollama", "llama3.2:1b", "http://127.0.0.1:11434", ""),
            ("openai", "gpt-4o-mini", "https://api.openai.com/v1", "OPENAI_API_KEY"),
            ("compatible", "grok-test", "https://api.x.ai/v1", "XAI_API_KEY"),
            ("gemini", "gemini-2.0-flash", "https://generativelanguage.googleapis.com/v1beta", "GEMINI_API_KEY"),
        ]
        with patch.dict("os.environ", {"OPENAI_API_KEY": "test", "XAI_API_KEY": "test", "GEMINI_API_KEY": "test"}):
            for kind, model, url, key_env in providers:
                provider = SimpleNamespace(kind=kind, model=model, url=url,
                    config={"key_env": key_env, "max_tokens": 64, "temperature": 0.2})
                runnable = create_langchain_model(provider)
                self.assertTrue(callable(runnable.ainvoke))

    async def test_kafka_event_schema_has_simulation_run_and_wall_time(self):
        class Producer:
            def __init__(self):
                self.messages = []
            async def send_and_wait(self, topic, key, value):
                self.messages.append((topic, json.loads(value)))

        bus = EventBus()
        bus.producer = Producer()
        delivered = await bus.publish("shelter.events", {"simulation_timestamp": 42.5, "event": "intent"},
            "run-a", "A001", "req-9", event_type="agent.shelter_intent")
        self.assertTrue(delivered)
        topic, event = bus.producer.messages[0]
        self.assertEqual(topic, "essaim.shelter.events")
        self.assertEqual(event["schema_version"], 1)
        self.assertEqual(event["run_id"], "run-a")
        self.assertEqual(event["simulation_timestamp"], 42.5)
        self.assertTrue(event["wall_timestamp"])
        self.assertEqual(event["correlation_id"], "req-9")


if __name__ == "__main__":
    unittest.main()
