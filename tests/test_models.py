from dataclasses import replace
from random import Random
import unittest

from config.settings import ConfigurationError, load_configuration, construct, SimulationSettings
from models.agent import create_agents
from models.shelter import create_shelters


class ModelTests(unittest.TestCase):
    def setUp(self):
        self.config = load_configuration()

    def test_five_shelter_capacities_and_resources(self):
        specs = {s.id: s for s in self.config.shelters}
        self.assertEqual([specs[f"S{i}"].capacity for i in range(1, 6)],
                         [2500, 750, 1800, 3500, 5000])
        self.assertEqual(specs["S1"].supplies_person_days, 2000)
        self.assertIsNone(specs["S3"].reported_supplies_person_days)
        self.assertEqual(specs["S5"].existence_probability, 0.5)

    def test_seeded_shelter_generation_and_existence_extremes(self):
        self.assertEqual(create_shelters(self.config.shelters, Random(4)),
                         create_shelters(self.config.shelters, Random(4)))
        for probability, expected in [(0.0, False), (1.0, True)]:
            spec = replace(self.config.shelters[-1], existence_probability=probability)
            self.assertEqual(create_shelters((spec,), Random(4))["S5"].exists, expected)

    def test_agents_have_unique_ids_and_distinct_beliefs(self):
        agents = create_agents(100, self.config.agents, self.config.shelters, Random(7))
        self.assertEqual(len({a.id for a in agents}), 100)
        self.assertGreater(len({a.speed_m_per_second for a in agents}), 1)
        self.assertEqual({a.role for a in agents}, {"civilian", "authority"})
        agents[0].beliefs["S5"].unavailable = True
        self.assertFalse(agents[1].beliefs["S5"].unavailable)
        self.assertEqual(agents[0].beliefs["S5"].existence_probability, 0.5)
        self.assertIsNone(agents[0].beliefs["S3"].reported_supplies_person_days)

    def test_s5_truth_not_given_to_agents(self):
        specs = self.config.shelters[:-1] + (
            replace(self.config.shelters[-1], existence_probability=0.0),)
        shelters = create_shelters(specs, Random(2))
        agents = create_agents(1, self.config.agents, specs, Random(2))
        self.assertFalse(shelters["S5"].exists)
        self.assertEqual(agents[0].beliefs["S5"].existence_probability, 0.5)

    def test_invalid_configuration_rejected(self):
        for updates in ({"population": 0}, {"population": True},
                        {"tick_seconds": 0}, {"tick_seconds": float("nan")},
                        {"countdown_max_seconds": 601}, {"seed": 2.5}):
            with self.subTest(updates=updates), self.assertRaises(ConfigurationError):
                replace(self.config.simulation, **updates)
        with self.assertRaises(ConfigurationError):
            replace(self.config.agents, speed_m_per_second=(4, 1))
        with self.assertRaises(ConfigurationError):
            replace(self.config.shelters[0], capacity=-1)
        with self.assertRaises(ConfigurationError):
            replace(self.config.shelters[0], existence_probability=1.2)
        with self.assertRaises(ConfigurationError):
            replace(self.config, shelters=(self.config.shelters[0],) * 5)

    def test_unknown_config_keys_rejected(self):
        data = self.config.to_dict()["simulation"]
        data["populaton"] = 10
        with self.assertRaises(ConfigurationError):
            construct(SimulationSettings, data, "test")

    def test_configuration_overrides_are_validated(self):
        changed = self.config.with_overrides(seed=0, population=5)
        self.assertEqual(changed.simulation.seed, 0)
        self.assertEqual(changed.simulation.population, 5)
        self.assertEqual(self.config.simulation.population, 1000)
        with self.assertRaises(ConfigurationError):
            self.config.with_overrides(population=-1)
