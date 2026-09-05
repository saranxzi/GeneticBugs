"""
CLI entry point to execute the GeneticBugs simulation and export JSON replays for Godot 4.
"""

import argparse
from pathlib import Path
from simulation import SimulationConfig, SimulationRunner


def main():
    parser = argparse.ArgumentParser(description="GeneticBugs 2D Genetic Algorithm Headless Simulator")
    parser.add_argument("--config", type=str, default=None, help="Path to JSON config file")
    parser.add_argument("--seed", type=int, default=42, help="RNG seed for simulation run")
    parser.add_argument("--generations", "-g", type=int, default=50, help="Number of generations to evolve")
    parser.add_argument("--pop-size", "-p", type=int, default=60, help="Population size per generation")
    parser.add_argument("--ticks", "-t", type=int, default=600, help="Ticks per generation")
    parser.add_argument(
        "--out-dir", "-o",
        type=str,
        default="godot/data",
        help="Output directory for JSON replay files (default: godot/data)"
    )
    parser.add_argument("--save-config", type=str, default=None, help="Save resolved config to JSON file")

    args = parser.parse_args()

    # Load or initialize config
    if args.config and Path(args.config).is_file():
        print(f"Loading configuration from {args.config}...")
        config = SimulationConfig.load_json(args.config)
    else:
        config = SimulationConfig(
            seed=args.seed,
            generations=args.generations,
            population_size=args.pop_size,
            ticks_per_generation=args.ticks
        )

    if args.save_config:
        config.save_json(args.save_config)
        print(f"Saved configuration to {args.save_config}")

    print("=" * 65)
    print("                GENETICBUGS HEADLESS SIMULATION                ")
    print("=" * 65)
    print(f" Arena: {config.arena_width}x{config.arena_height}")
    print(f" Population: {config.population_size} bugs | Generations: {config.generations}")
    print(f" Ticks per generation: {config.ticks_per_generation}")
    print(f" Seed: {config.seed} (deterministic per-generation layout)")
    print(f" Output Replay Directory: {args.out_dir}")
    print("=" * 65)

    runner = SimulationRunner(config)
    summary = runner.run_and_export(args.out_dir)

    print("=" * 65)
    print(f"Simulation completed in {summary['elapsed_seconds']}s.")
    champ = summary["overall_champion"]
    if champ:
        print(
            f"Overall Champion: Gen {champ['generation'] + 1} with Fitness {champ['fitness']:.1f} "
            f"({champ['food_eaten']} food eaten, {champ['ticks_alive']} ticks alive)"
        )
    print(f"Replay data exported to: {Path(args.out_dir).resolve()}")
    print("=" * 65)


if __name__ == "__main__":
    main()
