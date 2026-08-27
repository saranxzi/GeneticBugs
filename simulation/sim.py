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
