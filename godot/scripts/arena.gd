class_name ArenaView
extends Node2D

## Renders the arena floor, boundaries, hazard zones,
## nutrient pellets, and active bugs via unified 2D batch drawing.

var arena_width: float = 900.0
var arena_height: float = 600.0
var hazards: Array = []
var food_pellets: Array = []
var bugs: Array = []

# Theme Palette
const COLOR_BG = Color(0.05, 0.065, 0.09, 1.0)
const COLOR_BORDER = Color(0.13, 0.82, 0.93, 0.9)
const COLOR_CORNER = Color(1.0, 0.84, 0.25, 0.9)
const COLOR_HAZARD_CORE = Color(0.85, 0.12, 0.22, 0.32)
const COLOR_HAZARD_MID = Color(0.95, 0.22, 0.28, 0.18)
const COLOR_HAZARD_RING = Color(1.0, 0.32, 0.4, 0.85)
const COLOR_HAZARD_ACCENT = Color(1.0, 0.6, 0.2, 0.7)
const COLOR_FOOD_HALO = Color(0.15, 0.95, 0.55, 0.25)
const COLOR_FOOD_MID = Color(0.25, 0.98, 0.65, 0.85)
const COLOR_FOOD_CORE = Color(0.9, 1.0, 0.95, 1.0)
const COLOR_BUG_ALIVE = Color(0.96, 0.65, 0.12)
const COLOR_BUG_DEAD = Color(0.96, 0.65, 0.12, 0.25)
const COLOR_EYE = Color(0.1, 0.12, 0.15)


func configure_arena(w: float, h: float, p_hazards: Array) -> void:
	arena_width = w
	arena_height = h
	hazards = p_hazards
	queue_redraw()


func update_state(p_bugs: Array, p_food: Array) -> void:
	bugs = p_bugs
	food_pellets = p_food
	queue_redraw()


func _draw() -> void:
	var arena_rect = Rect2(0, 0, arena_width, arena_height)

	# 1. Floor background & border
	draw_rect(arena_rect, COLOR_BG, true)
	draw_rect(arena_rect, COLOR_BORDER, false, 1.5)

	# 2. Corner brackets
	var bl = 14.0
	draw_line(Vector2(0, 0), Vector2(bl, 0), COLOR_CORNER, 2.0)
	draw_line(Vector2(0, 0), Vector2(0, bl), COLOR_CORNER, 2.0)
	draw_line(Vector2(arena_width, 0), Vector2(arena_width - bl, 0), COLOR_CORNER, 2.0)
	draw_line(Vector2(arena_width, 0), Vector2(arena_width, bl), COLOR_CORNER, 2.0)
	draw_line(Vector2(0, arena_height), Vector2(bl, arena_height), COLOR_CORNER, 2.0)
	draw_line(Vector2(0, arena_height), Vector2(0, arena_height - bl), COLOR_CORNER, 2.0)
	draw_line(Vector2(arena_width, arena_height), Vector2(arena_width - bl, arena_height), COLOR_CORNER, 2.0)
	draw_line(Vector2(arena_width, arena_height), Vector2(arena_width, arena_height - bl), COLOR_CORNER, 2.0)

	# 3. Hazards
	for h in hazards:
		var center = Vector2(float(h.get("x", 0)), float(h.get("y", 0)))
		var rad = float(h.get("radius", 40.0))
		draw_circle(center, rad, COLOR_HAZARD_MID)
		draw_circle(center, rad * 0.7, COLOR_HAZARD_CORE)
		draw_arc(center, rad, 0, TAU, 32, COLOR_HAZARD_RING, 2.0)
		draw_arc(center, rad * 0.5, 0, TAU, 20, COLOR_HAZARD_ACCENT, 1.2)
		draw_line(center - Vector2(8, 0), center + Vector2(8, 0), COLOR_HAZARD_RING, 1.8)
		draw_line(center - Vector2(0, 8), center + Vector2(0, 8), COLOR_HAZARD_RING, 1.8)
		draw_circle(center, 2.5, Color.WHITE)

	# 4. Food Pellets
	for pos in food_pellets:
		draw_circle(pos, 8.5, COLOR_FOOD_HALO)
		draw_circle(pos, 4.2, COLOR_FOOD_MID)
		draw_circle(pos, 1.8, COLOR_FOOD_CORE)

	# 5. Bugs (hardware-accelerated batch drawing)
	for b in bugs:
		var pos = b.position
		var col = COLOR_BUG_ALIVE if b.alive else COLOR_BUG_DEAD

		draw_circle(pos, 8.0, col)
		draw_arc(pos, 8.0, 0, TAU, 16, col.lightened(0.25), 1.0)

		var dir = Vector2(cos(b.heading), sin(b.heading))
		var perp = Vector2(-dir.y, dir.x)
		var tip = pos + dir * 12.0
		var p1 = pos + dir * 6.0 + perp * 4.5
		var p2 = pos + dir * 6.0 - perp * 4.5
		draw_colored_polygon(PackedVector2Array([tip, p1, p2]), col.lightened(0.2))

		var eye_fwd = dir * 4.0
		var eye_side = perp * 3.2
		draw_circle(pos + eye_fwd + eye_side, 1.6, COLOR_EYE)
		draw_circle(pos + eye_fwd - eye_side, 1.6, COLOR_EYE)