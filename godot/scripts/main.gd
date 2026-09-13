class_name MainController
extends Node2D

## Main controller: coordinates the real-time live simulation,
## arena display, menu bar, and graphs/stats panel.

const LiveSimulatorClass = preload("res://scripts/live_sim.gd")
const SPEEDS: Array = [
	["0.5x", 0.5], ["1.0x", 1.0], ["2.0x", 2.0], ["4.0x", 4.0],
	["8.0x", 8.0], ["16.0x", 16.0], ["32.0x", 32.0], ["64.0x", 64.0], ["Uncapped", 200.0]
]

@onready var arena = $Arena
@onready var stats_overlay = $UI/StatsOverlay

# Menu Bar controls
@onready var btn_play: Button = $UI/TopMenuBar/Margin/HBox/BtnPlay
@onready var speed_options: OptionButton = $UI/TopMenuBar/Margin/HBox/SpeedOptions
@onready var gen_label: Label = $UI/TopMenuBar/Margin/HBox/GenLabel
@onready var tick_label: Label = $UI/TopMenuBar/Margin/HBox/TickLabel
@onready var lbl_alive: Label = $UI/TopMenuBar/Margin/HBox/AliveLabel
@onready var lbl_dead: Label = $UI/TopMenuBar/Margin/HBox/DeadLabel
@onready var btn_stats_toggle: Button = $UI/TopMenuBar/Margin/HBox/BtnStatsToggle

# Graphs & Stats Panel items
@onready var fitness_graph = $UI/StatsOverlay/Margin/VBox/FitnessGraph
@onready var lbl_best_fit: Label = $UI/StatsOverlay/Margin/VBox/Metrics/RowBest/Val
@onready var lbl_avg_fit: Label = $UI/StatsOverlay/Margin/VBox/Metrics/RowAvg/Val
@onready var lbl_best_food: Label = $UI/StatsOverlay/Margin/VBox/Metrics/RowFood/Val
@onready var lbl_leader_energy: Label = $UI/StatsOverlay/Margin/VBox/Metrics/RowEnergy/Val
@onready var lbl_casualties: Label = $UI/StatsOverlay/Margin/VBox/Metrics/RowCasualties/Val
@onready var lbl_breakdown: Label = $UI/StatsOverlay/Margin/VBox/LblBreakdown

# Live Evolution Config Controls
@onready var live_config_box = $UI/StatsOverlay/Margin/VBox/LiveConfigBox
@onready var spin_max_gens: SpinBox = $UI/StatsOverlay/Margin/VBox/LiveConfigBox/RowMaxGens/SpinMaxGens
@onready var spin_pop: SpinBox = $UI/StatsOverlay/Margin/VBox/LiveConfigBox/RowPop/SpinPop
@onready var spin_ticks: SpinBox = $UI/StatsOverlay/Margin/VBox/LiveConfigBox/RowTicks/SpinTicks
@onready var spin_mut: SpinBox = $UI/StatsOverlay/Margin/VBox/LiveConfigBox/RowMut/SpinMut
@onready var spin_decay: SpinBox = $UI/StatsOverlay/Margin/VBox/LiveConfigBox/RowDecay/SpinDecay
@onready var spin_food_count: SpinBox = $UI/StatsOverlay/Margin/VBox/LiveConfigBox/RowFoodCount/SpinFoodCount
@onready var spin_food_gain: SpinBox = $UI/StatsOverlay/Margin/VBox/LiveConfigBox/RowFoodGain/SpinFoodGain
@onready var btn_apply_live: Button = $UI/StatsOverlay/Margin/VBox/LiveConfigBox/BtnApplyLive

var is_playing: bool = true
var playback_speed: float = 1.0
var ticks_per_second: float = 60.0
var ticks_per_generation: int = 600

var live_sim = null
var live_max_generations: int = 100
var live_tick_accum: float = 0.0


func _ready() -> void:
	arena.position = Vector2.ZERO
	arena.scale = Vector2(1280.0 / 900.0, 720.0 / 600.0)

	if speed_options:
		speed_options.clear()
		for i in SPEEDS.size():
			speed_options.add_item(SPEEDS[i][0], i)
			speed_options.set_item_metadata(i, SPEEDS[i][1])
		speed_options.select(1)

	setup_ui_signals()
	init_live_simulation()
	_update_play_pause_button()


func setup_ui_signals() -> void:
	btn_play.pressed.connect(toggle_play)
	if btn_stats_toggle:
		btn_stats_toggle.pressed.connect(toggle_stats_overlay)
	if speed_options:
		speed_options.item_selected.connect(func(idx): playback_speed = float(speed_options.get_item_metadata(idx)))
	if btn_apply_live:
		btn_apply_live.pressed.connect(init_live_simulation)

	if spin_max_gens:
		spin_max_gens.value_changed.connect(_on_max_gens_changed)
	if spin_ticks:
		spin_ticks.value_changed.connect(_on_ticks_changed)
	if spin_pop:
		spin_pop.value_changed.connect(func(v): if live_sim: live_sim.population_size = maxi(1, int(v)))
	if spin_mut:
		spin_mut.value_changed.connect(func(v): if live_sim: live_sim.mutation_rate = maxf(0.0, v / 100.0))
	if spin_decay:
		spin_decay.value_changed.connect(func(v): if live_sim: live_sim.bug_energy_decay_per_tick = v)
	if spin_food_count:
		spin_food_count.value_changed.connect(func(v): if live_sim: live_sim.food_count = maxi(1, int(v)))
	if spin_food_gain:
		spin_food_gain.value_changed.connect(func(v): if live_sim: live_sim.food_energy_gain = maxf(0.0, v))


func _process(delta: float) -> void:
	if not is_playing or not live_sim:
		return

	live_tick_accum += delta * ticks_per_second * playback_speed
	var max_substeps = 5000 if playback_speed > 64.0 else 1000
	var substeps = 0
	var start_msec = Time.get_ticks_msec()

	while live_tick_accum >= 1.0 and substeps < max_substeps:
		live_tick_accum -= 1.0
		substeps += 1
		if live_sim.step_tick():
			fitness_graph.set_history_data(live_sim.history, live_max_generations)
			fitness_graph.set_current_generation(live_sim.current_generation - 1)
			if live_max_generations > 0 and live_sim.current_generation >= live_max_generations:
				is_playing = false
				_update_play_pause_button()
				gen_label.text = "Gen: %02d / %02d (Finished)" % [live_sim.current_generation, live_max_generations]
				break
			_format_gen_label()

		if substeps % 32 == 0 and (Time.get_ticks_msec() - start_msec) > 15:
			break

	live_sim.sync_visual_views()
	_update_live_stats_display()


func _format_gen_label() -> void:
	if live_max_generations > 0 and live_sim.current_generation >= live_max_generations:
		gen_label.text = "Gen: %02d / %02d (Finished)" % [live_sim.current_generation, live_max_generations]
	elif live_max_generations == -1:
		gen_label.text = "Gen: %02d / ∞" % [live_sim.current_generation + 1]
	else:
		gen_label.text = "Gen: %02d / %02d" % [live_sim.current_generation + 1, live_max_generations]


func _update_live_stats_display() -> void:
	if not live_sim:
		return

	var stats = live_sim.get_live_stats()
	tick_label.text = "Tick: %03d / %03d" % [int(stats.get("tick", 0)), ticks_per_generation]
	_format_gen_label()

	if lbl_alive: lbl_alive.text = "Alive: %d" % int(stats.get("alive_count", 0))
	if lbl_dead: lbl_dead.text = "Dead: %d" % int(stats.get("dead_count", 0))
	if lbl_best_fit: lbl_best_fit.text = str(stats.get("best_fitness", 0.0))
	if lbl_avg_fit: lbl_avg_fit.text = str(stats.get("avg_fitness", 0.0))
	if lbl_best_food: lbl_best_food.text = "%d (Avg: %.1f)" % [int(stats.get("best_food", 0)), float(stats.get("avg_food", 0.0))]
	if lbl_leader_energy: lbl_leader_energy.text = "%d / 100" % int(stats.get("leader_energy", 0))
	if lbl_casualties:
		lbl_casualties.text = "Haz: %d | Starv: %d" % [int(stats.get("hazard_deaths", 0)), int(stats.get("starved_deaths", 0))]

	if lbl_breakdown:
		var bd = stats.get("breakdown", {})
		lbl_breakdown.text = "Food: +%.1f | Surv: +%.1f | Haz: %.1f" % [
			float(bd.get("food_score", 0.0)),
			float(bd.get("survival_score", 0.0)),
			float(bd.get("hazard_penalty", 0.0))
		]


func init_live_simulation() -> void:
	var p_gens = int(spin_max_gens.value) if spin_max_gens else 100
	live_max_generations = -1 if p_gens <= 0 else p_gens
	if spin_max_gens:
		spin_max_gens.suffix = " (∞)" if live_max_generations == -1 else ""

	var p_size = int(spin_pop.value) if spin_pop else 100
	ticks_per_generation = int(spin_ticks.value) if spin_ticks else 600
	var p_mut = (float(spin_mut.value) / 100.0) if spin_mut else 0.10
	var p_decay = float(spin_decay.value) if spin_decay else 0.35
	var p_food_count = int(spin_food_count.value) if spin_food_count else 40
	var p_food_gain = float(spin_food_gain.value) if spin_food_gain else 40.0

	if not live_sim:
		live_sim = LiveSimulatorClass.new(arena)
	live_sim.configure_and_restart(p_size, ticks_per_generation, p_mut, p_decay, p_food_count, p_food_gain)
	live_tick_accum = 0.0
	fitness_graph.set_history_data([], live_max_generations)

	_format_gen_label()
	tick_label.text = "Tick: 000 / %03d" % ticks_per_generation
	_update_live_stats_display()


func toggle_play() -> void:
	is_playing = not is_playing
	_update_play_pause_button()


func _update_play_pause_button() -> void:
	if btn_play:
		btn_play.text = "Pause" if is_playing else "Play"


func toggle_stats_overlay() -> void:
	if stats_overlay:
		stats_overlay.visible = not stats_overlay.visible


func _on_max_gens_changed(val: float) -> void:
	live_max_generations = -1 if int(val) <= 0 else int(val)
	if spin_max_gens:
		spin_max_gens.suffix = " (∞)" if live_max_generations == -1 else ""
	_update_live_stats_display()


func _on_ticks_changed(val: float) -> void:
	ticks_per_generation = maxi(1, int(val))
	if live_sim:
		live_sim.ticks_per_generation = ticks_per_generation
	_update_live_stats_display()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_select") or (event is InputEventKey and event.pressed and event.keycode == KEY_SPACE):
		toggle_play()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and (event.keycode == KEY_H or event.keycode == KEY_TAB):
		toggle_stats_overlay()
		get_viewport().set_input_as_handled()
