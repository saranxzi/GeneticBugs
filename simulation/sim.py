"""
GeneticBugs Core Simulation Engine.
Consolidates neural brain, kinematics, environment, genetic algorithm, and runner.
"""

from dataclasses import dataclass, field, asdict, fields
from typing import List, Tuple, Dict, Any, Optional, Callable
from pathlib import Path
import json
import math
import time
import numpy as np


def wrap_angle(rad: float) -> float:
    """Wraps an angle in radians to [-pi, pi]."""
    return (rad + math.pi) % (2.0 * math.pi) - math.pi


@dataclass
class SimulationConfig:
    seed: int = 42
    arena_width: float = 900.0
    arena_height: float = 600.0
    wall_margin: float = 20.0

    food_count: int = 40
    food_radius: float = 8.0
    food_energy_gain: float = 40.0

    hazard_count: int = 6
    hazard_min_radius: float = 35.0
    hazard_max_radius: float = 45.0

    bug_radius: float = 10.0
    bug_initial_energy: float = 100.0
    bug_energy_decay_per_tick: float = 0.35
    bug_max_speed: float = 4.0
    bug_max_turn_rate: float = 0.45

    num_inputs: int = 6
    num_hidden: int = 8
    num_outputs: int = 2

    population_size: int = 100
    generations: int = 100
    ticks_per_generation: int = 600
    elitism_count: int = 5
    tournament_size: int = 3
    crossover_rate: float = 0.75
    mutation_rate: float = 0.10
    mutation_sigma: float = 0.25
    random_reset_rate: float = 0.02

    food_fitness_weight: float = 120.0
    survival_fitness_weight: float = 0.10
    hazard_penalty: float = 40.0
    max_proximity_bonus: float = 5.0
    max_logged_samples: int = 12

    def to_dict(self) -> dict:
        return asdict(self)

    def save_json(self, filepath: str | Path) -> None:
        Path(filepath).parent.mkdir(parents=True, exist_ok=True)
        with open(filepath, "w", encoding="utf-8") as f:
            json.dump(self.to_dict(), f, indent=2)

    @classmethod
    def load_json(cls, filepath: str | Path) -> "SimulationConfig":
        with open(filepath, "r", encoding="utf-8") as f:
            data = json.load(f)
        valid_fields = {f.name for f in fields(cls)}
        return cls(**{k: v for k, v in data.items() if k in valid_fields})


class BugBrain:
    """Feedforward Neural Network (6 inputs -> 8 hidden [tanh] -> 2 outputs [tanh, sigmoid])."""

    def __init__(self, num_inputs: int = 6, num_hidden: int = 8, num_outputs: int = 2):
        self.num_inputs = num_inputs
        self.num_hidden = num_hidden
        self.num_outputs = num_outputs

        self.w1_size = num_inputs * num_hidden
        self.b1_size = num_hidden
        self.w2_size = num_hidden * num_outputs
        self.b2_size = num_outputs
        self.total_weights = self.w1_size + self.b1_size + self.w2_size + self.b2_size

        self.W1 = np.zeros((num_inputs, num_hidden), dtype=np.float32)
        self.b1 = np.zeros(num_hidden, dtype=np.float32)
        self.W2 = np.zeros((num_hidden, num_outputs), dtype=np.float32)
        self.b2 = np.zeros(num_outputs, dtype=np.float32)

    @classmethod
    def random_genome(cls, num_inputs: int = 6, num_hidden: int = 8, num_outputs: int = 2,
                      rng: np.random.Generator | None = None) -> np.ndarray:
        if rng is None:
            rng = np.random.default_rng()
        w1_scale = np.sqrt(2.0 / (num_inputs + num_hidden))
        w2_scale = np.sqrt(2.0 / (num_hidden + num_outputs))
        w1 = rng.normal(0.0, w1_scale, (num_inputs, num_hidden)).astype(np.float32)
        b1 = np.zeros(num_hidden, dtype=np.float32)
        w2 = rng.normal(0.0, w2_scale, (num_hidden, num_outputs)).astype(np.float32)
        b2 = np.zeros(num_outputs, dtype=np.float32)
        return np.concatenate([w1.ravel(), b1, w2.ravel(), b2])

    def set_genome(self, genome: np.ndarray | list) -> None:
        arr = np.asarray(genome, dtype=np.float32).ravel()
        if len(arr) != self.total_weights:
            raise ValueError(f"Genome length {len(arr)} does not match expected {self.total_weights}")
        idx = 0
        self.W1 = arr[idx : idx + self.w1_size].reshape((self.num_inputs, self.num_hidden))
        idx += self.w1_size
        self.b1 = arr[idx : idx + self.b1_size].copy()
        idx += self.b1_size
        self.W2 = arr[idx : idx + self.w2_size].reshape((self.num_hidden, self.num_outputs))
        idx += self.w2_size
        self.b2 = arr[idx : idx + self.b2_size].copy()

    def get_genome(self) -> np.ndarray:
        return np.concatenate([self.W1.ravel(), self.b1, self.W2.ravel(), self.b2]).astype(np.float32)

    def forward(self, inputs: np.ndarray) -> Tuple[float, float]:
        hidden = np.tanh(np.dot(inputs, self.W1) + self.b1)
        out = np.dot(hidden, self.W2) + self.b2
        turn = float(np.tanh(out[0]))
        speed = float(1.0 / (1.0 + np.exp(-np.clip(out[1], -30.0, 30.0))))
        return turn, speed


@dataclass
class Hazard:
    x: float
    y: float
    radius: float

    def to_dict(self) -> Dict[str, float]:
        return {"x": round(self.x, 1), "y": round(self.y, 1), "radius": round(self.radius, 1)}


@dataclass
class FoodPellet:
    x: float
    y: float
    id: int

    def to_dict(self) -> Dict[str, Any]:
        return {"id": self.id, "x": round(self.x, 1), "y": round(self.y, 1)}


@dataclass
class BugState:
    id: int
    x: float
    y: float
    heading: float
    energy: float
    alive: bool = True
    food_eaten: int = 0
    ticks_alive: int = 0
    death_tick: int = -1
    death_reason: Optional[str] = None
    min_food_dist: float = float("inf")

    food_score: float = 0.0
    survival_score: float = 0.0
    hazard_penalty: float = 0.0
    proximity_score: float = 0.0
    total_fitness: float = 0.0
    trajectory: List[List[float]] = field(default_factory=list)


class Environment:
    """Continuous 2D arena with deterministic resets, sensors, and kinematics."""

    def __init__(self, config: SimulationConfig):
        self.config = config
        self.arena_w = config.arena_width
        self.arena_h = config.arena_height
        self.max_diag = math.sqrt(self.arena_w ** 2 + self.arena_h ** 2)

        self.hazards: List[Hazard] = []
        self.food_pellets: List[FoodPellet] = []
        self.bugs: List[BugState] = []
        self.brains: List[BugBrain] = []
        self.food_events: List[Dict[str, Any]] = []
        self.respawn_rng = np.random.default_rng(config.seed)

    def reset_generation(self, gen_seed: int, bugs_genomes: List[np.ndarray]) -> None:
        layout_rng = np.random.default_rng(gen_seed)
        self.respawn_rng = np.random.default_rng(gen_seed + 10000)
        self.food_events.clear()

        # 1. Hazards
        self.hazards.clear()
        margin = self.config.wall_margin + 50.0
        for _ in range(self.config.hazard_count):
            hx = float(layout_rng.uniform(margin, self.arena_w - margin))
            hy = float(layout_rng.uniform(margin, self.arena_h - margin))
            hr = float(layout_rng.uniform(self.config.hazard_min_radius, self.config.hazard_max_radius))
            self.hazards.append(Hazard(hx, hy, hr))

        # 2. Food Pellets
        self.food_pellets.clear()
        f_margin = self.config.wall_margin + 10.0
        food_id = 0
        while len(self.food_pellets) < self.config.food_count:
            fx = float(layout_rng.uniform(f_margin, self.arena_w - f_margin))
            fy = float(layout_rng.uniform(f_margin, self.arena_h - f_margin))
            if not any(((fx - h.x)**2 + (fy - h.y)**2) < (h.radius * h.radius) for h in self.hazards):
                self.food_pellets.append(FoodPellet(fx, fy, food_id))
                food_id += 1

        # 3. Bugs & Brains
        self.bugs.clear()
        self.brains.clear()
        spawn_rng = np.random.default_rng(gen_seed + 20000)
        center_x, center_y = self.arena_w / 2.0, self.arena_h / 2.0
        spawn_radius = min(self.arena_w, self.arena_h) * 0.35

        for i, genome in enumerate(bugs_genomes):
            angle = float(spawn_rng.uniform(0, 2.0 * math.pi))
            r = float(spawn_rng.uniform(20.0, spawn_radius))
            bx = float(np.clip(center_x + r * math.cos(angle), self.config.wall_margin, self.arena_w - self.config.wall_margin))
            by = float(np.clip(center_y + r * math.sin(angle), self.config.wall_margin, self.arena_h - self.config.wall_margin))
            heading = float(spawn_rng.uniform(-math.pi, math.pi))

            bug = BugState(id=i, x=bx, y=by, heading=heading, energy=self.config.bug_initial_energy)
            self.bugs.append(bug)

            brain = BugBrain(self.config.num_inputs, self.config.num_hidden, self.config.num_outputs)
            brain.set_genome(genome)
            self.brains.append(brain)

    def _respawn_food(self, food: FoodPellet, tick: int, bug_id: int) -> None:
        old_x, old_y = food.x, food.y
        f_margin = self.config.wall_margin + 10.0
        for _ in range(100):
            nx = float(self.respawn_rng.uniform(f_margin, self.arena_w - f_margin))
            ny = float(self.respawn_rng.uniform(f_margin, self.arena_h - f_margin))
            if not any(((nx - h.x)**2 + (ny - h.y)**2) < (h.radius * h.radius) for h in self.hazards):
                food.x, food.y = nx, ny
                break
        else:
            food.x, food.y = self.arena_w / 2.0, self.arena_h / 2.0

        self.food_events.append({
            "tick": tick, "food_id": food.id, "bug_id": bug_id,
            "old_x": round(old_x, 1), "old_y": round(old_y, 1),
            "new_x": round(food.x, 1), "new_y": round(food.y, 1)
        })

    def get_sensors(self, bug: BugState) -> np.ndarray:
        # 1. Nearest food (squared distance search)
        min_f_sq = float("inf")
        n_fdx, n_fdy = 0.0, 0.0
        for f in self.food_pellets:
            dx = f.x - bug.x
            dy = f.y - bug.y
            dsq = dx * dx + dy * dy
            if dsq < min_f_sq:
                min_f_sq = dsq
                n_fdx, n_fdy = dx, dy

        if min_f_sq < float("inf"):
            min_f_dist = math.sqrt(min_f_sq)
            f_rel_angle = wrap_angle(math.atan2(n_fdy, n_fdx) - bug.heading) / math.pi
        else:
            min_f_dist = self.max_diag
            f_rel_angle = 0.0

        if min_f_dist < bug.min_food_dist:
            bug.min_food_dist = min_f_dist

        # 2. Nearest hazard
        min_h_dist = float("inf")
        h_rel_angle = 0.0
        for h in self.hazards:
            dx = h.x - bug.x
            dy = h.y - bug.y
            dist = math.hypot(dx, dy)
            edge_dist = max(0.0, dist - h.radius)
            if edge_dist < min_h_dist:
                min_h_dist = edge_dist
                h_rel_angle = wrap_angle(math.atan2(dy, dx) - bug.heading) / math.pi

        # 3. Normalized values
        norm_f = min(min_f_dist / self.max_diag, 1.0)
        norm_h = min(min_h_dist / self.max_diag, 1.0)
        norm_e = max(0.0, min(bug.energy / self.config.bug_initial_energy, 1.0))
        wall_d = min(bug.x, self.arena_w - bug.x, bug.y, self.arena_h - bug.y)
        norm_w = min(wall_d / (min(self.arena_w, self.arena_h) * 0.5), 1.0)

        return np.array([norm_f, f_rel_angle, norm_h, h_rel_angle, norm_e, norm_w], dtype=np.float32)

    def step_tick(self, tick: int) -> None:
        eat_r_sq = (self.config.bug_radius + self.config.food_radius) ** 2
        r_bug = self.config.bug_radius

        for i, bug in enumerate(self.bugs):
            if not bug.alive:
                continue

            bug.ticks_alive += 1
            sensors = self.get_sensors(bug)
            turn_act, speed_act = self.brains[i].forward(sensors)

            bug.heading = wrap_angle(bug.heading + turn_act * self.config.bug_max_turn_rate)
            spd = speed_act * self.config.bug_max_speed
            bug.x = float(np.clip(bug.x + spd * math.cos(bug.heading), r_bug, self.arena_w - r_bug))
            bug.y = float(np.clip(bug.y + spd * math.sin(bug.heading), r_bug, self.arena_h - r_bug))

            bug.energy -= self.config.bug_energy_decay_per_tick
            if bug.energy <= 0.0:
                bug.energy = 0.0
                bug.alive = False
                bug.death_tick = tick
                bug.death_reason = "starved"
                continue

            # Hazard collision
            for h in self.hazards:
                comb_r = r_bug + h.radius
                dx = bug.x - h.x
                dy = bug.y - h.y
                if (dx * dx + dy * dy) < (comb_r * comb_r):
                    bug.alive = False
                    bug.death_tick = tick
                    bug.death_reason = "hazard"
                    break

            if not bug.alive:
                continue

            # Food consumption
            for food in self.food_pellets:
                fdx = bug.x - food.x
                fdy = bug.y - food.y
                if (fdx * fdx + fdy * fdy) < eat_r_sq:
                    bug.food_eaten += 1
                    bug.energy = min(self.config.bug_initial_energy, bug.energy + self.config.food_energy_gain)
                    self._respawn_food(food, tick, bug.id)

    def finalize_fitness(self) -> None:
        for bug in self.bugs:
            bug.food_score = bug.food_eaten * self.config.food_fitness_weight
            bug.survival_score = bug.ticks_alive * self.config.survival_fitness_weight
            bug.hazard_penalty = -self.config.hazard_penalty if bug.death_reason == "hazard" else 0.0

            if self.max_diag > 0 and bug.min_food_dist < float("inf"):
                factor = max(0.0, 1.0 - (bug.min_food_dist / (self.max_diag * 0.5)))
                bug.proximity_score = min(self.config.max_proximity_bonus, self.config.max_proximity_bonus * factor)
            else:
                bug.proximity_score = 0.0

            bug.total_fitness = max(0.0, bug.food_score + bug.survival_score + bug.hazard_penalty + bug.proximity_score)


class GeneticAlgorithm:
    """Selection, uniform crossover, Gaussian mutation, and elitism for bug brains."""

    def __init__(self, config: SimulationConfig):
        self.config = config
        self.rng = np.random.default_rng(config.seed)

    def initialize_population(self) -> List[np.ndarray]:
        return [
            BugBrain.random_genome(self.config.num_inputs, self.config.num_hidden, self.config.num_outputs, rng=self.rng)
            for _ in range(self.config.population_size)
        ]

    def tournament_selection(self, population: List[np.ndarray], fitnesses: List[float]) -> np.ndarray:
        k = min(self.config.tournament_size, len(population))
        indices = self.rng.choice(len(population), size=k, replace=False)
        best_idx = max(indices, key=lambda idx: fitnesses[idx])
        return population[best_idx].copy()

    def uniform_crossover(self, parent_a: np.ndarray, parent_b: np.ndarray) -> np.ndarray:
        if self.rng.random() > self.config.crossover_rate:
            return parent_a.copy()
        mask = self.rng.random(len(parent_a)) < 0.5
        return np.where(mask, parent_a, parent_b).astype(np.float32)

    def mutate(self, genome: np.ndarray) -> np.ndarray:
        mutated = genome.copy()
        mutate_mask = self.rng.random(len(mutated)) < self.config.mutation_rate
        noise = self.rng.normal(0.0, self.config.mutation_sigma, len(mutated)).astype(np.float32)
        mutated += np.where(mutate_mask, noise, 0.0).astype(np.float32)

        reset_mask = self.rng.random(len(mutated)) < self.config.random_reset_rate
        if np.any(reset_mask):
            random_weights = self.rng.normal(0.0, 0.8, len(mutated)).astype(np.float32)
            mutated = np.where(reset_mask, random_weights, mutated).astype(np.float32)

        return mutated

    def evolve_generation(self, population: List[np.ndarray], bugs: List[BugState]) -> Tuple[List[np.ndarray], Dict[str, Any]]:
        sorted_indices = sorted(range(len(bugs)), key=lambda i: bugs[i].total_fitness, reverse=True)
        fitnesses = [bugs[i].total_fitness for i in range(len(bugs))]
        best = bugs[sorted_indices[0]]
        worst = bugs[sorted_indices[-1]]

        stats = {
            "best_fitness": round(float(best.total_fitness), 2),
            "avg_fitness": round(float(np.mean(fitnesses)), 2),
            "worst_fitness": round(float(worst.total_fitness), 2),
            "best_food": int(best.food_eaten),
            "avg_food": round(float(np.mean([b.food_eaten for b in bugs])), 2),
            "best_ticks_alive": int(best.ticks_alive),
            "breakdown": {
                "food_score": round(float(best.food_score), 2),
                "survival_score": round(float(best.survival_score), 2),
                "hazard_penalty": round(float(best.hazard_penalty), 2),
                "proximity_score": round(float(best.proximity_score), 2),
            }
        }

        # Elitism
        next_pop = [population[sorted_indices[i]].copy() for i in range(min(self.config.elitism_count, len(sorted_indices)))]
        while len(next_pop) < self.config.population_size:
            p_a = self.tournament_selection(population, fitnesses)
            p_b = self.tournament_selection(population, fitnesses)
            child = self.mutate(self.uniform_crossover(p_a, p_b))
            next_pop.append(child)

        return next_pop, stats


class SimulationRunner:
    """Coordinates headless evolution loop and generates run summaries."""

    def __init__(self, config: Optional[SimulationConfig] = None):
        self.config = config or SimulationConfig()
        self.env = Environment(self.config)
        self.ga = GeneticAlgorithm(self.config)

    def run(self, progress_callback: Optional[Callable[[int, int, Dict[str, Any]], None]] = None) -> Tuple[Dict[str, Any], List[Dict[str, Any]]]:
        start = time.time()
        population = self.ga.initialize_population()
        history: List[Dict[str, Any]] = []
        overall_champion: Optional[Dict[str, Any]] = None
        max_fit = -float("inf")

        for gen in range(self.config.generations):
            self.env.reset_generation(gen_seed=self.config.seed, bugs_genomes=population)
            for tick in range(self.config.ticks_per_generation):
                self.env.step_tick(tick)
            self.env.finalize_fitness()

            population, stats = self.ga.evolve_generation(population, self.env.bugs)
            stats["generation"] = gen
            history.append(stats)

            if stats["best_fitness"] > max_fit:
                max_fit = stats["best_fitness"]
                overall_champion = {
                    "generation": gen, "fitness": stats["best_fitness"],
                    "food_eaten": stats["best_food"], "ticks_alive": stats["best_ticks_alive"]
                }

            if progress_callback:
                progress_callback(gen, self.config.generations, stats)

        elapsed = round(time.time() - start, 2)
        summary = {
            "arena": {"width": self.config.arena_width, "height": self.config.arena_height},
            "config": self.config.to_dict(),
            "total_generations": self.config.generations,
            "elapsed_seconds": elapsed,
            "history": history,
            "overall_champion": overall_champion
        }
        return summary, history

    def run_and_export(self, output_dir: str | Path) -> Dict[str, Any]:
        summary, _ = self.run(
            progress_callback=lambda g, total, s: print(
                f"[Gen {g+1:02d}/{total:02d}] Best: {s['best_fitness']:6.1f} (Food: {s['best_food']:2d}) | Avg: {s['avg_fitness']:5.1f}"
            )
        )
        out_path = Path(output_dir)
        out_path.mkdir(parents=True, exist_ok=True)
        with open(out_path / "summary.json", "w", encoding="utf-8") as f:
            json.dump(summary, f, indent=2)
        return summary
