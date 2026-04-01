# Kana-entity — liikkuu, hyppii, tuuppii muita kanoja
# Positio grid-koordinaateissa, sprite skaalataan chicken_layerissa
extends Node2D

enum State { IDLE, WALK, JUMP }

const CHICKEN_W := 5   # Törmäyslaatikon leveys (grid-pikseleitä)
const CHICKEN_H := 7   # Törmäyslaatikon korkeus
const WALK_SPEED := 0.3
const JUMP_SPEED := -2.2
const GRAVITY := 0.15
const MAX_FALL := 3.5
const PUSH_FORCE := 0.08

var grid_pos: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO
var state: State = State.IDLE
var state_timer: float = 1.0
var facing: int = 1  # 1 = oikea, -1 = vasen
var on_ground: bool = false
var alive: bool = true

var sprite: Sprite2D


func setup(tex: Texture2D, pos: Vector2) -> void:
	grid_pos = pos
	position = pos

	sprite = Sprite2D.new()
	sprite.texture = tex
	sprite.centered = true
	# Skaalaa sprite niin että korkeus ≈ CHICKEN_H grid-pikseliä
	var tex_h := float(tex.get_height())
	var s := float(CHICKEN_H) / tex_h
	sprite.scale = Vector2(s, s)
	# Sprite keskikohta kanan keskelle (jalat alareunassa)
	sprite.position = Vector2(0.0, -float(CHICKEN_H) / 2.0)
	add_child(sprite)


func update_chicken(grid: PackedByteArray, w: int, h: int, delta: float, others: Array) -> bool:
	if not alive:
		return false

	# AI-tilasiirtymä
	state_timer -= delta
	if state_timer <= 0.0:
		_pick_state()

	# Liike tilasta riippuen
	match state:
		State.IDLE:
			velocity.x *= 0.8
			if absf(velocity.x) < 0.01:
				velocity.x = 0.0
		State.WALK:
			velocity.x = float(facing) * WALK_SPEED
		State.JUMP:
			pass  # Hyppy asetettu _pick_state:ssä

	# Tarkista onko maassa ENNEN painovoimaa
	on_ground = _feet_on_ground(grid, w, h, grid_pos.x, grid_pos.y)

	# Painovoima — vain jos ei maassa
	if on_ground:
		if velocity.y > 0.0:
			velocity.y = 0.0
	else:
		velocity.y = minf(velocity.y + GRAVITY, MAX_FALL)

	# Liiku X — tarkista törmäys
	if absf(velocity.x) > 0.001:
		var new_x := grid_pos.x + velocity.x
		if not _body_collides(grid, w, h, new_x, grid_pos.y):
			grid_pos.x = new_x
		else:
			velocity.x = 0.0
			facing *= -1
			state_timer = 0.0  # Vaihda tilaa heti

	# Liiku Y — vain jos nopeus
	if absf(velocity.y) > 0.001:
		var new_y := grid_pos.y + velocity.y
		if not _body_collides(grid, w, h, grid_pos.x, new_y):
			grid_pos.y = new_y
		else:
			if velocity.y > 0.0:
				on_ground = true
				# Binäärihaulla tarkka pinta
				var safe_y := grid_pos.y
				var target_y := new_y
				for _i in 6:
					var mid := (safe_y + target_y) * 0.5
					if _body_collides(grid, w, h, grid_pos.x, mid):
						target_y = mid
					else:
						safe_y = mid
				grid_pos.y = floorf(safe_y)
			velocity.y = 0.0

	# Rajat
	grid_pos.x = clampf(grid_pos.x, float(CHICKEN_W) / 2.0 + 1.0, float(w) - float(CHICKEN_W) / 2.0 - 1.0)
	if grid_pos.y > float(h) + 20.0:
		alive = false
		queue_free()
		return false

	# Tuuppiminen — kanat työntävät toisiaan (pehmeästi)
	for other in others:
		if other == self or not other.alive:
			continue
		var dx: float = grid_pos.x - other.grid_pos.x
		var dy: float = grid_pos.y - other.grid_pos.y
		if absf(dx) < float(CHICKEN_W) * 0.9 and absf(dy) < float(CHICKEN_H) * 0.6:
			var push_dir: float = signf(dx) if absf(dx) > 0.5 else (1.0 if randf() > 0.5 else -1.0)
			velocity.x += push_dir * PUSH_FORCE
			other.velocity.x -= push_dir * PUSH_FORCE * 0.5

	# Tuli tappaa
	if _touches_material(grid, w, h, 5):  # MAT_FIRE
		kill()
		return false

	# Päivitä visuaali — pyöristä pikseliin (estää subpixel-tärinä)
	position = Vector2(roundf(grid_pos.x), roundf(grid_pos.y))
	sprite.flip_h = facing < 0

	return true


func kill() -> void:
	if not alive:
		return
	alive = false
	sprite.modulate = Color(1.0, 0.3, 0.3, 1.0)
	var tween := create_tween()
	tween.tween_property(sprite, "modulate:a", 0.0, 0.35)
	tween.parallel().tween_property(sprite, "scale", sprite.scale * 1.5, 0.35)
	tween.tween_callback(queue_free)


func _pick_state() -> void:
	if not on_ground:
		state = State.IDLE
		state_timer = 0.3
		return

	var r := randf()
	if r < 0.3:
		# Seiso paikallaan
		state = State.IDLE
		state_timer = randf_range(0.5, 2.5)
	elif r < 0.82:
		# Kävele
		state = State.WALK
		if randf() < 0.3:
			facing *= -1
		state_timer = randf_range(0.5, 2.0)
	else:
		# Hyppää
		state = State.JUMP
		velocity.y = JUMP_SPEED
		# Pieni vaakasuuntainen impulssi hypätessä
		velocity.x += float(facing) * 0.3
		state_timer = randf_range(0.3, 0.6)


# === TÖRMÄYSTARKISTUKSET ===

# Onko kanan jalkojen alla kiinteä maa?
func _feet_on_ground(grid: PackedByteArray, w: int, h: int, cx: float, cy: float) -> bool:
	var hw := CHICKEN_W / 2
	var foot_y := int(cy) + 1  # Yksi pikseli jalkojen alla
	if foot_y >= h:
		return true  # Ruudun pohja

	var x0 := int(cx) - hw
	var x1 := int(cx) + hw
	for gx in range(x0, x1 + 1):
		if gx >= 0 and gx < w:
			var mat := grid[foot_y * w + gx]
			if mat == 1 or mat == 3 or mat == 4 or mat == 8 or mat == 9:
				return true
	return false


# Kanan keho: cx ± CHICKEN_W/2, cy-CHICKEN_H+1 .. cy
func _body_collides(grid: PackedByteArray, w: int, h: int, cx: float, cy: float) -> bool:
	var hw := CHICKEN_W / 2
	var x0 := int(cx) - hw
	var x1 := int(cx) + hw
	var y0 := int(cy) - CHICKEN_H + 1
	var y1 := int(cy)

	for gy in range(y0, y1 + 1):
		for gx in range(x0, x1 + 1):
			if _is_solid(grid, w, h, gx, gy):
				return true
	return false


# Koskeeko kana annettua materiaalia
func _touches_material(grid: PackedByteArray, w: int, h: int, mat: int) -> bool:
	var hw := CHICKEN_W / 2
	var x0 := int(grid_pos.x) - hw - 1
	var x1 := int(grid_pos.x) + hw + 1
	var y0 := int(grid_pos.y) - CHICKEN_H
	var y1 := int(grid_pos.y) + 1

	for gy in range(y0, y1 + 1):
		for gx in range(x0, x1 + 1):
			if gx >= 0 and gx < w and gy >= 0 and gy < h:
				if grid[gy * w + gx] == mat:
					return true
	return false


func _is_solid(grid: PackedByteArray, w: int, h: int, gx: int, gy: int) -> bool:
	if gx < 0 or gx >= w:
		return true  # Seinät
	if gy < 0:
		return true  # Katto
	if gy >= h:
		return true  # Lattia
	var mat := grid[gy * w + gx]
	# Kiinteät: hiekka(1), kivi(3), puu(4), tuhka(8), putoava puu(9)
	return mat == 1 or mat == 3 or mat == 4 or mat == 8 or mat == 9
