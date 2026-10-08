"""Shelter truth belongs to the environment, separate from agents' beliefs."""

from dataclasses import dataclass, field
from random import Random

from config.settings import ShelterSpec


@dataclass
class Shelter:
    spec: ShelterSpec
    exists: bool
    supplies_person_days: float
    occupants: list[int] = field(default_factory=list)
    operational: bool = True

    @property
    def remaining_capacity(self) -> int:
        return self.spec.capacity - len(self.occupants)


def create_shelters(specs: tuple[ShelterSpec, ...], rng: Random) -> dict[str, Shelter]:
    shelters = {}
    for spec in specs:
        # Draw uncertain existence once, never again during movement or admission.
        if spec.existence_probability in (0.0, 1.0):
            exists = bool(spec.existence_probability)
        else:
            exists = rng.random() < spec.existence_probability
        supplies = spec.supplies_person_days
        if supplies is None:
            assert spec.supplies_range_person_days is not None
            supplies = rng.uniform(*spec.supplies_range_person_days)
        shelters[spec.id] = Shelter(spec, exists, supplies, operational=exists)
    return shelters
