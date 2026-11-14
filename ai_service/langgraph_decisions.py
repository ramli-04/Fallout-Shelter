"""LangChain model adapters and per-agent LangGraph decision workflow.

Godot remains the physical simulation. This graph receives only one validated
agent observation and returns one intention from the existing Godot contract.
"""
from __future__ import annotations

import json
import math
from typing import Any, Callable, TypedDict

from langchain.chat_models import init_chat_model
from langchain_core.exceptions import OutputParserException
from langchain_core.prompts import ChatPromptTemplate
from langgraph.graph import END, START, StateGraph
from pydantic import BaseModel, ConfigDict, Field

from .cognitive_retrieval import retrieve_private_context
from .cognitive_tools import build_cognitive_tools, tool_for_decision
from .contracts import ACTIONS, decision
from .schemas import Decision


class InvalidDecisionResponse(ValueError):
    """Structured model output failed schema or agent-tool authorization."""


class ShelterChoice(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    action: str = Field(min_length=1, max_length=32)
    target: str = Field(default="", max_length=64)
    reason: str = Field(default="", max_length=160)


class ShelterState(TypedDict, total=False):
    run_id: str
    request_id: str
    agent_id: str
    provider_key: str
    profile: dict
    context: dict
    allowed_actions: list[str]
    allowed_targets: list[str]
    pending_choice: dict
    committed_choice: dict
    graph_stages: list[str]
    usage: tuple[int, int]


def _number(value: Any, default: float = 0.0) -> float:
    try:
        number = float(value)
        return number if math.isfinite(number) else default
    except (TypeError, ValueError):
        return default


class CognitiveState(TypedDict, total=False):
    run_id: str
    request_id: str
    agent_id: str
    provider_key: str
    observation: dict
    own_memory: list[dict]
    role: str
    personality: dict
    simulated_iq: int | float | None
    beliefs: dict
    current_goals: list[str]
    family_relationships: dict
    available_tools: list[str]
    runtime_tools: dict
    visible_facts: dict
    retrieved_context: list[dict]
    retrieval_provenance: list[dict]
    belief_updates: dict
    needs: dict
    branch: str
    branch_guidance: str
    prompt: str
    provider_result: dict
    pending_decision: dict
    committed_decision: dict
    graph_stages: list[str]


def _create_chat_model(provider):
    """Create the LangChain chat adapter that matches existing ESSAIM config."""
    kind = provider.kind
    model = provider.model
    maximum = int(provider.config.get("max_tokens", 128))
    temperature = float(provider.config.get("temperature", 0.2))
    if kind == "ollama":
        chat = init_chat_model(model, model_provider="ollama", base_url=provider.url,
                               temperature=temperature, num_predict=maximum)
    elif kind == "gemini":
        import os
        key = os.getenv(provider.config.get("key_env", ""), "")
        chat = init_chat_model(model, model_provider="google-genai", api_key=key,
                               temperature=temperature, max_output_tokens=maximum)
    else:
        import os
        key = os.getenv(provider.config.get("key_env", ""), "")
        chat = init_chat_model(model, model_provider="openai", api_key=key,
                               base_url=provider.url, temperature=temperature, max_tokens=maximum)
    return chat


def create_langchain_model(provider):
    """Create the structured standard-decision adapter."""
    return _create_chat_model(provider).with_structured_output(Decision, include_raw=True)


def create_langchain_shelter_model(provider):
    """Create a structured adapter for bounded, event-triggered shelter choices."""
    return _create_chat_model(provider).with_structured_output(ShelterChoice, include_raw=True)


def _compact_observation(observation: dict) -> dict:
    """Build a bounded prompt view from the already-validated private projection."""
    profile = observation["profile"]
    profile_keys = ("id", "role", "primary_personality", "secondary_personality", "panic_level",
                    "skepticism", "cooperation", "risk_tolerance", "empathy", "family_concern",
                    "fatigue", "health", "stress", "safety", "vehicle_id", "has_phone", "iq")
    beliefs = {}
    for identity, belief in list(observation.get("beliefs", {}).items())[:5]:
        beliefs[identity] = {key: belief[key] for key in (
            "position", "capacity", "estimated_occupancy", "resource_score", "risk",
            "existence_probability", "confidence", "unavailable", "source", "evidence_type")
            if key in belief}
    social_beliefs = {}
    for identity, belief in list(observation.get("social_beliefs", {}).items())[:4]:
        social_beliefs[identity] = {key: (value[:120] if isinstance(value, str) else value)
                                    for key, value in belief.items()
                                    if key in ("claimed_value", "source", "confidence", "evidence", "status")}
    family_locations = {}
    for identity, location in list(observation.get("known_family_locations", {}).items())[:4]:
        family_locations[identity] = {key: (value[:100] if isinstance(value, str) else value)
                                      for key, value in location.items()
                                      if key in ("position", "source", "timestamp", "confidence")}
    phone_messages = []
    for item in observation.get("received_phone_messages", [])[-2:]:
        content = item.get("content", {})
        phone_messages.append({"sender": item.get("sender", ""), "channel": item.get("channel", ""),
                               "content": {key: (value[:120] if isinstance(value, str) else value)
                                           for key, value in content.items()
                                           if key in ("subject", "value", "message", "alert_id")}})
    return {
        "profile": {key: profile[key] for key in profile_keys if key in profile},
        "position": observation.get("position"),
        "perceptions": observation.get("perceptions", [])[:12],
        "experience": observation.get("experience", [])[-8:],
        "cognitive_traits": observation.get("cognitive_traits", {}),
        "excluded_shelters": observation.get("excluded_shelters", []),
        "requires_verified_shelter": observation.get("requires_verified_shelter", False),
        "goal": observation.get("goal", ""),
        "destination": observation.get("destination", ""),
        "simulation_time": observation.get("simulation_time", 0),
        "estimated_time_remaining": observation.get("estimated_time_remaining", 0),
        "beliefs": beliefs,
        "memories": [{"time": m.get("time"), "text": str(m.get("text", ""))[:180]}
                     for m in observation.get("memories", [])[-3:]],
        "messages": [{"claim": str(m.get("claim", ""))[:160],
                      "source": m.get("original_source", "unknown"),
                      "kind": m.get("kind", "unknown"),
                      "credibility": m.get("perceived_credibility")}
                     for m in observation.get("messages", [])[-3:]],
        "nearby_agents": [{key: agent[key] for key in ("id", "role", "position", "state") if key in agent}
                          for agent in observation.get("nearby_agents", [])[:4]],
        "family_relationships": {key: (value[:80] if isinstance(value, str) else value)
                                 for key, value in list(observation.get("family_relationships", {}).items())[:8]},
        "known_family_locations": family_locations,
        "social_beliefs": social_beliefs,
        "received_phone_messages": phone_messages,
        "trust_relationships": dict(list(observation.get("trust_relationships", {}).items())[:8]),
    }


class LangGraphDecisionWorkflow:
    """Run bounded asynchronous decisions on an ephemeral, agent-private graph state."""

    def __init__(self, model_factory: Callable[[Any], Any] | None = None,
                 event_sink: Callable[..., Any] | None = None,
                 shelter_model_factory: Callable[[Any], Any] | None = None):
        self.model_factory = model_factory or create_langchain_model
        self.event_sink = event_sink
        self.models: dict[int, Any] = {}
        self.model_providers: dict[int, Any] = {}
        self.shelter_model_factory = shelter_model_factory or create_langchain_shelter_model
        self.shelter_models: dict[int, Any] = {}
        self.graph = self._build_graph()
        self.shelter_graph = self._build_shelter_graph()

    async def _emit(self, topic: str, event_type: str, payload: dict, state: CognitiveState) -> None:
        if self.event_sink:
            await self.event_sink(topic, event_type, payload, state)

    def _build_graph(self):
        graph = StateGraph(CognitiveState)
        graph.add_node("observe", self.observe)
        graph.add_node("retrieve_memory", self.retrieve_memory)
        graph.add_node("update_beliefs", self.update_beliefs)
        graph.add_node("evaluate_needs", self.evaluate_needs)
        graph.add_node("context_router", self.context_router)
        for branch in ("emergency", "accident", "family", "phone", "authority", "shelter", "missing_information", "general"):
            async def enter_branch(state, selected=branch):
                return await self.branch_node(state, selected)
            graph.add_node(branch, enter_branch)
            graph.add_edge(branch, "plan")
        graph.add_node("plan", self.plan)
        graph.add_node("select_action", self.select_action)
        graph.add_node("validate_action", self.validate_action)
        graph.add_node("commit_decision", self.commit_decision)
        graph.add_edge(START, "observe")
        graph.add_edge("observe", "retrieve_memory")
        graph.add_edge("retrieve_memory", "update_beliefs")
        graph.add_edge("update_beliefs", "evaluate_needs")
        graph.add_edge("evaluate_needs", "context_router")
        graph.add_conditional_edges("context_router", self.select_branch, {
            key: key for key in ("emergency", "accident", "family", "phone", "authority", "shelter", "missing_information", "general")
        })
        graph.add_edge("plan", "select_action")
        graph.add_edge("select_action", "validate_action")
        graph.add_edge("validate_action", "commit_decision")
        graph.add_edge("commit_decision", END)
        return graph.compile()

    def _build_shelter_graph(self):
        graph = StateGraph(ShelterState)
        graph.add_node("assess_needs_and_constraints", self.assess_shelter_context)
        graph.add_node("choose_shelter_response", self.plan_shelter_response)
        graph.add_node("validate_shelter_choice", self.validate_shelter_choice)
        graph.add_node("commit_shelter_choice", self.commit_shelter_choice)
        graph.add_edge(START, "assess_needs_and_constraints")
        graph.add_edge("assess_needs_and_constraints", "choose_shelter_response")
        graph.add_edge("choose_shelter_response", "validate_shelter_choice")
        graph.add_edge("validate_shelter_choice", "commit_shelter_choice")
        graph.add_edge("commit_shelter_choice", END)
        return graph.compile()

    @staticmethod
    def _shelter_stage(state: ShelterState, name: str) -> list[str]:
        return [*state.get("graph_stages", []), name]

    async def assess_shelter_context(self, state: ShelterState) -> dict:
        if not state.get("allowed_actions") or len(state["allowed_actions"]) > 12:
            raise InvalidDecisionResponse("Shelter choice has no bounded action menu")
        context = json.dumps(state.get("context", {}), ensure_ascii=False, allow_nan=False)
        if len(context) > 2400:
            raise InvalidDecisionResponse("Shelter context exceeds the private prompt budget")
        return {"graph_stages": self._shelter_stage(state, "assess_needs_and_constraints")}

    async def plan_shelter_response(self, state: ShelterState) -> dict:
        key = state["provider_key"]
        model = self.shelter_models[key]
        prompt = ChatPromptTemplate.from_messages([
            ("system", "You are {agent_id}, an ESSAIM survivor inside a shelter. Make one short, practical choice "
             "for the current family, resource, equipment, or emergency decision. Use only the personal profile "
             "and context provided. Do not invent skills, supplies, relationships, injuries, or room access. "
             "Choose one allowed action. Godot remains authoritative and will validate the choice."),
            ("human", "Private decision context (JSON):\n{context}\nAllowed actions: {allowed_actions}\nAllowed targets: {allowed_targets}"),
        ])
        value = prompt.format_prompt(agent_id=state["agent_id"],
            context=json.dumps({"profile": state.get("profile", {}), "event": state.get("context", {})},
                               ensure_ascii=False, separators=(",", ":")),
            allowed_actions=", ".join(state["allowed_actions"]),
            allowed_targets=", ".join(state.get("allowed_targets", [])) or "none")
        response = await model.ainvoke(value)
        usage = (0, 0)
        if isinstance(response, dict) and "parsed" in response:
            raw = response.get("raw")
            metadata = getattr(raw, "usage_metadata", None) or {}
            fallback = getattr(raw, "response_metadata", None) or {}
            usage = (int(metadata.get("input_tokens", fallback.get("prompt_eval_count", 0)) or 0),
                     int(metadata.get("output_tokens", fallback.get("eval_count", 0)) or 0))
            response = response.get("parsed")
        if isinstance(response, BaseModel):
            choice = ShelterChoice.model_validate(response).model_dump()
        else:
            choice = ShelterChoice.model_validate(response).model_dump()
        return {"pending_choice": choice, "usage": usage,
                "graph_stages": self._shelter_stage(state, "choose_shelter_response")}

    async def validate_shelter_choice(self, state: ShelterState) -> dict:
        choice = ShelterChoice.model_validate(state["pending_choice"]).model_dump()
        if choice["action"] not in state["allowed_actions"]:
            raise InvalidDecisionResponse("Shelter action is outside the allowed menu")
        targets = state.get("allowed_targets", [])
        if choice["target"] and targets and choice["target"] not in targets:
            raise InvalidDecisionResponse("Shelter target is outside the allowed targets")
        return {"pending_choice": choice, "graph_stages": self._shelter_stage(state, "validate_shelter_choice")}

    async def commit_shelter_choice(self, state: ShelterState) -> dict:
        return {"committed_choice": ShelterChoice.model_validate(state["pending_choice"]).model_dump(),
                "graph_stages": self._shelter_stage(state, "commit_shelter_choice")}

    @staticmethod
    def _stage(state: CognitiveState, name: str) -> list[str]:
        return [*state.get("graph_stages", []), name]

    async def observe(self, state: CognitiveState) -> dict:
        obs = state["observation"]
        readers, action_tools, available = build_cognitive_tools(obs)
        results = {}
        for key, tool in readers.items():
            raw = await tool.ainvoke({"query": key})
            try:
                results[key] = json.loads(raw).get("result", {})
            except (TypeError, ValueError):
                results[key] = {}
        # Agent cognition is an explicit private projection; no world singleton,
        # Director state, or data from another actor is reachable from these tools.
        return {"visible_facts": results, "runtime_tools": action_tools,
                "available_tools": available, "graph_stages": self._stage(state, "observe")}

    async def retrieve_memory(self, state: CognitiveState) -> dict:
        obs = state["observation"]
        memory_terms = [str(item.get("text", ""))[:180]
                        for item in [*obs.get("memories", [])[-2:], *state.get("own_memory", [])[-2:]]]
        query = " ".join([obs.get("goal", ""), obs.get("destination", ""),
                           state.get("branch", ""), "shelter emergency family road safety known city map",
                           *memory_terms])
        docs = retrieve_private_context(obs, state.get("own_memory", []), query)
        context = []
        provenance = []
        for doc in docs:
            meta = doc.metadata
            content = doc.page_content[:220]
            source = {key: meta[key] for key in ("source_id", "source_kind", "source", "confidence", "evidence", "timestamp") if key in meta}
            context.append({"text": content, "source": source})
            provenance.append(source)
        return {"retrieved_context": context, "retrieval_provenance": provenance,
                "graph_stages": self._stage(state, "retrieve_relevant_memory")}

    async def update_beliefs(self, state: CognitiveState) -> dict:
        obs = state["observation"]
        # Retrieval can attach source references but never silently promotes a
        # rumor or invents a new shelter/road fact.
        provenance = state.get("retrieval_provenance", [])
        evidence = {}
        for item in state.get("retrieved_context", []):
            source = item.get("source", {})
            if source.get("source_kind") not in ("local_city_map", "shelter_belief", "road_condition", "social_belief", "family_memory", "social_report"):
                continue
            identity = source.get("source_id", "")
            if identity:
                evidence[identity] = dict(claim=item.get("text", ""), source=source.get("source", "unknown"),
                    confidence=source.get("confidence"), evidence=source.get("evidence", "unknown"),
                    status="RETRIEVED_UNVERIFIED")
        updates = {"retained_belief_count": len(obs.get("beliefs", {})),
                   "retrieved_source_ids": [item.get("source_id", "") for item in provenance],
                   "new_evidence_count": len(evidence),
                   "unverified_report_count": sum(1 for message in obs.get("messages", [])
                       if message.get("kind", "rumor") != "observation")}
        result = {"beliefs": dict(state.get("beliefs", {}), **{"retrieved_evidence": evidence}),
                  "belief_updates": updates,
                  "graph_stages": self._stage(state, "update_beliefs")}
        await self._emit("world.events", "agent.belief_updated", updates, state)
        return result

    async def evaluate_needs(self, state: CognitiveState) -> dict:
        profile = state["observation"]["profile"]
        known_local = list(state["observation"].get("social_beliefs", {}).items())
        risky_shelter = any(_number(item.get("risk"), 0) >= 0.7 for item in state["observation"].get("beliefs", {}).values())
        incident_known = (any(key.startswith(("accident:", "vehicle:")) for key, _ in known_local) or
                          any(item.get("kind") == "accident" for item in state["observation"].get("perceptions", [])))
        local_emergency = any(item.get("kind") in ("fire", "explosion", "smoke") and
                              _number(item.get("severity"), 0) >= .4
                              for item in state["observation"].get("perceptions", []))
        needs = {
            "safety": profile.get("safety", max(0.0, 1.0 - _number(profile.get("panic_level"), 0) / 100.0)),
            "fatigue": profile.get("fatigue", 0),
            "stress": profile.get("stress", profile.get("panic_level", 0)),
            "family_concern": profile.get("family_concern", 0),
            "health": profile.get("health", 1),
            "social_attachment": profile.get("social_attachment", 0),
            "known_incident": incident_known,
            "perceived_emergency": risky_shelter or incident_known or local_emergency or _number(profile.get("panic_level"), 0) >= 85,
        }
        return {"needs": needs, "graph_stages": self._stage(state, "evaluate_needs")}

    async def context_router(self, state: CognitiveState) -> dict:
        return {"graph_stages": self._stage(state, "route_context")}

    @staticmethod
    def select_branch(state: CognitiveState) -> str:
        obs = state["observation"]
        if state.get("needs", {}).get("known_incident"):
            return "accident"
        if state.get("needs", {}).get("perceived_emergency"):
            return "emergency"
        if obs.get("received_phone_messages"):
            return "phone"
        if (_number(obs["profile"].get("family_concern"), 0) > 0.5 or
                obs.get("known_family_locations")):
            return "family"
        if obs["profile"].get("role") == "Authority" and any(
                key.startswith(("order:", "authority:")) for key in obs.get("social_beliefs", {})):
            return "authority"
        if obs.get("beliefs"):
            return "shelter"
        if not obs.get("beliefs") and not obs.get("nearby_agents"):
            return "missing_information"
        return "general"

    async def branch_node(self, state: CognitiveState, selected: str) -> dict:
        guidance = {
            "emergency": "Prioritize immediate safety from hazards the agent actually knows.",
            "accident": "Use only known incident reports; avoid asserting unobserved road or casualty facts.",
            "family": "Contact or reunite only with configured family contacts using known information.",
            "phone": "Treat received messages as sourced reports with uncertainty.",
            "authority": "Check role authorization and preserve emergency access before an order.",
            "shelter": "Compare only this agent's shelter beliefs; Godot handles route and admission.",
            "missing_information": "Ask to observe or wait; do not invent locations or world state.",
            "general": "Choose one action consistent with current local evidence and needs.",
        }
        return {"branch_guidance": guidance.get(selected, guidance["general"]),
                "graph_stages": self._stage(state, selected)}

    async def plan(self, state: CognitiveState) -> dict:
        return {"graph_stages": self._stage(state, "plan")}

    def _structured_prompt(self, state: CognitiveState):
        obs = state["observation"]
        reads = state.get("visible_facts", {})
        raw_roads = reads.get("inspect_known_road_status", {})
        raw_feed = reads.get("read_social_feed", {})
        raw_environment = reads.get("observe_nearby_environment", {})
        local_reads = {
            "nearby_agent_ids": [agent.get("id", "") for agent in raw_environment.get("nearby_agents", [])[:4]],
            "known_roads": {key: {field: value.get(field) for field in ("claimed_value", "source", "confidence", "evidence") if field in value}
                            for key, value in list(raw_roads.items())[:4] if isinstance(value, dict)},
            "delivered_reports": [{"claim": str(item.get("claim", ""))[:160],
                                   "source": item.get("original_source", "unknown"),
                                   "kind": item.get("kind", "unknown")}
                                  for item in raw_feed.get("messages", [])[:2]],
        }
        context = {
            "private_observation": _compact_observation(obs),
            "needs": state.get("needs", {}),
            "relevant_memory_and_knowledge": [dict(text=item.get("text", "")[:160], source={
                key: (value[:100] if isinstance(value, str) else value)
                for key, value in item.get("source", {}).items()
                if key in ("source_id", "source_kind", "source", "confidence", "evidence")})
                for item in state.get("retrieved_context", [])[:5]],
            "belief_update_provenance": state.get("belief_updates", {}),
            "local_reads": local_reads,
            "priority": state.get("branch_guidance", ""),
            "available_tools": state.get("available_tools", []),
        }
        encoded = json.dumps(context, ensure_ascii=False, separators=(",", ":"), allow_nan=False)
        # RAG documents are useful context, but do not let them grow an unbounded
        # prompt or turn into a copy of the simulation world.
        while len(encoded) > 4300 and context["relevant_memory_and_knowledge"]:
            context["relevant_memory_and_knowledge"].pop(0)
            encoded = json.dumps(context, ensure_ascii=False, separators=(",", ":"), allow_nan=False)
        if len(encoded) > 4500:
            raise ValueError("Private cognitive prompt exceeds the configured budget")
        profile = obs["profile"]
        prompt = ChatPromptTemplate.from_messages([
            ("system", "You are {agent_id}, a {role} in ESSAIM. Respect this agent's personality and known evidence. "
             "Only use the private observation, retrieved memories with provenance, and public emergency procedures below. "
             "Never infer the true world state from missing information. Rumors are uncertain reports, not facts. "
             "Choose exactly one existing Godot action from: {actions}. "
             "Authority actions are role restricted, and all actions are permission checked before commit. "
             "To request emergency assistance, choose COMMUNICATE to a nearby observed Authority and prefix the message "
             "with 'Emergency assistance requested:'. This sends a report; it does not dispatch units itself. "
             "The available tool list is permission filtered. Godot remains authoritative for physical movement, routes, shelter "
             "admission, dispatch, and world changes. Simulated IQ is not morality, authority, personality, or survival. "
             "Return only the structured decision, with a short reason."),
            ("human", "Private run-local context (JSON):\n{context}"),
        ])
        value = prompt.format_prompt(agent_id=profile["id"], role=profile["role"],
                                     actions=", ".join(ACTIONS), context=encoded)
        return value, value.to_string()

    async def select_action(self, state: CognitiveState) -> dict:
        model = self.models[state["provider_key"]]
        messages, rendered = self._structured_prompt(state)
        try:
            response = await model.ainvoke(messages)
        except OutputParserException as error:
            raise InvalidDecisionResponse("Provider could not produce the structured decision") from error
        usage = (0, 0)
        raw = None
        parsed = response
        if isinstance(response, dict) and "parsed" in response:
            parsed, raw = response.get("parsed"), response.get("raw")
        if parsed is None:
            raise InvalidDecisionResponse("LangChain did not return a structured decision")
        try:
            if isinstance(parsed, BaseModel):
                candidate = Decision.model_validate(parsed).model_dump()
            else:
                candidate = Decision.model_validate(parsed).model_dump()
        except (ValueError, TypeError) as error:
            raise InvalidDecisionResponse("Structured decision did not match the simulation schema") from error
        if raw is not None:
            usage_metadata = getattr(raw, "usage_metadata", None) or {}
            response_metadata = getattr(raw, "response_metadata", None) or {}
            usage = (int(usage_metadata.get("input_tokens", response_metadata.get("prompt_eval_count", 0)) or 0),
                     int(usage_metadata.get("output_tokens", response_metadata.get("eval_count", 0)) or 0))
        payload = {"decision": candidate, "usage": usage,
                   "raw_answer": str(getattr(raw, "content", ""))[:6000] if raw is not None else "",
                   "prompt": rendered}
        return {"provider_result": payload, "pending_decision": candidate,
                "prompt": rendered, "graph_stages": self._stage(state, "select_action")}

    async def validate_action(self, state: CognitiveState) -> dict:
        candidate = Decision.model_validate(state["pending_decision"]).model_dump()
        tools = state["runtime_tools"]
        action = candidate["action"]
        if action == "COMMUNICATE" and candidate["message"].lower().startswith("emergency assistance requested:"):
            tool = tools.get("REQUEST_EMERGENCY_ASSISTANCE")
            if tool is None:
                raise ValueError("No nearby authority can receive an emergency request")
            args = dict(target=candidate["target"], message=candidate["message"].split(":", 1)[-1].strip(),
                        reason=candidate["reason"], confidence=candidate["confidence"])
        else:
            tool = tool_for_decision(action, tools)
            args = {key: candidate[key] for key in ("target", "message", "reason", "confidence")}
        try:
            validated = await tool.ainvoke(args)
            validated = Decision.model_validate(validated).model_dump()
            # The canonical validator is run once more against the latest request
            # observation at the runtime boundary before commit.
            validated = decision(json.dumps(validated), state["observation"])
        except (ValueError, TypeError) as error:
            raise InvalidDecisionResponse("Selected action failed permission or observation checks") from error
        return {"pending_decision": validated, "graph_stages": self._stage(state, "validate_action")}

    async def commit_decision(self, state: CognitiveState) -> dict:
        result = Decision.model_validate(state["pending_decision"]).model_dump()
        action = result["action"]
        if action in ("COMMUNICATE", "CALL", "TEXT", "POST"):
            await self._emit("agent.communications", "agent.communication", result, state)
        if action in ("CREATE_ROADBLOCK", "REMOVE_ROADBLOCK", "ISSUE_ALERT"):
            await self._emit("world.events", "authority.order_issued", result, state)
        if action in ("MOVE_TO_SHELTER", "DRIVE_TO_SHELTER"):
            await self._emit("shelter.events", "agent.shelter_intent", result, state)
        return {"committed_decision": result,
                "graph_stages": self._stage(state, "commit_decision")}

    async def ainvoke(self, provider, *, run_id: str, request_id: str,
                      observation: dict, own_memory: list[dict]) -> dict:
        key = str(id(provider))
        if key not in self.models:
            model = self.model_factory(provider)
            if hasattr(model, "__await__"):
                model = await model
            self.models[key] = model
            self.model_providers[key] = provider
        profile = observation["profile"]
        state: CognitiveState = {
            "run_id": run_id, "request_id": request_id, "agent_id": profile["id"],
            "provider_key": key, "observation": observation,
            "own_memory": own_memory, "role": profile["role"],
            "personality": {key: profile.get(key) for key in ("primary_personality", "secondary_personality")},
            "simulated_iq": profile.get("iq"), "beliefs": observation.get("beliefs", {}),
            "current_goals": [observation.get("goal", "")],
            "family_relationships": observation.get("family_relationships", {}),
            "graph_stages": [],
        }
        result = await self.graph.ainvoke(state)
        return {"decision": result["committed_decision"],
                "usage": result.get("provider_result", {}).get("usage", (0, 0)),
                "prompt": result.get("prompt", ""),
                "raw_answer": result.get("provider_result", {}).get("raw_answer", ""),
                "retrieval_provenance": result.get("retrieval_provenance", []),
                "stages": result.get("graph_stages", []),
                "agent_id": profile["id"], "run_id": run_id, "request_id": request_id}

    async def ainvoke_shelter(self, provider, *, run_id: str, request_id: str,
                              profile: dict, context: dict, allowed_actions: list[str],
                              allowed_targets: list[str] | None = None) -> dict:
        """Run the small shelter-choice graph only when a complex event requests it."""
        key = str(id(provider))
        if key not in self.shelter_models:
            model = self.shelter_model_factory(provider)
            if hasattr(model, "__await__"):
                model = await model
            self.shelter_models[key] = model
        state: ShelterState = {
            "run_id": run_id, "request_id": request_id, "agent_id": str(profile.get("id", "")),
            "provider_key": key, "profile": profile, "context": context,
            "allowed_actions": allowed_actions, "allowed_targets": allowed_targets or [],
            "graph_stages": [],
        }
        result = await self.shelter_graph.ainvoke(state)
        return {"decision": result["committed_choice"], "stages": result.get("graph_stages", []),
                "usage": result.get("usage", (0, 0)),
                "agent_id": state["agent_id"], "run_id": run_id, "request_id": request_id}

    async def aclose(self) -> None:
        seen = set()
        for model in [*self.models.values(), *self.shelter_models.values()]:
            pending = [model]
            visited = set()
            while pending:
                target = pending.pop()
                if target is None or id(target) in visited:
                    continue
                visited.add(id(target))
                closer = getattr(target, "aclose", None)
                if closer and id(target) not in seen:
                    seen.add(id(target))
                    try:
                        result = closer()
                        if hasattr(result, "__await__"):
                            await result
                    except Exception:
                        pass
                for attribute in ("bound", "steps", "runnable", "first", "last"):
                    child = getattr(target, attribute, None)
                    pending.extend(child if isinstance(child, (list, tuple)) else [child])

    async def reset_models(self) -> None:
        await self.aclose()
        self.models.clear()
        self.model_providers.clear()
        self.shelter_models.clear()
