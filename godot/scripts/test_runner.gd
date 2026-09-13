extends SceneTree

const MainControllerScript = preload("res://scripts/main.gd")
const ArenaScript = preload("res://scripts/arena.gd")
const LiveSimulatorScript = preload("res://scripts/live_sim.gd")
const FitnessGraphScript = preload("res://scripts/fitness_graph.gd")

## Automated headless verification test for GeneticBugs Live Simulator.
## Validates scene graph construction, batch rendering state, decoupled stepping,
## kinematics, infinite generation mode, and parameter reconfiguration.


func _init() -> void:
	print("==================================================")
	print("       GENETICBUGS LIVE SIMULATOR VERIFICATION       ")
	print("==================================================")
	run_tests_async()


func run_tests_async() -> void:
	# 1. Test Scene Graph Loading
	print("[Test 1/4] Loading and instantiating main.tscn...")
	var main_scene = load("res://scenes/main.tscn")
	if main_scene == null:
		push_error("FAIL: Could not load res://scenes/main.tscn!")
		quit(1)
		return

	var main_node = main_scene.instantiate()
	if main_node == null:
		push_error("FAIL: Could not instantiate main.tscn!")
		quit(1)
		return

	root.add_child(main_node)

	# Wait 2 frames for scene tree to process enter_tree and ready
	await process_frame
	await process_frame

	# 2. Test Hierarchy and Arena Bug State
	print("[Test 2/4] Verifying node hierarchy and arena bug states...")
	if not main_node.has_node("Arena"):
		push_error("FAIL: Arena node missing from Main!")
		quit(1)
		return
	var arena = main_node.get_node("Arena")
	if main_node.live_sim == null:
		push_error("FAIL: LiveSimulator not initialized in main!")
		quit(1)
		return

	var bugs = main_node.live_sim.bugs
	print("  - Active bugs in simulation: %d" % bugs.size())
	if bugs.size() != 100:
		push_error("FAIL: Expected 100 bugs in live_sim, got %d" % bugs.size())
		quit(1)
		return
	if arena.bugs.size() != 100:
		push_error("FAIL: Expected 100 bugs synced to arena, got %d" % arena.bugs.size())
		quit(1)
		return

	# 3. Test Live Simulation Stepping & Kinematics
	print("[Test 3/4] Testing Live Simulation stepping & kinematics...")
	var initial_positions = []
	for b in main_node.live_sim.bugs:
		initial_positions.append(b.position)

	# Run 60 simulation ticks
	for t in range(60):
		main_node.live_sim.step_tick()
	main_node.live_sim.sync_visual_views()

	var moved_count = 0
	for i in range(main_node.live_sim.bugs.size()):
		if main_node.live_sim.bugs[i].position.distance_squared_to(initial_positions[i]) > 0.5:
			moved_count += 1

	print("  - Live bugs moved after 60 ticks: %d / %d" % [moved_count, main_node.live_sim.bugs.size()])
	if moved_count == 0:
		push_error("FAIL: No live bugs moved after 60 ticks!")
		quit(1)
		return

	var stats = main_node.live_sim.get_live_stats()
	print("  - Live stats after 60 ticks: Tick %d, Alive %d/%d, Best Food: %d" % [
		stats.get("tick", 0),
		stats.get("alive_count", 0),
		stats.get("total_count", 0),
		stats.get("best_food", 0)
	])

	# 4. Test Infinite Mode (-1) and Parameter Reconfiguration
	print("[Test 4/4] Testing Infinite Generation mode (-1) and dynamic tuning...")
	main_node.spin_max_gens.value = -1.0
	main_node._on_max_gens_changed(-1.0)
	print("  - GenLabel in infinite mode: %s" % main_node.gen_label.text)
	if not main_node.gen_label.text.contains("∞"):
		push_error("FAIL: GenLabel did not display infinite symbol!")
		quit(1)
		return

	# Reconfigure live sim with small population and short generation ticks
	main_node.spin_pop.value = 20.0
	main_node.spin_ticks.value = 30.0
	main_node.spin_food_count.value = 50.0
	main_node.spin_decay.value = 0.50
	main_node.init_live_simulation()

	print("  - Reconfigured live sim: Pop %d, Ticks %d, Food %d, Decay %.2f" % [
		main_node.live_sim.population_size,
		main_node.live_sim.ticks_per_generation,
		main_node.live_sim.food_count,
		main_node.live_sim.bug_energy_decay_per_tick
	])

	# Step through generation 0 into generation 1
	var advanced_to_gen1 = false
	for t in range(40):
		var finished = main_node.live_sim.step_tick()
		if finished:
			advanced_to_gen1 = true
			break

	if not advanced_to_gen1:
		push_error("FAIL: Live simulation did not finish generation within 40 ticks!")
		quit(1)
		return

	main_node._update_live_stats_display()
	print("  - Advanced into infinite Gen 2 without stopping. Status: %s" % main_node.gen_label.text)
	if not main_node.gen_label.text.contains("Gen: 02 / ∞"):
		push_error("FAIL: Did not advance to Gen 02 / ∞!")
		quit(1)
		return

	print(">> ALL LIVE SIMULATION TESTS PASSED SUCCESSFULLY! <<")
	print("==================================================")
	quit(0)
