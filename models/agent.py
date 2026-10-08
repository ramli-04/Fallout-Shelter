"""Heterogeneous agents, their private memory, and public-map beliefs."""

from dataclasses import dataclass, field
from random import Random

from config.settings import AgentSettings, ShelterSpec


@dataclass
class ShelterBelief:
    shelter_id: str
    position_m: tuple[float, float]
    capacity: int
    existence_probability: float
    reported_supplies_person_days: float | None
    confidence: float
    unavailable: bool = False
    source: str = "public map"


@dataclass(frozen=True)
class Decision:
    time_seconds: float
    shelter_id: str | None
    reason: str


@dataclass
class Agent:
    id: int
    role: str
    position_m: tuple[float, float]
    speed_m_per_second: float
    personality: str
    risk_tolerance: float
    trust_in_authorities: float
    sociability: float
    crowd_following: float
    communication_capable: bool
    health: float
    beliefs: dict[str, ShelterBelief]
    memory: list[str] = field(default_factory=list)
    objective: str | None = None
    decision_history: list[Decision] = field(default_factory=list)
    shelter_id: str | None = None
    status: str = "moving"
    death_cause: str | None = None

    @property
    def alive(self) -> bool:
        return self.status != "dead"


def create_agents(count: int, settings: AgentSettings, specs: tuple[ShelterSpec, ...],
                  rng: Random) -> list[Agent]:
    agents = []
    for agent_id in range(count):
        # Only published information is copied. No Shelter runtime state enters here.
        beliefs = {
            spec.id: ShelterBelief(
                spec.id, spec.position_m, spec.capacity,
                spec.public_existence_probability, spec.reported_supplies_person_days,
                settings.initial_belief_confidence,
            )
            for spec in specs
        }
        agents.append(Agent(
            id=agent_id,
            role="authority" if rng.random() < settings.authority_fraction else "civilian",
            position_m=(rng.uniform(*settings.spawn_x_m), rng.uniform(*settings.spawn_y_m)),
            speed_m_per_second=rng.uniform(*settings.speed_m_per_second),
            personality=rng.choice(settings.personalities),
            risk_tolerance=rng.uniform(*settings.risk_tolerance),
            trust_in_authorities=rng.uniform(*settings.trust_in_authorities),
            sociability=rng.uniform(*settings.sociability),
            crowd_following=rng.uniform(*settings.crowd_following),
            communication_capable=rng.random() < settings.communication_probability,
            health=settings.initial_health,
            beliefs=beliefs,
        ))
    return agents
