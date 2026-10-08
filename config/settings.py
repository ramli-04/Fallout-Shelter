"""Load JSON data and reject invalid modeling parameters before a run starts."""

from dataclasses import asdict, dataclass, fields, replace
import json
import math
from pathlib import Path
from typing import Any


class ConfigurationError(ValueError):
    """A readable error in a configuration file or command-line override."""


def number(value: Any, label: str, minimum: float | None = None,
           maximum: float | None = None) -> None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ConfigurationError(f"{label} must be a number")
    if not math.isfinite(value):
        raise ConfigurationError(f"{label} must be finite")
    if minimum is not None and value < minimum:
        raise ConfigurationError(f"{label} must be >= {minimum}")
    if maximum is not None and value > maximum:
        raise ConfigurationError(f"{label} must be <= {maximum}")


def integer(value: Any, label: str, minimum: int | None = None) -> None:
    number(value, label, minimum)
    if not isinstance(value, int):
        raise ConfigurationError(f"{label} must be an integer")


def pair(value: Any, label: str, minimum: float | None = None,
         maximum: float | None = None) -> None:
    if not isinstance(value, (list, tuple)) or len(value) != 2:
        raise ConfigurationError(f"{label} must contain two numbers")
    for item in value:
        number(item, label, minimum, maximum)
    if value[0] > value[1]:
        raise ConfigurationError(f"{label} minimum must not exceed maximum")


@dataclass(frozen=True)
class SimulationSettings:
    seed: int
    population: int
    countdown_min_seconds: int
    countdown_max_seconds: int
    tick_seconds: float
    arrival_radius_m: float

    def __post_init__(self) -> None:
        integer(self.seed, "seed")
        integer(self.population, "population", 1)
        integer(self.countdown_min_seconds, "countdown_min_seconds", 300)
        integer(self.countdown_max_seconds, "countdown_max_seconds", 300)
        if not self.countdown_min_seconds <= self.countdown_max_seconds <= 600:
            raise ConfigurationError("countdown bounds must satisfy 300 <= min <= max <= 600")
        number(self.tick_seconds, "tick_seconds", 0)
        if self.tick_seconds == 0:
            raise ConfigurationError("tick_seconds must be positive")
        number(self.arrival_radius_m, "arrival_radius_m", 0)


@dataclass(frozen=True)
class AgentSettings:
    spawn_x_m: tuple[float, float]
    spawn_y_m: tuple[float, float]
    speed_m_per_second: tuple[float, float]
    authority_fraction: float
    communication_probability: float
    risk_tolerance: tuple[float, float]
    trust_in_authorities: tuple[float, float]
    sociability: tuple[float, float]
    crowd_following: tuple[float, float]
    initial_health: float
    initial_belief_confidence: float
    personalities: tuple[str, ...]

    def __post_init__(self) -> None:
        for name in ("spawn_x_m", "spawn_y_m"):
            pair(getattr(self, name), name)
        pair(self.speed_m_per_second, "speed_m_per_second", 0)
        if self.speed_m_per_second[0] == 0:
            raise ConfigurationError("minimum speed must be positive")
        for name in ("risk_tolerance", "trust_in_authorities", "sociability", "crowd_following"):
            pair(getattr(self, name), name, 0, 1)
        for name in ("authority_fraction", "communication_probability", "initial_belief_confidence"):
            number(getattr(self, name), name, 0, 1)
        number(self.initial_health, "initial_health", 0, 100)
        if self.initial_health == 0:
            raise ConfigurationError("initial_health must be positive")
        if not isinstance(self.personalities, (list, tuple)) or not self.personalities:
            raise ConfigurationError("personalities must be a nonempty list of strings")
        if any(not isinstance(p, str) or not p.strip() for p in self.personalities):
            raise ConfigurationError("personalities must contain nonempty strings")


@dataclass(frozen=True)
class ShelterSpec:
    id: str
    capacity: int
    position_m: tuple[float, float]
    resources_label: str
    supplies_person_days: float | None
    supplies_range_person_days: tuple[float, float] | None
    reported_supplies_person_days: float | None
    distance_band: str
    feature: str
    maintenance_failure_probability: float
    existence_probability: float
    public_existence_probability: float

    def __post_init__(self) -> None:
        if not isinstance(self.id, str) or not self.id.strip():
            raise ConfigurationError("shelter id must be a nonempty string")
        integer(self.capacity, f"{self.id}.capacity", 1)
        # A position is a coordinate, not a minimum/maximum range.
        if not isinstance(self.position_m, (list, tuple)) or len(self.position_m) != 2:
            raise ConfigurationError(f"{self.id}.position_m needs two coordinates")
        for coordinate in self.position_m:
            number(coordinate, f"{self.id}.position_m")
        for name in ("resources_label", "distance_band", "feature"):
            if not isinstance(getattr(self, name), str) or not getattr(self, name).strip():
                raise ConfigurationError(f"{self.id}.{name} must be a nonempty string")
        if (self.supplies_person_days is None) == (self.supplies_range_person_days is None):
            raise ConfigurationError(f"{self.id}: specify either fixed supplies or a supplies range")
        if self.supplies_person_days is not None:
            number(self.supplies_person_days, f"{self.id}.supplies_person_days", 0)
        if self.supplies_range_person_days is not None:
            pair(self.supplies_range_person_days, f"{self.id}.supplies_range_person_days", 0)
        if self.reported_supplies_person_days is not None:
            number(self.reported_supplies_person_days, f"{self.id}.reported_supplies_person_days", 0)
        for name in ("maintenance_failure_probability", "existence_probability",
                     "public_existence_probability"):
            number(getattr(self, name), f"{self.id}.{name}", 0, 1)


@dataclass(frozen=True)
class Configuration:
    simulation: SimulationSettings
    agents: AgentSettings
    shelters: tuple[ShelterSpec, ...]

    def __post_init__(self) -> None:
        ids = [s.id for s in self.shelters]
        if len(ids) != len(set(ids)):
            raise ConfigurationError("shelter IDs must be unique")
        if set(ids) != {"S1", "S2", "S3", "S4", "S5"}:
            raise ConfigurationError("this scenario requires exactly S1, S2, S3, S4, S5")

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

    def with_overrides(self, seed: int | None = None,
                       population: int | None = None) -> "Configuration":
        updates = {}
        if seed is not None:
            updates["seed"] = seed
        if population is not None:
            updates["population"] = population
        return replace(self, simulation=replace(self.simulation, **updates))


def construct(model: type, data: Any, label: str) -> Any:
    if not isinstance(data, dict):
        raise ConfigurationError(f"{label} must contain a JSON object")
    expected = {field.name for field in fields(model)}
    missing, extra = expected - data.keys(), data.keys() - expected
    if missing or extra:
        raise ConfigurationError(f"{label}: missing keys {sorted(missing)}; unknown keys {sorted(extra)}")
    # Normalize JSON lists to tuples so the frozen configuration stays immutable.
    converted = {k: tuple(v) if isinstance(v, list) else v for k, v in data.items()}
    return model(**converted)


def load_configuration(directory: Path | str | None = None) -> Configuration:
    directory = Path(directory) if directory is not None else Path(__file__).resolve().parent

    def read(name: str) -> Any:
        path = directory / name
        try:
            return json.loads(path.read_text(encoding="utf-8-sig"))
        except (OSError, ValueError) as error:
            raise ConfigurationError(f"Cannot read {path}: {error}") from error

    simulation = construct(SimulationSettings, read("simulation.json"), "simulation.json")
    agents = construct(AgentSettings, read("agents.json"), "agents.json")
    shelters_data = read("shelters.json")
    if not isinstance(shelters_data, list):
        raise ConfigurationError("shelters.json must contain a JSON list")
    shelters = tuple(construct(ShelterSpec, item, "shelters.json") for item in shelters_data)
    return Configuration(simulation, agents, shelters)
