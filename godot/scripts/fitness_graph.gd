class_name FitnessGraph
extends Control

## Visualizes evolutionary fitness progression (Best & Average)
## with area fill gradients, data beads, gridlines, and an active generation scrubber.

var history: Array = []
var current_gen: int = 0
var total_gens: int = 50

# Curated Graph Palette
const COLOR_BG = Color(0.06, 0.08, 0.11, 0.95)
const COLOR_BORDER = Color(0.18, 0.24, 0.35, 0.85)
const COLOR_GRID = Color(0.14, 0.18, 0.26, 0.5)
const COLOR_BEST_LINE = Color(1.0, 0.82, 0.22, 1.0)       # Amber Gold
const COLOR_BEST_FILL = Color(1.0, 0.82, 0.22, 0.12)      # Gradient Area Fill
const COLOR_AVG_LINE = Color(0.14, 0.86, 0.78, 1.0)       # Electric Cyan
const COLOR_SCRUBBER = Color(1.0, 1.0, 1.0, 0.9)
const COLOR_TEXT = Color(0.7, 0.78, 0.88, 1.0)

var font: Font


func _ready() -> void:
	font = ThemeDB.fallback_font


func set_history_data(hist: Array, total: int) -> void:
	history = hist
	total_gens = total
	queue_redraw()


func set_current_generation(gen_idx: int) -> void:
	current_gen = gen_idx
	queue_redraw()


func _draw() -> void:
	var w = size.x
	var h = size.y
	if w <= 10 or h <= 10:
		return

	var pad_left = 38.0
	var pad_right = 16.0
	var pad_top = 28.0
	var pad_bottom = 24.0

	var plot_w = w - pad_left - pad_right
	var plot_h = h - pad_top - pad_bottom

	# 1. Background Box with Subtle Border
	draw_rect(Rect2(0, 0, w, h), COLOR_BG, true)
	draw_rect(Rect2(0, 0, w, h), COLOR_BORDER, false, 1.5)

	# 2. Header & Legend
	if font:
		draw_string(font, Vector2(10, 18), "FITNESS PROGRESSION", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COLOR_TEXT)
		# Legend items
		var leg_x = w - 135
		draw_circle(Vector2(leg_x + 4, 13), 3.5, COLOR_BEST_LINE)
		draw_string(font, Vector2(leg_x + 12, 17), "Best", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COLOR_TEXT)

		draw_circle(Vector2(leg_x + 58, 13), 3.5, COLOR_AVG_LINE)
		draw_string(font, Vector2(leg_x + 66, 17), "Avg", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COLOR_TEXT)

	if history.is_empty():
		return

	# Calculate max fitness for scaling
	var max_val = 100.0
	for entry in history:
		var b = float(entry.get("best_fitness", 0.0))
		if b > max_val:
			max_val = b
	max_val = ceilf(max_val / 500.0) * 500.0

	# 3. Horizontal Grid lines & Value labels
	var num_h_lines = 4
	for i in range(num_h_lines + 1):
		var ratio = float(i) / float(num_h_lines)
		var gy = pad_top + plot_h * (1.0 - ratio)
		draw_line(Vector2(pad_left, gy), Vector2(w - pad_right, gy), COLOR_GRID, 1.0)
		if font and (i == 0 or i == num_h_lines / 2 or i == num_h_lines):
			var val_lbl = "%d" % int(max_val * ratio)
			draw_string(font, Vector2(4, gy + 4), val_lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, COLOR_TEXT)

	# 4. Vertical Grid lines & Generation labels
	var max_g = total_gens
	if max_g <= 0:
		max_g = max(10, history.size())

	var num_v_lines = 5
	for i in range(num_v_lines + 1):
		var ratio = float(i) / float(num_v_lines)
		var gx = pad_left + plot_w * ratio
		draw_line(Vector2(gx, pad_top), Vector2(gx, h - pad_bottom), COLOR_GRID, 1.0)
		if font and (i == 0 or i == num_v_lines):
			var gen_lbl = "G%d" % int(max_g * ratio) if total_gens > 0 else "G%d" % int(max_g * ratio)
			draw_string(font, Vector2(gx - 8, h - 8), gen_lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, COLOR_TEXT)

	# 5. Compile Plot Points
	var best_points = PackedVector2Array()
	var avg_points = PackedVector2Array()

	var num_entries = history.size()
	for i in range(num_entries):
		var frac_x = float(i) / float(max(1, max_g - 1))
		var px = pad_left + plot_w * frac_x

		var best_v = float(history[i].get("best_fitness", 0.0))
		var avg_v = float(history[i].get("avg_fitness", 0.0))

		var best_py = pad_top + plot_h * (1.0 - clampf(best_v / max_val, 0.0, 1.0))
		var avg_py = pad_top + plot_h * (1.0 - clampf(avg_v / max_val, 0.0, 1.0))

		best_points.append(Vector2(px, best_py))
		avg_points.append(Vector2(px, avg_py))

	# 6. Area Fill under Best Fitness curve
	if best_points.size() >= 2:
		var fill_poly = PackedVector2Array(best_points)
		var baseline_y = pad_top + plot_h
		fill_poly.append(Vector2(best_points[-1].x, baseline_y))
		fill_poly.append(Vector2(best_points[0].x, baseline_y))
		draw_colored_polygon(fill_poly, COLOR_BEST_FILL)

	# 7. Render Curve Lines
	if avg_points.size() >= 2:
		draw_polyline(avg_points, COLOR_AVG_LINE, 2.0, false)
	elif avg_points.size() == 1:
		draw_circle(avg_points[0], 3.0, COLOR_AVG_LINE)

	if best_points.size() >= 2:
		draw_polyline(best_points, COLOR_BEST_LINE, 2.5, false)
	elif best_points.size() == 1:
		draw_circle(best_points[0], 3.5, COLOR_BEST_LINE)

	# 8. Active Generation Scrubber Line & Glowing Bead
	var curr_frac = float(current_gen) / float(max(1, max_g - 1))
	var scrub_x = pad_left + plot_w * curr_frac
	draw_line(Vector2(scrub_x, pad_top), Vector2(scrub_x, h - pad_bottom), COLOR_SCRUBBER, 2.0)
	draw_circle(Vector2(scrub_x, pad_top + 4), 3.5, COLOR_SCRUBBER)

	if current_gen >= 0 and current_gen < best_points.size():
		var bead_pos = best_points[current_gen]
		draw_circle(bead_pos, 5.5, COLOR_BEST_LINE)
		draw_circle(bead_pos, 2.5, Color.WHITE)
