"""
Unit tests and convergence verification for the Genetic Algorithm.
"""

import numpy as np
import pytest
from simulation import SimulationConfig, Environment, GeneticAlgorithm


def test_ga_operators():
    """Verify selection, crossover, mutation, and elitism maintain population invariants."""
    config = SimulationConfig(population_size=20, elitism_count=2)
    ga = GeneticAlgorithm(config)

    pop = ga.initialize_population()
    assert len(pop) == 20
    for genome in pop:
        assert len(genome) == (6 * 8 + 8 + 8 * 2 + 2)

    # Test mutation changes weights
    original = pop[0].copy()
    mutated = ga.mutate(original)
    assert not np.array_equal(original, mutated)

    # Test crossover
    parent_a = np.zeros(74, dtype=np.float32)
    parent_b = np.ones(74, dtype=np.float32)
    child = ga.uniform_crossover(parent_a, parent_b)
    # Child should have some 0s and some 1s
    assert np.any(child == 0.0)
    assert np.any(child == 1.0)


def test_evolution_convergence():
    """
    Simulate headless evolution for 45 generations.
    Confirm that champion fitness and food consumption trend upward,
    and verify food score dominates over proximity shaping.
    """
    config = SimulationConfig(
        seed=101,
        population_size=50,
        generations=45,
        ticks_per_generation=500,
        food_count=40,
        hazard_count=5,
        food_fitness_weight=120.0,
        survival_fitness_weight=0.10,
        max_proximity_bonus=5.0
    )

    env = Environment(config)
    ga = GeneticAlgorithm(config)
    pop = ga.initialize_population()

    history = []

    for gen in range(config.generations):
        # Reset environment deterministically for this run
        env.reset_generation(gen_seed=config.seed, bugs_genomes=pop)

        for tick in range(config.ticks_per_generation):
            env.step_tick(tick)

        env.finalize_fitness()
        pop, stats = ga.evolve_generation(pop, env.bugs)
        history.append(stats)

        if gen % 10 == 0 or gen == config.generations - 1:
            print(
                f"Gen {gen:2d} | Best Fit: {stats['best_fitness']:6.1f} (Food: {stats['best_food']}, "
                f"Breakdown: food={stats['breakdown']['food_score']}, prox={stats['breakdown']['proximity_score']}, "
                f"surv={stats['breakdown']['survival_score']}) | Avg Fit: {stats['avg_fitness']:5.1f}"
            )

    # Assertions
    gen0_best = history[0]["best_fitness"]
    final_best = history[-1]["best_fitness"]
    max_ever = max(h["best_fitness"] for h in history)

    print(f"\nEvolution Summary: Gen 0 Best: {gen0_best} -> Final Best: {final_best} (Max Ever: {max_ever})")

    # Fitness should show marked improvement over generation 0
    assert final_best > gen0_best or max_ever > gen0_best * 1.5

    # Check breakdown: In later generations, food eating should occur and dominate proximity bonus
    champion_stats = max(history, key=lambda s: s["best_fitness"])
    assert champion_stats["best_food"] >= 1, "Champion should have learned to eat food!"
    assert champion_stats["breakdown"]["food_score"] > champion_stats["breakdown"]["proximity_score"], \
        "Food score should comfortably dominate proximity shaping!"


if __name__ == "__main__":
    pytest.main(["-s", __file__])
