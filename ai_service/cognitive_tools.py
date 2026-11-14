"""LangChain tools bound to a single agent's authorized observation."""
from __future__ import annotations

import json
from langchain_core.tools import StructuredTool
from pydantic import BaseModel, ConfigDict, Field

from .contracts import ACTIONS, decision


class DecisionToolInput(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    target: str = Field(default="", max_length=64)
    message: str = Field(default="", max_length=160)
    reason: str = Field(default="", max_length=240)
    confidence: float = Field(default=0.5, ge=0, le=1)


class ReadToolInput(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    query: str = Field(default="", max_length=160)


_ACTION_TO_TOOL = {
    "MOVE_TO_SHELTER": ("choose_shelter", "Choose a shelter ID this agent knows; Godot computes its route."),
    "WAIT": ("wait_briefly", "Pause briefly while this agent reassesses its own evidence."),
    "OBSERVE": ("observe_nearby_environment", "Use only people and shelter facts in this agent's current observation."),
    "COMMUNICATE": ("send_message", "Send a short message to nearby observed people."),
    "DANCE": ("choose_nonurgent_action", "Choose a brief low-priority action."),
    "FLEE_RANDOMLY": ("choose_nonurgent_action", "Choose a short panic movement; Godot controls movement."),
    "HELP_AGENT": ("help_nearby_agent", "Help an observed nearby agent."),
    "FOLLOW_AGENT": ("follow_nearby_agent", "Follow an observed nearby agent."),
    "CALL": ("call_family_member", "Call a configured family contact."),
    "TEXT": ("text_family_member", "Text a configured family contact."),
    "POST": ("share_information", "Share an uncertain claim as a social report."),
    "FIND_FAMILY": ("request_family_reunion", "Try to reunite with a configured family contact."),
    "DRIVE_TO_SHELTER": ("request_navigation_route", "Ask Godot to route this agent's vehicle to a known shelter."),
    "CREATE_ROADBLOCK": ("create_roadblock", "Request a roadblock; authority and world safety checks remain in Godot."),
    "REMOVE_ROADBLOCK": ("remove_roadblock", "Request roadblock removal; authority and world checks remain in Godot."),
    "ISSUE_ALERT": ("issue_authority_order", "Issue an authority alert through the existing validated simulation action."),
}


def _known_roads(observation: dict) -> dict:
    return {key: value for key, value in observation.get("social_beliefs", {}).items()
            if key.startswith(("road:", "traffic:"))}


def build_cognitive_tools(observation: dict) -> tuple[dict[str, StructuredTool], dict[str, StructuredTool], list[str]]:
    """Return read tools, action tools, and the names visible to this agent."""
    profile = observation["profile"]
    agent_id = profile["id"]

    def read_tool(name: str, description: str, fetch):
        def run(query: str = "") -> str:
            result = fetch()
            return json.dumps({"result": result, "agent_id": agent_id, "query": query},
                              ensure_ascii=False, separators=(",", ":"))[:3000]
        return StructuredTool.from_function(name=name, description=description, func=run,
                                            args_schema=ReadToolInput)

    read_tools = {
        "observe_nearby_environment": read_tool(
            "observe_nearby_environment", "Read only the current agent's visible nearby agents and own position.",
            lambda: {"position": observation.get("position"), "nearby_agents": observation.get("nearby_agents", [])}),
        "inspect_known_road_status": read_tool(
            "inspect_known_road_status", "Inspect road closures and traffic claims this agent already knows.",
            lambda: _known_roads(observation)),
        "read_social_feed": read_tool(
            "read_social_feed", "Read only messages and social reports delivered to this agent.",
            lambda: {"messages": observation.get("messages", []),
                     "phone_messages": observation.get("received_phone_messages", [])}),
    }

    action_tools: dict[str, StructuredTool] = {}
    available = list(read_tools)
    known_family = observation.get("family_relationships", {})
    nearby = observation.get("nearby_agents", [])
    role = profile.get("role")
    has_phone = profile.get("has_phone", False) is True
    has_vehicle = bool(profile.get("vehicle_id"))

    for action, (name, description) in _ACTION_TO_TOOL.items():
        if action in ("CALL", "TEXT") and (not has_phone or not known_family):
            continue
        if action == "FIND_FAMILY" and not known_family:
            continue
        if action == "POST" and profile.get("social_user") is not True:
            continue
        if action == "DRIVE_TO_SHELTER" and not has_vehicle:
            continue
        if action in ("CREATE_ROADBLOCK", "REMOVE_ROADBLOCK", "ISSUE_ALERT") and role != "Authority":
            continue
        # A family contact tool needs a known relationship; roadblock/order tools
        # are limited to authorities. Other restrictions are rechecked on invocation.
        def invoke(target: str = "", message: str = "", reason: str = "", confidence: float = 0.5,
                   *, _action=action) -> dict:
            if _action in ("CALL", "TEXT") and not has_phone:
                raise ValueError("Phone tool requires a phone")
            if _action == "POST" and profile.get("social_user") is not True:
                raise ValueError("Social posting permission denied")
            if _action == "DRIVE_TO_SHELTER" and not has_vehicle:
                raise ValueError("Vehicle route requires an assigned vehicle")
            if _action in ("CALL", "TEXT", "FIND_FAMILY") and target not in known_family:
                raise ValueError("Family tool target is not a configured contact")
            if _action in ("MOVE_TO_SHELTER", "DRIVE_TO_SHELTER") and observation.get("beliefs", {}).get(target, {}).get("unavailable"):
                raise ValueError("Shelter is marked unavailable in this agent's beliefs")
            if _action in ("CREATE_ROADBLOCK", "REMOVE_ROADBLOCK", "ISSUE_ALERT") and role != "Authority":
                raise ValueError("Authority tool permission denied")
            candidate = dict(action=_action, target=target, message=message,
                             reason=reason, confidence=confidence)
            return decision(json.dumps(candidate), observation)

        action_tools[action] = StructuredTool.from_function(
            name=name, description=description, func=invoke, args_schema=DecisionToolInput)
        if name not in available:
            available.append(name)

    # Emergency assistance is a communication intent to an authority actually
    # present in the sender's perception. It never dispatches or teleports units.
    if any(agent.get("role") == "Authority" for agent in nearby):
        def request_help(target: str, message: str, reason: str = "Request assistance",
                         confidence: float = 0.8) -> dict:
            authorities = {agent["id"] for agent in nearby if agent.get("role") == "Authority"}
            if target not in authorities:
                raise ValueError("Emergency request recipient is not a nearby authority")
            body = ("Emergency assistance requested: " + message)[:160]
            return decision(json.dumps(dict(action="COMMUNICATE", target=target, message=body,
                                            reason=reason, confidence=confidence)), observation)
        action_tools["REQUEST_EMERGENCY_ASSISTANCE"] = StructuredTool.from_function(
            name="request_emergency_assistance",
            description="Ask a nearby observed authority for help; this sends a message only.",
            func=request_help)
        available.append("request_emergency_assistance")

    return read_tools, action_tools, available


def tool_for_decision(action: str, tools: dict[str, StructuredTool]) -> StructuredTool:
    if action not in ACTIONS:
        raise ValueError("Action is not in the Godot decision contract")
    if action in tools:
        return tools[action]
    raise ValueError("No authorized tool can commit this action")
