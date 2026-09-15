# GeneticBugs: 2D Evolutionary Neural Simulation

**GeneticBugs** is a high-performance 2D continuous evolutionary simulation where autonomous neural creatures ("bugs") evolve in real time to forage for food and avoid hazards in a bounded cybernetic terrarium.

---

## Key Features & Architecture

### 1. Dedicated Real-Time Live Simulator (Godot 4.x)
- **High-Throughput Pure GDScript Engine**: Simulates 100+ neural creatures in real time without intermediate file or trajectory storage overhead.
- **Hardware-Accelerated 2D Batch Drawing**: Arena floor, boundaries, hazard zones, food pellets, and all 100 bug bodies are rendered in a single unified `_draw()` pass, dropping runtime node count from ~215 down to 15.
- **Unrolled Zero-Allocation Forward Pass**: The 8-neuron hidden layer forward pass uses unrolled scalar arithmetic, eliminating per-tick array allocations and garbage collection pauses.
- **Pre-Parsed Typed Spatial Structures**: Pre-parsed `PackedVector2Array` and `PackedFloat32Array` structures replace Dictionary lookups during simulation ticks.
- **Inner-Loop Algorithmic Optimization**: Replaces Euclidean distance and hypot checks with squared-distance comparisons ($dx^2 + dy^2 < r^2$) across all collision and nearest-neighbor loops.
- **Decoupled Physics & Render Stepping**: Discrete simulation stepping operates independently from the visual SceneTree, updating visual nodes once per frame to enable ultra-fast execution up to 64x and Uncapped.
- **Infinite Generation Mode**: Supports continuous non-stop evolution (`-1 = ∞`) or fixed generation goals.
- **Dynamic Parameter Tuning**: Live in-app tuning for population size, generation ticks, mutation rate, metabolic energy decay, food count, and food energy gain.

### 2. Neural Architecture & Kinematics
- **Continuous 2D Arena**: 900 x 600 bounded terrarium with soft boundary margins and static hazards.
- **Kinematic Steering**: Differential steering (turn rate delta) and forward thrust.
- **6 Ego-Centric Sensor Inputs**:
  1. Normalized distance to nearest food pellet [0, 1]
  2. Relative bearing to nearest food pellet [-1, 1]
  3. Normalized edge distance to nearest hazard [0, 1]
  4. Relative bearing to nearest hazard [-1, 1]
  5. Normalized remaining energy [0, 1]
  6. Normalized distance to nearest arena boundary [0, 1]
- **Neural Brain**: Feedforward network (6 inputs -> 8 hidden -> 2 outputs, 74 total parameters) with tanh hidden activations, tanh steering output, and logistic sigmoid speed output.

### 3. Evolutionary Dynamics & Invariants
- **Deterministic Layout Seeding**: Hazard and initial food placements are deterministically placed per run so evolutionary fitness gains strictly reflect policy adaptation rather than spawn luck.
- **Anti-Camping & Reward Bounding**: Continuous proximity shaping is strictly capped at <= 5% of the terminal food reward (max 5.0 pts vs. 120.0 pts per food). Fitness components (food, survival, hazard penalty, proximity bonus) are tracked and displayed independently to prevent reward hacking.
- **Operators**: Tournament selection ($k=3$), uniform crossover ($p_c = 0.75$), Gaussian mutation with adaptive random resets, and elitism ($E = 5$).

---

## Project Structure

```
GeneticBugs/
├── simulation/
│   ├── __init__.py          # Re-exports core simulation symbols
│   └── sim.py               # Consolidated engine: Brain, Config, Environment, GA, Runner
├── run_sim.bat              # Portable Windows launcher for GeneticBugs Live Simulator
├── run_simulation.py        # CLI entry point for headless Python evolution
├── tests/
│   ├── test_brain.py        # Neural net roundtrip and forward pass tests
│   ├── test_environment.py  # Kinematics, sensors, collisions, and food tests
│   └── test_ga.py           # GA operators and convergence verification
├── godot/
│   ├── project.godot        # Godot 4 project configuration (1280x720)
│   ├── scenes/
│   │   └── main.tscn        # Main viewport, top menu bar, and stats overlay
│   └── scripts/
│       ├── arena.gd         # Unified 2D batch drawing for arena, hazards, food, and bugs
│       ├── fitness_graph.gd # Vector line chart (Best and Average fitness)
│       ├── live_sim.gd      # Real-time GDScript simulation and evolution engine
│       ├── main.gd          # Master controller and UI coordinator
│       └── test_runner.gd   # Headless automated validation test suite
├── pyproject.toml           # Build configuration and linting rules
├── requirements.txt         # Runtime dependencies (numpy)
├── requirements-dev.txt     # Developer dependencies (pytest, ruff, mypy)
└── README.md
```

---

## Getting Started

### Prerequisites
- **Python**: 3.10 or newer with `numpy`
- **Godot Engine**: Godot 4.2+ (Forward+ or Compatibility renderer)

### Installation
```bash
# Clone the repository
git clone https://github.com/username/GeneticBugs.git
cd GeneticBugs

# Install Python dependencies
pip install -r requirements.txt

# (Optional) Install developer test tools
pip install -r requirements-dev.txt
```

---

## Running the Simulator

### 1. Launch Live Simulator (Godot 4)
Double-click `run_sim.bat` or run via terminal:
```powershell
# Windows
.\run_sim.bat

# Or directly with Godot CLI
godot --path godot
```

### 2. Run Headless Evolution (Python)
Execute via CLI:
```bash
python run_simulation.py --generations 50 --pop-size 60 --ticks 600 --seed 42
```

---

## Controls & Telemetry

### Top Menu Bar
- **Pause / Play**: Toggle continuous simulation execution (`Space`).
- **Speed Multiplier**: `0.5x`, `1.0x`, `2.0x`, `4.0x`, `8.0x`, `16.0x`, `32.0x`, `64.0x`, `Uncapped`.
- **Telemetry Counters**: Real-time display of current generation, current tick, alive count, and casualty count.
- **Graphs & Stats [H]**: Toggle the semi-transparent side telemetry overlay (`H` or `Tab`).

### Graphs & Stats Panel
- **Fitness Progression Chart**: Real-time vector line graph tracking Best Fitness (gold) and Average Fitness (cyan) across all evolved generations.
- **Live Hyperparameter Tuning**:
  - **Max Gens**: Target generation limit (`-1` for infinite continuous simulation).
  - **Pop Size**: Active population count (1 to 100,000).
  - **Gen Ticks**: Lifespan ticks per generation (1 to 10,000,000).
  - **Mutation Rate**: Per-gene mutation probability (0.0% to 1,000.0%).
  - **Energy Decay**: Metabolic cost per tick (-1,000.0 to 10,000.0).
  - **Food Count**: Number of concurrent food pellets in arena (1 to 10,000).
  - **Food Energy Gain**: Energy restored per pellet consumed (0.0 to 10,000.0).
- **Casualty Diagnostics**: Real-time breakdown of deaths caused by hazards vs. starvation.

### Keyboard Shortcuts
| Key | Action |
|---|---|
| `Space` | Pause / Play simulation |
| `H` / `Tab` | Toggle "Graphs & Stats" Overlay (Clean Fullscreen View) |

---

## Verification & Testing

### Godot Headless Test Suite
Run the automated verification suite validating scene loading, arena bug instancing, decoupled physics stepping, infinite generation mode, and parameter reconfiguration:
```powershell
godot --headless --path godot -s res://scripts/test_runner.gd
```

### Python Test Suite
Run the unit test suite verifying neural network encoding, kinematics, collision geometry, deterministic layouts, and GA convergence:
```bash
python -m pytest tests/
```

---

## License
MIT License. Open source for research, educational, and personal use.
