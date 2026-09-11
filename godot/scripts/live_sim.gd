class_name LiveSimulator
extends RefCounted

## Pure simulation and genetic algorithm engine.
## Operates entirely on data structures without scene graph coupling.

const DEFAULT_HAZARDS = [
	{"x": 200.0, "y": 180.0, "radius": 42.0},
	{"x": 700.0, "y": 190.0, "radius": 38.0},
	{"x": 450.0, "y": 300.0, "radius": 45.0},
	{"x": 220.0, "y": 420.0, "radius": 39.0},
	{"x": 680.0, "y": 430.0, "radius": 40.0},
	{"x": 450.0, "y": 120.0, "radius": 36.0}
]

var arena_width: float = 900.0
var arena_height: float = 600.0
var max_diag: float = 1081.66
var wall_margin: float = 20.0

var population_size: int = 100
var ticks_per_generation: int = 600
var current_tick: int = 0
var current_generation: int = 0
var mutation_rate: float = 0.10
var bug_energy_decay_per_tick: float = 0.35
var food_energy_gain: float = 40.0
var food_count: int = 40

var hazard_positions: PackedVector2Array = PackedVector2Array()
var hazard_radii: PackedFloat32Array = PackedFloat32Array()
var hazard_radii_sq: PackedFloat32Array = PackedFloat32Array()

class LiveBug:
	var id: int = 0
	var position: Vector2 = Vector2.ZERO
	var heading: float = 0.0
	var energy: float = 100.0
	var alive: bool = true
	var food_eaten: int = 0
	var ticks_alive: int = 0
	var death_tick: int = -1
	var death_reason: String = ""
	var min_food_dist_sq: float = 99999999.0
	var total_fitness: float = 0.0
	var breakdown: Dictionary = {}
	var genome: PackedFloat32Array

var bugs: Array[LiveBug] = []
var food_pellets: Array[Vector2] = []
var initial_food_template: Array[Vector2] = []
var hazards: Array = []
var history: Array = []

var arena_node = null
var rng = RandomNumberGenerator.new()

# Incremental live stats
var alive_count: int = 0
var hazard_deaths: int = 0
var starved_deaths: int = 0
var best_food: int = 0
var total_food: int = 0
var leader_idx: int = 0


func _init(p_arena) -> void:
	arena_node = p_arena
	rng.randomize()

	arena_width = 900.0
	arena_height = 600.0
	max_diag = sqrt(arena_width * arena_width + arena_height * arena_height)
	wall_margin = 20.0
	hazards = DEFAULT_HAZARDS

	hazard_positions.clear()
	hazard_radii.clear()
	hazard_radii_sq.clear()
	for h in hazards:
		var h_pos = Vector2(float(h.get("x", 0)), float(h.get("y", 0)))
		var r = float(h.get("radius", 40.0))
		hazard_positions.append(h_pos)
		hazard_radii.append(r)
		hazard_radii_sq.append(r * r)

	_generate_food_template()

	if is_instance_valid(arena_node):
		arena_node.configure_arena(arena_width, arena_height, hazards)

	current_generation = 0
	current_tick = 0
	history.clear()

	var initial_genomes: Array[PackedFloat32Array] = []
	for i in range(population_size):
		var g = PackedFloat32Array()
		g.resize(74)
		for j in range(74):
			g[j] = rng.randf_range(-0.6, 0.6)
		initial_genomes.append(g)

	start_generation(initial_genomes)


func _generate_food_template() -> void:
	initial_food_template.clear()
	var template_rng = RandomNumberGenerator.new()
	template_rng.seed = 42
	var f_margin = wall_margin + 15.0
	var num_h = hazard_positions.size()

	while initial_food_template.size() < food_count:
		var fx = template_rng.randf_range(f_margin, arena_width - f_margin)
		var fy = template_rng.randf_range(f_margin, arena_height - f_margin)
		var in_hazard = false
		for h_idx in range(num_h):
			if Vector2(fx, fy).distance_squared_to(hazard_positions[h_idx]) < (hazard_radii_sq[h_idx] + 100.0):
				in_hazard = true
				break
		if not in_hazard:
			initial_food_template.append(Vector2(fx, fy))


func start_generation(genomes: Array[PackedFloat32Array]) -> void:
	current_tick = 0
	alive_count = genomes.size()
	hazard_deaths = 0
	starved_deaths = 0
	best_food = 0
	total_food = 0
	leader_idx = 0

	# Reset food pellets
	food_pellets.clear()
	for f_pos in initial_food_template:
		food_pellets.append(f_pos)

	var f_margin = wall_margin + 10.0
	var num_hazards = hazard_positions.size()
	while food_pellets.size() < food_count:
		var fx = rng.randf_range(f_margin, arena_width - f_margin)
		var fy = rng.randf_range(f_margin, arena_height - f_margin)
		var in_hazard = false
		for h_idx in range(num_hazards):
			if Vector2(fx, fy).distance_squared_to(hazard_positions[h_idx]) < hazard_radii_sq[h_idx]:
				in_hazard = true
				break
		if not in_hazard:
			food_pellets.append(Vector2(fx, fy))

	if food_pellets.size() > food_count:
		food_pellets.resize(food_count)

	# Initialize Live Bugs (pure data structs, 0 node allocations)
	bugs.clear()
	var center = Vector2(arena_width * 0.5, arena_height * 0.5)
	var spawn_r = minf(arena_width, arena_height) * 0.35

	for i in range(genomes.size()):
		var bug = LiveBug.new()
		bug.id = i
		bug.genome = genomes[i]

		var angle = rng.randf_range(0.0, TAU)
		var r = rng.randf_range(20.0, spawn_r)
		bug.position = Vector2(
			clampf(center.x + r * cos(angle), wall_margin, arena_width - wall_margin),
			clampf(center.y + r * sin(angle), wall_margin, arena_height - wall_margin)
		)
		bug.heading = rng.randf_range(-PI, PI)
		bug.energy = 100.0
		bug.alive = true
		bug.food_eaten = 0
		bug.ticks_alive = 0
		bug.death_tick = -1
		bug.death_reason = ""
		bug.min_food_dist_sq = 99999999.0
		bug.total_fitness = 0.0

		bugs.append(bug)

	sync_visual_views()


func step_tick() -> bool:
	current_tick += 1
	var eat_dist_sq = 18.0 * 18.0
	var f_margin = wall_margin + 10.0
	var num_hazards = hazard_positions.size()
	var num_foods = food_pellets.size()
	var best_f = -1.0

	for i in range(bugs.size()):
		var bug = bugs[i]
		if not bug.alive:
			continue

		bug.ticks_alive += 1

		# 1. Sensors & Neural forward pass
		var sensors = _get_sensors(bug)
		var actions = _forward_nn(sensors, bug.genome)

		# 2. Kinematics
		bug.heading = wrapf(bug.heading + actions.x * 0.45, -PI, PI)
		var next_pos = bug.position + Vector2(cos(bug.heading), sin(bug.heading)) * (actions.y * 4.0)

		# Boundaries
		bug.position = Vector2(
			clampf(next_pos.x, wall_margin, arena_width - wall_margin),
			clampf(next_pos.y, wall_margin, arena_height - wall_margin)
		)

		# 3. Energy decay
		bug.energy -= bug_energy_decay_per_tick
		if bug.energy <= 0.0:
			bug.energy = 0.0
			bug.alive = false
			bug.death_tick = current_tick
			bug.death_reason = "starved"
			alive_count -= 1
			starved_deaths += 1
			continue

		# 4. Hazard collisions (squared distance)
		for h_idx in range(num_hazards):
			var comb_r = 10.0 + hazard_radii[h_idx]
			if bug.position.distance_squared_to(hazard_positions[h_idx]) < (comb_r * comb_r):
				bug.alive = false
				bug.death_tick = current_tick
				bug.death_reason = "hazard"
				alive_count -= 1
				hazard_deaths += 1
				break

		if not bug.alive:
			continue

		# 5. Food consumption
		for f_idx in range(num_foods):
			if bug.position.distance_squared_to(food_pellets[f_idx]) < eat_dist_sq:
				bug.food_eaten += 1
				total_food += 1
				if bug.food_eaten > best_food:
					best_food = bug.food_eaten
				bug.energy = minf(100.0, bug.energy + food_energy_gain)

				# Fast food respawn
				var respawned = false
				for attempt in range(15):
					var nx = rng.randf_range(f_margin, arena_width - f_margin)
					var ny = rng.randf_range(f_margin, arena_height - f_margin)
					var in_h = false
					for h_idx in range(num_hazards):
						if Vector2(nx, ny).distance_squared_to(hazard_positions[h_idx]) < hazard_radii_sq[h_idx]:
							in_h = true
							break
					if not in_h:
						food_pellets[f_idx] = Vector2(nx, ny)
						respawned = true
						break
				if not respawned:
					food_pellets[f_idx] = Vector2(arena_width * 0.5, arena_height * 0.5)

		# Track current leader
		var cur_fit = bug.food_eaten * 120.0 + bug.ticks_alive * 0.10
		if cur_fit > best_f:
			best_f = cur_fit
			leader_idx = i

	if current_tick >= ticks_per_generation:
		_finalize_and_evolve()
		return true

	return false


func sync_visual_views() -> void:
	if is_instance_valid(arena_node):
		arena_node.update_state(bugs, food_pellets)


func _get_sensors(bug: LiveBug) -> PackedFloat32Array:
	var s = PackedFloat32Array()
	s.resize(6)

	var min_f_sq = 99999999.0
	var nearest_f = Vector2.ZERO
	for f in food_pellets:
		var d_sq = bug.position.distance_squared_to(f)
		if d_sq < min_f_sq:
			min_f_sq = d_sq
			nearest_f = f

	var min_f = sqrt(min_f_sq)
	s[0] = clampf(min_f / max_diag, 0.0, 1.0)
	s[1] = wrapf((nearest_f - bug.position).angle() - bug.heading, -PI, PI) / PI
	if min_f_sq < bug.min_food_dist_sq:
		bug.min_food_dist_sq = min_f_sq

	var min_h_dist = 999999.0
	var nearest_h_pos = Vector2.ZERO
	var num_hazards = hazard_positions.size()
	for h_idx in range(num_hazards):
		var h_pos = hazard_positions[h_idx]
		var edge = maxf(0.0, bug.position.distance_to(h_pos) - hazard_radii[h_idx])
		if edge < min_h_dist:
			min_h_dist = edge
			nearest_h_pos = h_pos

	s[2] = clampf(min_h_dist / max_diag, 0.0, 1.0)
	s[3] = wrapf((nearest_h_pos - bug.position).angle() - bug.heading, -PI, PI) / PI if min_h_dist < 999990.0 else 0.0
	s[4] = clampf(bug.energy / 100.0, 0.0, 1.0)

	var d_l = bug.position.x
	var d_r = arena_width - bug.position.x
	var d_t = bug.position.y
	var d_b = arena_height - bug.position.y
	s[5] = clampf(minf(minf(d_l, d_r), minf(d_t, d_b)) / (minf(arena_width, arena_height) * 0.5), 0.0, 1.0)

	return s


static func _forward_nn(inputs: PackedFloat32Array, genome: PackedFloat32Array) -> Vector2:
	var in0 = inputs[0]
	var in1 = inputs[1]
	var in2 = inputs[2]
	var in3 = inputs[3]
	var in4 = inputs[4]
	var in5 = inputs[5]

	var h0 = tanh(genome[48] + in0*genome[0]  + in1*genome[8]  + in2*genome[16] + in3*genome[24] + in4*genome[32] + in5*genome[40])
	var h1 = tanh(genome[49] + in0*genome[1]  + in1*genome[9]  + in2*genome[17] + in3*genome[25] + in4*genome[33] + in5*genome[41])
	var h2 = tanh(genome[50] + in0*genome[2]  + in1*genome[10] + in2*genome[18] + in3*genome[26] + in4*genome[34] + in5*genome[42])
	var h3 = tanh(genome[51] + in0*genome[3]  + in1*genome[11] + in2*genome[19] + in3*genome[27] + in4*genome[35] + in5*genome[43])
	var h4 = tanh(genome[52] + in0*genome[4]  + in1*genome[12] + in2*genome[20] + in3*genome[28] + in4*genome[36] + in5*genome[44])
	var h5 = tanh(genome[53] + in0*genome[5]  + in1*genome[13] + in2*genome[21] + in3*genome[29] + in4*genome[37] + in5*genome[45])
	var h6 = tanh(genome[54] + in0*genome[6]  + in1*genome[14] + in2*genome[22] + in3*genome[30] + in4*genome[38] + in5*genome[46])
	var h7 = tanh(genome[55] + in0*genome[7]  + in1*genome[15] + in2*genome[23] + in3*genome[31] + in4*genome[39] + in5*genome[47])

	var net_turn = genome[72] + h0*genome[56] + h1*genome[58] + h2*genome[60] + h3*genome[62] + h4*genome[64] + h5*genome[66] + h6*genome[68] + h7*genome[70]
	var net_speed = genome[73] + h0*genome[57] + h1*genome[59] + h2*genome[61] + h3*genome[63] + h4*genome[65] + h5*genome[67] + h6*genome[69] + h7*genome[71]

	return Vector2(tanh(net_turn), 1.0 / (1.0 + exp(-clampf(net_speed, -20.0, 20.0))))


func _finalize_and_evolve() -> void:
	var total_fit = 0.0

	for bug in bugs:
		var food_score = bug.food_eaten * 120.0
		var surv_score = bug.ticks_alive * 0.10
		var haz_penalty = -40.0 if bug.death_reason == "hazard" else 0.0
		var prox_bonus = 0.0
		if max_diag > 0.0 and bug.min_food_dist_sq < 99999990.0:
			prox_bonus = minf(5.0, 5.0 * maxf(0.0, 1.0 - (sqrt(bug.min_food_dist_sq) / (max_diag * 0.5))))

		bug.breakdown = {
			"food_score": food_score,
			"survival_score": surv_score,
			"hazard_penalty": haz_penalty,
			"proximity_score": prox_bonus
		}
		bug.total_fitness = maxf(0.0, food_score + surv_score + haz_penalty + prox_bonus)
		total_fit += bug.total_fitness

	bugs.sort_custom(func(a, b): return a.total_fitness > b.total_fitness)

	var avg_fit = total_fit / float(bugs.size()) if not bugs.is_empty() else 0.0
	var best_bug = bugs[0]

	history.append({
		"generation": current_generation,
		"best_fitness": roundf(best_bug.total_fitness * 100.0) / 100.0,
		"avg_fitness": roundf(avg_fit * 100.0) / 100.0,
		"best_food": best_bug.food_eaten,
		"avg_food": roundf((float(total_food) / float(bugs.size())) * 10.0) / 10.0 if not bugs.is_empty() else 0.0,
		"best_ticks_alive": best_bug.ticks_alive,
		"breakdown": best_bug.breakdown
	})

	# Elitism
	var elite_count = mini(mini(5, bugs.size()), population_size)
	var next_genomes: Array[PackedFloat32Array] = []
	for i in range(elite_count):
		next_genomes.append(bugs[i].genome.duplicate())

	# Offspring
	while next_genomes.size() < population_size:
		var pA = _tournament_select()
		var pB = _tournament_select()
		var child = _crossover(pA, pB)
		_mutate(child)
		next_genomes.append(child)

	current_generation += 1
	start_generation(next_genomes)


func _tournament_select() -> PackedFloat32Array:
	var k = mini(3, bugs.size())
	var best_idx = rng.randi_range(0, bugs.size() - 1)
	for i in range(k - 1):
		var idx = rng.randi_range(0, bugs.size() - 1)
		if bugs[idx].total_fitness > bugs[best_idx].total_fitness:
			best_idx = idx
	return bugs[best_idx].genome


func _crossover(gA: PackedFloat32Array, gB: PackedFloat32Array) -> PackedFloat32Array:
	var child = PackedFloat32Array()
	child.resize(74)
	if rng.randf() > 0.75:
		return gA.duplicate()
	for i in range(74):
		child[i] = gA[i] if rng.randf() < 0.5 else gB[i]
	return child


func _mutate(g: PackedFloat32Array) -> void:
	if mutation_rate <= 0.0:
		return
	var passes = int(ceil(mutation_rate))
	var per_pass_rate = mutation_rate / float(passes)
	for p in range(passes):
		for i in range(74):
			if rng.randf() < per_pass_rate:
				g[i] += rng.randf_range(-0.25, 0.25)
			elif rng.randf() < (per_pass_rate * 0.2):
				g[i] = rng.randf_range(-0.8, 0.8)


func configure_and_restart(p_pop_size: int, p_ticks: int, p_mut_rate: float, p_decay: float, p_food_count: int = 40, p_food_gain: float = 40.0) -> void:
	population_size = maxi(1, p_pop_size)
	ticks_per_generation = maxi(1, p_ticks)
	mutation_rate = maxf(0.0, p_mut_rate)
	bug_energy_decay_per_tick = p_decay
	food_count = maxi(1, p_food_count)
	food_energy_gain = maxf(0.0, p_food_gain)

	current_generation = 0
	current_tick = 0
	history.clear()

	var initial_genomes: Array[PackedFloat32Array] = []
	for i in range(population_size):
		var g = PackedFloat32Array()
		g.resize(74)
		for j in range(74):
			g[j] = rng.randf_range(-0.6, 0.6)
		initial_genomes.append(g)

	start_generation(initial_genomes)


func get_live_stats() -> Dictionary:
	var leader = bugs[leader_idx] if leader_idx < bugs.size() else null
	var leader_fit = (leader.food_eaten * 120.0 + leader.ticks_alive * 0.10) if leader else 0.0
	var leader_energy = leader.energy if leader else 0.0
	var dead_cnt = bugs.size() - alive_count

	return {
		"alive_count": alive_count,
		"dead_count": dead_cnt,
		"hazard_deaths": hazard_deaths,
		"starved_deaths": starved_deaths,
		"leader_energy": roundf(leader_energy),
		"total_count": bugs.size(),
		"generation": current_generation,
		"tick": current_tick,
		"best_fitness": roundf(leader_fit * 10.0) / 10.0,
		"avg_fitness": roundf(leader_fit * 0.5 * 10.0) / 10.0,
		"best_food": best_food,
		"avg_food": roundf((float(total_food) / float(bugs.size())) * 10.0) / 10.0 if not bugs.is_empty() else 0.0,
		"breakdown": {
			"food_score": leader.food_eaten * 120.0 if leader else 0.0,
			"survival_score": roundf(leader.ticks_alive * 0.10 * 10.0) / 10.0 if leader else 0.0,
			"hazard_penalty": 0.0
		}
	}