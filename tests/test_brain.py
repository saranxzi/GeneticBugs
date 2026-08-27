"""
Unit tests for BugBrain neural network.
"""

import numpy as np
import pytest
from simulation import BugBrain


def test_brain_genome_roundtrip():
    brain = BugBrain(num_inputs=6, num_hidden=8, num_outputs=2)
    rng = np.random.default_rng(123)
    genome = BugBrain.random_genome(6, 8, 2, rng=rng)

    assert len(genome) == (6 * 8 + 8 + 8 * 2 + 2)  # 74
    brain.set_genome(genome)
    encoded = brain.get_genome()

    np.testing.assert_allclose(genome, encoded, rtol=1e-6, atol=1e-6)


def test_brain_forward_ranges():
    brain = BugBrain(num_inputs=6, num_hidden=8, num_outputs=2)
    rng = np.random.default_rng(456)
    genome = BugBrain.random_genome(6, 8, 2, rng=rng)
    brain.set_genome(genome)

    # Test across multiple random input vectors
    for _ in range(50):
        # inputs: [dist_food, angle_food, dist_hazard, angle_hazard, energy, dist_wall]
        test_in = rng.uniform(-1.0, 1.0, size=6).astype(np.float32)
        turn, speed = brain.forward(test_in)

        assert -1.0 <= turn <= 1.0, f"Turn {turn} out of bounds [-1, 1]"
        assert 0.0 <= speed <= 1.0, f"Speed {speed} out of bounds [0, 1]"


def test_brain_deterministic():
    brain1 = BugBrain(num_inputs=6, num_hidden=8, num_outputs=2)
    brain2 = BugBrain(num_inputs=6, num_hidden=8, num_outputs=2)

    rng = np.random.default_rng(789)
    genome = BugBrain.random_genome(6, 8, 2, rng=rng)
    brain1.set_genome(genome)
    brain2.set_genome(genome)

    inputs = np.array([0.2, -0.5, 0.8, 0.3, 0.9, 0.1], dtype=np.float32)
    t1, s1 = brain1.forward(inputs)
    t2, s2 = brain2.forward(inputs)

    assert t1 == t2
    assert s1 == s2


def test_brain_accepts_list_genome():
    brain = BugBrain(num_inputs=6, num_hidden=8, num_outputs=2)
    genome_list = [0.1] * 74
    brain.set_genome(genome_list)
    assert len(brain.get_genome()) == 74


def test_brain_rejects_invalid_genome_length():
    brain = BugBrain(num_inputs=6, num_hidden=8, num_outputs=2)
    with pytest.raises(ValueError):
        brain.set_genome(np.zeros(50, dtype=np.float32))


if __name__ == "__main__":
    pytest.main([__file__])
