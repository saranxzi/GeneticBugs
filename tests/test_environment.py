"""
Unit tests for GeneticBugs simulation environment.
"""

import math
import numpy as np
import pytest
from simulation import SimulationConfig, BugBrain, Environment, BugState, FoodPellet, Hazard


def test_deterministic_layout():
    """Verify same seed produces 100% identical hazard and food placement across generations."""
    config = SimulationConfig(seed=12345)
    env1 = Environment(config)
    env2 = Environment(config)

    dummy_genomes = [BugBrain.random_genome() for _ in range(5)]

    env1.reset_generation(gen_seed=config.seed, bugs_genomes=dummy_genomes)
    env2.reset_generation(gen_seed=config.seed, bugs_genomes=dummy_genomes)

    assert len(env1.hazards) == len(env2.hazards)
    for h1, h2 in zip(env1.hazards, env2.hazards):
        assert h1.x == h2.x
        assert h1.y == h2.y
        assert h1.radius == h2.radius

    assert len(env1.food_pellets) == len(env2.food_pellets)
    for f1, f2 in zip(env1.food_pellets, env2.food_pellets):
        assert f1.x == f2.x
        assert f1.y == f2.y


def test_bug_kinematics_and_walls():
    """Verify bug moves in direction of heading and stops at walls."""
    config = SimulationConfig(arena_width=200.0, arena_height=200.0, wall_margin=10.0)
    env = Environment(config)
    dummy_genome = BugBrain.random_genome()
    env.reset_generation(gen_seed=42, bugs_genomes=[dummy_genome])

    bug = env.bugs[0]
    bug.x = 100.0
    bug.y = 100.0
    bug.heading = 0.0  # Pointing directly East (+X)

    # Move right towards wall
    for tick in range(100):
        # Force brain to move straight ahead at max speed
        env.step_tick(tick)

    # Bug should remain within arena boundary [r_bug, W - r_bug]
    assert bug.x <= config.arena_width - config.bug_radius
    assert bug.x >= config.bug_radius
    assert bug.y <= config.arena_height - config.bug_radius
    assert bug.y >= config.bug_radius


def test_food_consumption():
    """Verify eating food replenishes energy and increments food count."""
    config = SimulationConfig(bug_initial_energy=50.0, food_energy_gain=30.0)
    env = Environment(config)
    genome = BugBrain.random_genome()
    env.reset_generation(gen_seed=42, bugs_genomes=[genome])

    bug = env.bugs[0]
    bug.energy = 40.0
    food = env.food_pellets[0]

    # Place bug directly on top of food
    bug.x = food.x
    bug.y = food.y
    old_food_x = food.x

    # Step one tick
    env.step_tick(0)

    # Food should have been consumed and respawned
    assert bug.food_eaten >= 1
    assert bug.energy > 40.0
    assert len(env.food_events) >= 1
    assert env.food_events[0]["bug_id"] == bug.id


def test_hazard_collision_and_penalty():
    """Verify touching hazard causes instant death and penalty."""
    config = SimulationConfig()
    env = Environment(config)
    genome = BugBrain.random_genome()
    env.reset_generation(gen_seed=42, bugs_genomes=[genome])

    bug = env.bugs[0]
    hazard = env.hazards[0]

    # Place bug right at hazard center
    bug.x = hazard.x
    bug.y = hazard.y

    env.step_tick(0)

    assert not bug.alive
    assert bug.death_reason == "hazard"

    env.finalize_fitness()
    assert bug.hazard_penalty < 0.0


def test_fitness_breakdown():
    """Verify fitness components are logged separately and combined properly."""
    config = SimulationConfig(food_fitness_weight=100.0, survival_fitness_weight=1.0)
    env = Environment(config)
    genome = BugBrain.random_genome()
    env.reset_generation(gen_seed=42, bugs_genomes=[genome])

    bug = env.bugs[0]
    bug.food_eaten = 2
    bug.ticks_alive = 50
    bug.alive = True
    bug.min_food_dist = 10.0

    env.finalize_fitness()

    assert bug.food_score == 200.0
    assert bug.survival_score == 50.0
    assert bug.hazard_penalty == 0.0
    assert 0.0 <= bug.proximity_score <= config.max_proximity_bonus
    expected_total = bug.food_score + bug.survival_score + bug.hazard_penalty + bug.proximity_score
    assert abs(bug.total_fitness - expected_total) < 1e-4


def test_config_json_roundtrip_with_extra_keys(tmp_path):
    """Verify SimulationConfig ignores unknown future keys when loading JSON."""
    cfg = SimulationConfig(arena_width=950.0, seed=99)
    cfg_file = tmp_path / "config.json"
    cfg.save_json(cfg_file)

    # Inject unknown extra keys into JSON
    import json
    with open(cfg_file, "r") as f:
        data = json.load(f)
    data["unknown_future_param"] = "test_value"
    data["extra_setting"] = 12345
    with open(cfg_file, "w") as f:
        json.dump(data, f)

    loaded = SimulationConfig.load_json(cfg_file)
    assert loaded.arena_width == 950.0
    assert loaded.seed == 99


def test_sensors_empty_food_edge_case():
    """Verify sensors do not crash or return NaN if food list is empty."""
    config = SimulationConfig()
    env = Environment(config)
    env.reset_generation(gen_seed=42, bugs_genomes=[BugBrain.random_genome()])
    env.food_pellets.clear()  # Edge case: no food pellets in arena

    sensors = env.get_sensors(env.bugs[0])
    assert len(sensors) == 6
    assert not np.isnan(sensors).any()
    assert not np.isinf(sensors).any()


if __name__ == "__main__":
    pytest.main([__file__])
