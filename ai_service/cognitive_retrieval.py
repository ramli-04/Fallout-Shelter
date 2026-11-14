"""Permission-scoped local RAG over facts an agent already knows."""
from __future__ import annotations

import re
from typing import Iterable

from langchain_core.documents import Document
from langchain_core.retrievers import BaseRetriever
from pydantic import ConfigDict, Field


_WORD = re.compile(r"[a-z0-9_:-]+", re.IGNORECASE)


class PrivateKnowledgeRetriever(BaseRetriever):
    """Small lexical retriever; documents are pre-filtered to one private agent."""

    model_config = ConfigDict(arbitrary_types_allowed=True)
    documents: list[Document] = Field(default_factory=list)
    agent_id: str
    role: str
    k: int = 6

    def _authorized(self, document: Document) -> bool:
        metadata = document.metadata
        visibility = metadata.get("visibility", "private")
        if visibility == "public":
            return True
        if metadata.get("owner_id") == self.agent_id:
            return True
        return visibility == "role" and metadata.get("role") == self.role

    def _get_relevant_documents(self, query: str, *, run_manager) -> list[Document]:
        terms = set(_WORD.findall(query.lower()))
        scored: list[tuple[int, int, Document]] = []
        for index, document in enumerate(self.documents):
            if not self._authorized(document):
                continue
            content = document.page_content.lower()
            doc_terms = set(_WORD.findall(content))
            score = len(terms & doc_terms)
            if score:
                scored.append((score, -index, document))
        scored.sort(reverse=True, key=lambda item: (item[0], item[1]))
        return [document for _, _, document in scored[: self.k]]


def private_documents(observation: dict, own_memory: Iterable[dict]) -> list[Document]:
    """Build sources solely from this agent's allowlisted observation and memory."""
    profile = observation["profile"]
    agent_id = profile["id"]
    role = profile["role"]
    docs = [
        Document(
            page_content=(
                "Emergency procedure: treat direct observation and official warnings as stronger "
                "evidence than rumors. Reassess known shelter capacity and risk from the agent's "
                "own beliefs. Choose a route through Godot navigation; never claim a path or fact "
                "that is absent from this agent's observation."
            ),
            metadata={"source_id": "procedure:public-emergency", "source_kind": "procedure", "visibility": "public"},
        ),
        Document(
            page_content=(
                "Shelter guidance: shelter locations, capacity, occupancy, and danger are uncertain "
                "unless this agent has direct evidence. Keep each source and confidence attached. "
                "Physical shelter admission is decided by the simulation."
            ),
            metadata={"source_id": "procedure:shelter", "source_kind": "procedure", "visibility": "public"},
        ),
    ]
    role_text = (
        "Authority procedure: share only sourced reports with uncertainty, preserve emergency "
        "access, and issue orders only within the authority role."
        if role == "Authority"
        else "Civilian guidance: make independent safety choices; family locations are known only "
        "when personally observed, messaged, or remembered."
    )
    docs.append(Document(page_content=role_text, metadata={
        "source_id": f"procedure:role:{role.lower()}", "source_kind": "role_knowledge",
        "visibility": "role", "role": role,
    }))

    local_map = {
        "own_position": observation.get("position"),
        "known_shelter_positions": {identity: belief.get("position")
                                    for identity, belief in observation.get("beliefs", {}).items()
                                    if belief.get("position") is not None},
        "visible_agent_positions": [{"id": agent.get("id"), "position": agent.get("position")}
                                    for agent in observation.get("nearby_agents", [])[:20]],
        "known_road_conditions": {identity: {key: belief.get(key) for key in
                                   ("claimed_value", "source", "confidence", "evidence") if key in belief}
                                  for identity, belief in observation.get("social_beliefs", {}).items()
                                  if identity.startswith(("road:", "traffic:"))},
    }
    docs.append(Document(page_content=f"Known local city map from this agent's observation: {local_map}", metadata={
        "source_id": f"map_view:{agent_id}:{observation.get('simulation_time', 0)}",
        "source_kind": "local_city_map", "visibility": "private", "owner_id": agent_id,
    }))

    for item in list(own_memory)[-12:]:
        text = item.get("text", "")
        if text:
            docs.append(Document(page_content=str(text)[:800], metadata={
                "source_id": f"memory:{agent_id}:{item.get('time', 'unknown')}",
                "source_kind": "personal_memory", "visibility": "private", "owner_id": agent_id,
                "timestamp": item.get("time"),
            }))
    for index, item in enumerate(observation.get("memories", [])[-12:]):
        text = item.get("text", "")
        if text:
            docs.append(Document(page_content=str(text)[:800], metadata={
                "source_id": f"observation_memory:{agent_id}:{index}",
                "source_kind": "personal_memory", "visibility": "private", "owner_id": agent_id,
                "timestamp": item.get("time"),
            }))
    for shelter_id, belief in observation.get("beliefs", {}).items():
        summary = ", ".join(f"{key}={value}" for key, value in belief.items())
        docs.append(Document(page_content=f"Known shelter belief {shelter_id}: {summary}", metadata={
            "source_id": f"belief:shelter:{agent_id}:{shelter_id}", "source_kind": "shelter_belief",
            "visibility": "private", "owner_id": agent_id,
            "source": belief.get("source", "unknown"), "confidence": belief.get("confidence"),
        }))
    for subject, belief in observation.get("social_beliefs", {}).items():
        summary = ", ".join(f"{key}={value}" for key, value in belief.items())
        source_kind = "road_condition" if subject.startswith(("road:", "traffic:")) else "social_belief"
        docs.append(Document(page_content=f"Known local fact {subject}: {summary}", metadata={
            "source_id": f"belief:social:{agent_id}:{subject}", "source_kind": source_kind,
            "visibility": "private", "owner_id": agent_id,
            "source": belief.get("source", "unknown"), "confidence": belief.get("confidence"),
            "evidence": belief.get("evidence", "unknown"),
        }))
    for identity, location in observation.get("known_family_locations", {}).items():
        docs.append(Document(page_content=f"Remembered family location {identity}: {location}", metadata={
            "source_id": f"family_location:{agent_id}:{identity}", "source_kind": "family_memory",
            "visibility": "private", "owner_id": agent_id,
            "source": location.get("source", "unknown"), "confidence": location.get("confidence"),
        }))
    for index, message in enumerate(observation.get("messages", [])):
        claim = message.get("claim", "")
        if claim:
            docs.append(Document(page_content=f"Social report: {claim}", metadata={
                "source_id": f"message:{agent_id}:{message.get('rumor_id', index)}",
                "source_kind": "social_report", "visibility": "private", "owner_id": agent_id,
                "source": message.get("original_source", "unknown"),
                "confidence": message.get("perceived_credibility"), "evidence": message.get("kind", "unknown"),
            }))
    return docs


def retrieve_private_context(observation: dict, own_memory: list[dict], query: str) -> list[Document]:
    docs = private_documents(observation, own_memory)
    retriever = PrivateKnowledgeRetriever(documents=docs, agent_id=observation["profile"]["id"],
                                         role=observation["profile"]["role"], k=6)
    return retriever.invoke(query)
