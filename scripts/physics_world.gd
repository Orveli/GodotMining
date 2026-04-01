# Fysiikkamaailma — hallinnoi rigid body -kappaleita
# Erase all → forces → integrate → env collision → body-body → write all
class_name PhysicsWorld

const GRAVITY := Vector2(0, 0.6)  # pikseliä/frame²
const MIN_BODY_SIZE := 4  # Alle tämän → mursketta
const FRICTION := 0.2  # Vähemmän kitkaa = luonnollisempi liuku
const RESTITUTION := 0.15
const SUBSTEPS := 4
const TIPPING_TORQUE := 0.01  # Vahvempi kallistus
const ANGULAR_DAMPING := 0.92  # Enemmän vaimennusta = vakaampi pysähdys
const MAX_VELOCITY := 8.0  # Maksiminopeus

var bodies: Dictionary = {}  # body_id → RigidBodyData
const MAX_BODY_ID := 65535  # Kierrätetään ID:t ylivuodon estämiseksi
var next_body_id: int = 1
var body_map: PackedInt32Array  # cell → body_id (0 = ei kappaletta)
var map_w: int = 0
var map_h: int = 0
var force_damage_check := false  # Pakota vauriotarkistus (räjähdyksen jälkeen)


func _ensure_body_map(w: int, h: int) -> void:
	if map_w != w or map_h != h:
		map_w = w
		map_h = h
		body_map = PackedInt32Array()
		body_map.resize(w * h)
		body_map.fill(0)


func create_body(world_pixels: Array[Vector2i], seeds: PackedByteArray, mat: int) -> RigidBodyData:
	if world_pixels.size() < MIN_BODY_SIZE:
		return null
	var body := RigidBodyData.new()
	body.body_id = next_body_id
	body.material = mat
	body.calculate_from_world_pixels(world_pixels, seeds)
	bodies[next_body_id] = body
	# Kierrätä ID:t — etsi seuraava vapaa
	next_body_id += 1
	if next_body_id > MAX_BODY_ID:
		next_body_id = 1
	while bodies.has(next_body_id) and next_body_id <= MAX_BODY_ID:
		next_body_id += 1
		if next_body_id > MAX_BODY_ID:
			next_body_id = 1
	return body


func remove_body(body_id: int) -> void:
	bodies.erase(body_id)


# === RÄJÄHDYSIMPULSSIT ===

func apply_explosion_impulse(center: Vector2, radius: float, force: float) -> void:
	force_damage_check = true  # Pakota vauriotarkistus seuraavalla framella
	var effect_radius := radius * 2.0
	for body_id in bodies:
		var body: RigidBodyData = bodies[body_id]
		if body.is_static:
			continue
		var dir := body.position - center
		var dist := dir.length()
		if dist > effect_radius or dist < 0.01:
			continue
		dir = dir.normalized()
		# Voimakkuus laskee etäisyyden mukaan
		var strength := force * (1.0 - dist / effect_radius) / maxf(body.mass, 1.0)
		strength = minf(strength, MAX_VELOCITY * 0.8)
		body.velocity += dir * strength
		# Pyöritys
		body.angular_velocity += randf_range(-0.15, 0.15) * strength
		body.wake_up()


# === GRAVITY GUN ===

func apply_attraction(target: Vector2, radius: float, strength: float) -> void:
	for body_id in bodies:
		var body: RigidBodyData = bodies[body_id]
		if body.is_static:
			continue
		var dir := target - body.position
		var dist := dir.length()
		if dist > radius or dist < 1.0:
			continue
		dir = dir.normalized()
		# Vetovoima laskee etäisyyden mukaan, massan mukaan
		var pull := strength * (1.0 - dist / radius) / maxf(body.mass, 1.0) * 2.0
		pull = minf(pull, MAX_VELOCITY * 0.5)
		body.velocity += dir * pull
		body.wake_up()


func apply_throw(origin: Vector2, radius: float, throw_velocity: Vector2) -> void:
	for body_id in bodies:
		var body: RigidBodyData = bodies[body_id]
		if body.is_static:
			continue
		var dist := (body.position - origin).length()
		if dist > radius:
			continue
		var strength := (1.0 - dist / radius) / maxf(body.mass, 1.0) * 10.0
		body.velocity += throw_velocity * strength
		body.angular_velocity += randf_range(-0.1, 0.1) * strength
		body.wake_up()


# === PÄÄSILMUKKA ===
# Semi-sekventiaalinen: erase all → voimat → prosessoi alhaalta ylöspäin (erase→move→write)
# Jokainen kappale näkee jo käsiteltyjen kappaleiden pikselit gridissä

func step(grid: PackedByteArray, color_seed: PackedByteArray, w: int, h: int) -> void:
	_ensure_body_map(w, h)

	# Kerää aktiiviset kappaleet
	var active_ids: Array[int] = []
	for body_id in bodies:
		var body: RigidBodyData = bodies[body_id]
		if not body.is_sleeping and not body.is_static:
			active_ids.append(body_id)

	if active_ids.is_empty():
		return

	# Järjestä Y:n mukaan (alimmat ensin → ne laskeutuvat ja kirjoittavat pikselinsä ensin)
	active_ids.sort_custom(func(a_id: int, b_id: int) -> bool:
		return bodies[a_id].position.y > bodies[b_id].position.y
	)

	# Prosessoi jokainen kappale täysin sekventiaalisesti (alhaalta ylöspäin):
	# erase → voimat → tipping → integrointi → törmäys → write
	# Jokainen kappale näkee kaikki muut kappaleet gridissä
	for body_id in active_ids:
		var body: RigidBodyData = bodies[body_id]

		# 1. Poista tämän kappaleen pikselit
		_erase_body(body, grid, color_seed, w, h)

		# 2. Voimat (gridi sisältää muut kappaleet → tipping toimii)
		body.velocity += GRAVITY
		body.angular_velocity *= ANGULAR_DAMPING
		if body.velocity.length() > MAX_VELOCITY:
			body.velocity = body.velocity.normalized() * MAX_VELOCITY
		_apply_tipping_torque(body, grid, w, h)

		# 3. Integrointi
		var old_pos := body.position
		var old_angle := body.angle
		body.position = old_pos + body.velocity
		body.angle = old_angle + body.angular_velocity

		# Ympäristötörmäys (näkee maasto + staattiset + jo kirjoitetut kappaleet)
		var collision := _find_env_collision(body, grid, w, h)
		if collision.hit:
			var t_min := 0.0
			var t_max := 1.0
			for _s in SUBSTEPS:
				var t_mid := (t_min + t_max) * 0.5
				body.position = old_pos + body.velocity * t_mid
				body.angle = old_angle + body.angular_velocity * t_mid
				if _check_env_collision(body, grid, w, h):
					t_max = t_mid
				else:
					t_min = t_mid
			body.position = old_pos + body.velocity * t_min
			body.angle = old_angle + body.angular_velocity * t_min

			var normal := collision.normal
			if normal.length_squared() > 0.0:
				normal = normal.normalized()
				var vn := body.velocity.dot(normal)
				if vn < 0.0:
					body.velocity -= normal * vn * (1.0 + RESTITUTION)
					var tangent := Vector2(-normal.y, normal.x)
					var vt := body.velocity.dot(tangent)
					body.velocity -= tangent * vt * FRICTION
					var r := collision.contact_point - body.position
					var torque := r.x * normal.y - r.y * normal.x
					body.angular_velocity += torque * 0.02 / maxf(body.inertia, 1.0)
					# Rinteessä liukuminen
					var slope_tangent := Vector2(-normal.y, normal.x)
					var gravity_along_slope := GRAVITY.dot(slope_tangent)
					if absf(gravity_along_slope) > 0.05:
						body.velocity += slope_tangent * gravity_along_slope * 0.3
			else:
				body.velocity *= 0.1
				body.angular_velocity *= 0.5

			# Herätä nukkuva kappale jos osuttiin
			if collision.hit_body_id > 0 and bodies.has(collision.hit_body_id):
				var hit_body: RigidBodyData = bodies[collision.hit_body_id]
				if hit_body.is_sleeping and not hit_body.is_static:
					# Poista nukkuvan pikselit, herätä, siirrä voimaa
					_erase_body(hit_body, grid, color_seed, w, h)
					hit_body.wake_up()
					var impulse := body.velocity * minf(body.mass, 20.0) * 0.2
					hit_body.velocity += impulse / maxf(hit_body.mass, 1.0)
					_write_body(hit_body, grid, color_seed, w, h)

		# Nukahtamistarkistus ENNEN kirjoitusta
		var was_sleeping := body.is_sleeping
		body.update_sleep()

		# Kirjoita tämä kappale gridiin — seuraavat kappaleet näkevät sen
		_write_body(body, grid, color_seed, w, h)

		# Jos kappale juuri nukahti, ei tarvitse erikoiskäsittelyä
		# (update_sleep snappasi position, write käyttää snapattua pos)


# === AUKOTON RASTERIZATION ===
# Forward transform + aukkojen täyttö vierekkäisten pikselien välillä
# Palauttaa Dictionary[Vector2i, int]: maailmapos → lokaali-indeksi (-1 = aukontäyttö)

func _get_filled_world_pixels(body: RigidBodyData) -> Dictionary:
	body._ensure_rot_cache()
	var result := {}
	var local_to_world := {}
	var px := roundi(body.position.x)
	var py := roundi(body.position.y)

	for i in body.local_pixels.size():
		var rot := body._rot_cache[i]
		var wp := Vector2i(rot.x + px, rot.y + py)
		result[wp] = i
		local_to_world[body.local_pixels[i]] = wp

	# Aukontäyttö — sama kuin ennen, käyttää local_to_world-mappingia
	var local_set := {}
	for lp in body.local_pixels:
		local_set[lp] = true

	for lp in body.local_pixels:
		for dir in [Vector2i(1, 0), Vector2i(0, 1)]:
			var neighbor: Vector2i = lp + dir
			if not local_set.has(neighbor):
				continue
			if not local_to_world.has(neighbor):
				continue
			var wp_a: Vector2i = local_to_world[lp]
			var wp_b: Vector2i = local_to_world[neighbor]
			var mdist := absi(wp_b.x - wp_a.x) + absi(wp_b.y - wp_a.y)
			if mdist > 1:
				var mid1 := Vector2i(wp_a.x, wp_b.y)
				var mid2 := Vector2i(wp_b.x, wp_a.y)
				if not result.has(mid1):
					result[mid1] = -1
				if mid2 != mid1 and not result.has(mid2):
					result[mid2] = -1

	return result


# === APUFUNKTIOT ===

func _is_liquid(mat: int) -> bool:
	return mat == 2 or mat == 6 or mat == 7  # MAT_WATER, MAT_OIL, MAT_STEAM


# === ERASE / WRITE ===

func _erase_body(body: RigidBodyData, grid: PackedByteArray, seed: PackedByteArray, w: int, h: int) -> void:
	var filled := _get_filled_world_pixels(body)
	for wp_key in filled:
		var wp: Vector2i = wp_key
		if wp.x >= 0 and wp.x < w and wp.y >= 0 and wp.y < h:
			var idx: int = wp.y * w + wp.x
			if body_map[idx] == body.body_id:
				grid[idx] = 0
				seed[idx] = 0
				body_map[idx] = 0


func _write_body(body: RigidBodyData, grid: PackedByteArray, seed: PackedByteArray, w: int, h: int) -> int:
	var filled := _get_filled_world_pixels(body)
	var written := 0
	for wp_key in filled:
		var wp: Vector2i = wp_key
		if wp.x >= 0 and wp.x < w and wp.y >= 0 and wp.y < h:
			var idx: int = wp.y * w + wp.x
			if grid[idx] == 0 or _is_liquid(grid[idx]):
				# Syrjäytä neste viereiseen tyhjään soluun
				if _is_liquid(grid[idx]):
					var liq_mat := grid[idx]
					var liq_seed := seed[idx]
					for disp in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, -1), Vector2i(1, -1)]:
						var np := Vector2i(wp.x + disp.x, wp.y + disp.y)
						if np.x >= 0 and np.x < w and np.y >= 0 and np.y < h:
							var nidx := np.y * w + np.x
							if grid[nidx] == 0 and body_map[nidx] == 0:
								grid[nidx] = liq_mat
								seed[nidx] = liq_seed
								break
				grid[idx] = body.material
				body_map[idx] = body.body_id
				var pi: int = filled[wp]
				if pi >= 0 and pi < body.pixel_seeds.size():
					seed[idx] = body.pixel_seeds[pi]
				elif body.pixel_seeds.size() > 0:
					# Aukontäytön seed — ota naapurilta
					seed[idx] = body.pixel_seeds[0]
				written += 1
	return maxi(body.local_pixels.size() - written, 0)


# === YMPÄRISTÖTÖRMÄYS ===

class CollisionResult:
	var hit: bool = false
	var normal: Vector2 = Vector2.ZERO
	var contact_point: Vector2 = Vector2.ZERO
	var hit_body_id: int = 0  # Nukkuvan/staattisen kappaleen ID


func _check_env_collision(body: RigidBodyData, grid: PackedByteArray, w: int, h: int) -> bool:
	var world_pixels := body.get_world_pixels()
	for wp in world_pixels:
		if wp.x < 0 or wp.x >= w or wp.y < 0 or wp.y >= h:
			return true
		var mat := grid[wp.y * w + wp.x]
		if mat != 0 and not _is_liquid(mat):
			return true
	return false


func _find_env_collision(body: RigidBodyData, grid: PackedByteArray, w: int, h: int) -> CollisionResult:
	var result := CollisionResult.new()
	var world_pixels := body.get_world_pixels()
	var collision_points: Array[Vector2] = []
	var accumulated_normal := Vector2.ZERO

	for wp in world_pixels:
		var colliding := false

		if wp.x < 0 or wp.x >= w or wp.y < 0 or wp.y >= h:
			colliding = true
			if wp.x < 0: accumulated_normal += Vector2(1, 0)
			elif wp.x >= w: accumulated_normal += Vector2(-1, 0)
			if wp.y < 0: accumulated_normal += Vector2(0, 1)
			elif wp.y >= h: accumulated_normal += Vector2(0, -1)
		else:
			var idx := wp.y * w + wp.x
			var hit_mat := grid[idx]
			if hit_mat != 0 and not _is_liquid(hit_mat):
				colliding = true
				# Tunnista osuiko nukkuvaan kappaleeseen
				if body_map[idx] != 0 and result.hit_body_id == 0:
					result.hit_body_id = body_map[idx]
				var local_normal := Vector2.ZERO
				if wp.x > 0 and grid[idx - 1] == 0: local_normal.x -= 1.0
				if wp.x < w - 1 and grid[idx + 1] == 0: local_normal.x += 1.0
				if wp.y > 0 and grid[idx - w] == 0: local_normal.y -= 1.0
				if wp.y < h - 1 and grid[idx + w] == 0: local_normal.y += 1.0
				accumulated_normal += local_normal

		if colliding:
			collision_points.append(Vector2(wp))

	if not collision_points.is_empty():
		result.hit = true
		result.normal = accumulated_normal
		var sum := Vector2.ZERO
		for cp in collision_points:
			sum += cp
		result.contact_point = sum / float(collision_points.size())

	return result


# === KAPPALE-KAPPALE TÖRMÄYS ===

func _resolve_body_collision(a: RigidBodyData, b: RigidBodyData) -> void:
	var a_pixels := a.get_world_pixels()
	var b_pixels := b.get_world_pixels()

	# AABB-broadphase
	var a_min_x := 99999; var a_max_x := -99999
	var a_min_y := 99999; var a_max_y := -99999
	for wp in a_pixels:
		a_min_x = mini(a_min_x, wp.x); a_max_x = maxi(a_max_x, wp.x)
		a_min_y = mini(a_min_y, wp.y); a_max_y = maxi(a_max_y, wp.y)

	var b_min_x := 99999; var b_max_x := -99999
	var b_min_y := 99999; var b_max_y := -99999
	for wp in b_pixels:
		b_min_x = mini(b_min_x, wp.x); b_max_x = maxi(b_max_x, wp.x)
		b_min_y = mini(b_min_y, wp.y); b_max_y = maxi(b_max_y, wp.y)

	# AABB ei osu → ei törmäystä
	if a_max_x < b_min_x - 1 or b_max_x < a_min_x - 1:
		return
	if a_max_y < b_min_y - 1 or b_max_y < a_min_y - 1:
		return

	# Narrowphase: pikseli-overlap tai kosketus (etäisyys ≤ 1)
	var b_set := {}
	for wp in b_pixels:
		b_set[wp] = true

	var contact_points: Array[Vector2] = []
	var overlap := false
	for wp in a_pixels:
		# Suora overlap
		if b_set.has(wp):
			contact_points.append(Vector2(wp))
			overlap = true
		else:
			# Kosketus (vierekkäiset pikselit)
			for dir in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
				if b_set.has(wp + dir):
					contact_points.append(Vector2(wp) + Vector2(dir) * 0.5)
					break

	if contact_points.is_empty():
		return

	# Kontaktipiste
	var contact := Vector2.ZERO
	for p in contact_points:
		contact += p
	contact /= float(contact_points.size())

	# Törmäysnormaali (A:sta B:hen)
	var normal := (b.position - a.position)
	if normal.length_squared() < 0.01:
		normal = Vector2(0, -1)
	else:
		normal = normal.normalized()

	# Suhteellinen nopeus kontaktipisteessä
	var v_rel := a.velocity - b.velocity
	var vn := v_rel.dot(normal)
	if vn >= 0.0:
		return  # Liikkuvat erilleen

	# Impulssipohjainen törmäysvaste (liikemäärän säilyminen)
	var inv_mass_a := 1.0 / maxf(a.mass, 1.0)
	var inv_mass_b := 1.0 / maxf(b.mass, 1.0)
	# Rajaa impulssi — estää räjähtelyn
	var j := -(1.0 + RESTITUTION) * vn / (inv_mass_a + inv_mass_b)
	j = clampf(j, -50.0, 50.0)

	# Päivitä nopeudet
	a.velocity += normal * j * inv_mass_a
	b.velocity -= normal * j * inv_mass_b

	# Kitka
	var tangent := Vector2(-normal.y, normal.x)
	var vt := v_rel.dot(tangent)
	var jt := clampf(-vt / (inv_mass_a + inv_mass_b), -absf(j) * FRICTION, absf(j) * FRICTION)
	a.velocity += tangent * jt * inv_mass_a
	b.velocity -= tangent * jt * inv_mass_b

	# Vääntömomentti kontaktipisteestä (hillitty)
	var ra := contact - a.position
	var rb := contact - b.position
	var torque_a := ra.x * normal.y - ra.y * normal.x
	var torque_b := rb.x * normal.y - rb.y * normal.x
	a.angular_velocity += torque_a * j / maxf(a.inertia, 1.0) * 0.005
	b.angular_velocity -= torque_b * j / maxf(b.inertia, 1.0) * 0.005

	# Rajoita nopeudet törmäyksen jälkeen
	if a.velocity.length() > MAX_VELOCITY:
		a.velocity = a.velocity.normalized() * MAX_VELOCITY
	if b.velocity.length() > MAX_VELOCITY:
		b.velocity = b.velocity.normalized() * MAX_VELOCITY

	# Erota kappaleet (pehmeä penetraation korjaus)
	if overlap:
		var depth := minf(float(contact_points.size()) * 0.3, 2.0)
		var total_mass := a.mass + b.mass
		a.position -= normal * depth * (b.mass / maxf(total_mass, 1.0))
		b.position += normal * depth * (a.mass / maxf(total_mass, 1.0))


# === TIPPING TORQUE ===
# Parannettu: laskee todellisen tukipinnan ja käyttää kappaleen leveyttä vertailussa
# Kappale kaatuu jos painopiste on tukialueen ulkopuolella

func _apply_tipping_torque(body: RigidBodyData, grid: PackedByteArray, w: int, h: int) -> void:
	var world_pixels := body.get_world_pixels()

	# Etsi kappaleen alimmat pikselit (pohjapinta) ja niiden tukipisteet
	var bottom_pixels: Array[Vector2i] = []
	var body_set := {}
	for wp in world_pixels:
		body_set[wp] = true

	for wp in world_pixels:
		if wp.x < 0 or wp.x >= w or wp.y < 0 or wp.y >= h:
			continue
		var below := Vector2i(wp.x, wp.y + 1)
		# Pohjapinta = pikseli jonka alla EI ole omaa pikseliä
		if body_set.has(below):
			continue
		bottom_pixels.append(wp)

	if bottom_pixels.is_empty():
		return

	# Etsi tukipisteet — pohjapikselit joiden alla on jotain (maasto/muu kappale/reuna)
	var support_points: Array[float] = []
	for bp in bottom_pixels:
		var below_y := bp.y + 1
		var supported := false
		if below_y >= h:
			supported = true  # Maanpohja
		elif grid[below_y * w + bp.x] != 0:
			supported = true  # Jotain alla
		if supported:
			support_points.append(float(bp.x))

	if support_points.is_empty():
		return  # Vapaassa pudotuksessa

	# Tukialueen rajat
	var support_min := support_points[0]
	var support_max := support_points[0]
	for sx in support_points:
		support_min = minf(support_min, sx)
		support_max = maxf(support_max, sx)

	var support_center := (support_min + support_max) * 0.5
	var support_width := support_max - support_min + 1.0

	# Kappaleen kokonaisleveys (vertailuarvoksi)
	var body_min_x := 99999.0
	var body_max_x := -99999.0
	for wp in world_pixels:
		body_min_x = minf(body_min_x, float(wp.x))
		body_max_x = maxf(body_max_x, float(wp.x))
	var body_width := body_max_x - body_min_x + 1.0

	# Painopisteen poikkeama tukikeskipisteestä
	var offset_x := body.position.x - support_center

	# Tukisuhde: kapea tuki suhteessa kappaleeseen = helpompi kaatua
	var stability_ratio := support_width / maxf(body_width, 1.0)

	# Vääntövoima — voimakkaampi jos tuki on kapea ja painopiste kaukana
	if absf(offset_x) > 0.3:
		var half_support := support_width * 0.5
		var tip_strength := offset_x / maxf(half_support, 0.5)

		# Kapea tuki vahvistaa kallistusta
		var instability := 1.0 - clampf(stability_ratio, 0.0, 1.0)
		tip_strength *= (1.0 + instability * 2.0)

		tip_strength = clampf(tip_strength, -3.0, 3.0)
		body.angular_velocity += tip_strength * TIPPING_TORQUE

		# Jos painopiste on täysin tuen ulkopuolella → vahva kallistus + sivuttaisliike
		if absf(offset_x) > half_support:
			body.angular_velocity += signf(offset_x) * TIPPING_TORQUE * 3.0
			body.velocity.x += signf(offset_x) * 0.05


# === SKANNAUS JA VAURIOT ===

func scan_stone_bodies(grid: PackedByteArray, color_seed: PackedByteArray, w: int, h: int) -> void:
	_ensure_body_map(w, h)
	var components := CCL.find_components(grid, w, h, 3)  # MAT_STONE = 3

	for root in components:
		var pixels: Array[Vector2i] = components[root]
		if pixels.size() < MIN_BODY_SIZE:
			continue

		var seeds := PackedByteArray()
		seeds.resize(pixels.size())
		for i in pixels.size():
			var p := pixels[i]
			seeds[i] = color_seed[p.y * w + p.x]

		var body := create_body(pixels, seeds, 3)
		if body:
			# Kaikki alussa skannatut kappaleet ovat staattisia (osa maailmaa)
			# Ne muuttuvat dynaamisiksi vasta kun räjähdys/leikkaus irrottaa palan
			body.is_static = true
			body.is_sleeping = true
			# Kirjoita body_map
			for p in pixels:
				body_map[p.y * w + p.x] = body.body_id


func check_damage(grid: PackedByteArray, color_seed: PackedByteArray, w: int, h: int) -> void:
	_ensure_body_map(w, h)
	var check_static := force_damage_check  # Staattiset vain räjähdyksen jälkeen
	var bodies_to_check: Array[int] = []

	for body_id in bodies:
		var body: RigidBodyData = bodies[body_id]
		if body.is_static and not check_static:
			continue  # Ohita staattiset normaalilla tarkistuksella
		var world_pixels := body.get_world_pixels()
		var intact := true

		for wp in world_pixels:
			if wp.x < 0 or wp.x >= w or wp.y < 0 or wp.y >= h:
				continue
			var idx := wp.y * w + wp.x
			if grid[idx] != body.material:
				intact = false
				break

		if not intact:
			bodies_to_check.append(body_id)

	for body_id in bodies_to_check:
		_split_if_needed(body_id, grid, color_seed, w, h)


func _split_if_needed(body_id: int, grid: PackedByteArray, color_seed: PackedByteArray, w: int, h: int) -> void:
	if not bodies.has(body_id):
		return

	var body: RigidBodyData = bodies[body_id]
	var surviving_pixels: Array[Vector2i] = []
	var surviving_seeds := PackedByteArray()
	var world_pixels := body.get_world_pixels()

	for i in world_pixels.size():
		var wp := world_pixels[i]
		if wp.x >= 0 and wp.x < w and wp.y >= 0 and wp.y < h:
			var idx := wp.y * w + wp.x
			if grid[idx] == body.material:
				surviving_pixels.append(wp)
				surviving_seeds.append(color_seed[idx])

	if surviving_pixels.is_empty():
		_clear_body_from_map(body_id)
		remove_body(body_id)
		return

	var components := CCL.check_connectivity(surviving_pixels)

	if components.size() <= 1:
		# Yhtenäinen — päivitä muoto
		_clear_body_from_map(body_id)
		body.calculate_from_world_pixels(surviving_pixels, surviving_seeds)
		body.wake_up()
		for wp in surviving_pixels:
			body_map[wp.y * w + wp.x] = body_id
		return

	# Halkaise
	_clear_body_from_map(body_id)
	remove_body(body_id)

	for component in components:
		var comp_pixels: Array[Vector2i] = component
		var comp_seeds := PackedByteArray()
		comp_seeds.resize(comp_pixels.size())
		for i in comp_pixels.size():
			var p: Vector2i = comp_pixels[i]
			comp_seeds[i] = color_seed[p.y * w + p.x]

		if comp_pixels.size() >= MIN_BODY_SIZE:
			var new_body := create_body(comp_pixels, comp_seeds, body.material)
			if new_body:
				# Reunaa koskettavat palat pysyvät staattisina (vasen/oikea/ala — ei ylä)
				var touches_edge := false
				for p in comp_pixels:
					if p.x <= 0 or p.x >= w - 1 or p.y >= h - 1:
						touches_edge = true
						break
				if touches_edge:
					new_body.is_static = true
					new_body.is_sleeping = true
				else:
					new_body.velocity = body.velocity
					new_body.angular_velocity = body.angular_velocity
					new_body.wake_up()
				for p in comp_pixels:
					body_map[p.y * w + p.x] = new_body.body_id
		else:
			# Liian pieni → mursketta (hiekka)
			for p in comp_pixels:
				var idx := p.y * w + p.x
				grid[idx] = 1  # MAT_SAND
				body_map[idx] = 0


func _clear_body_from_map(body_id: int) -> void:
	if not bodies.has(body_id):
		# Kappale jo poistettu — skannaa (harvinainen)
		for i in body_map.size():
			if body_map[i] == body_id:
				body_map[i] = 0
		return
	# Käytä kappaleen pikseleitä — paljon nopeampi
	var body: RigidBodyData = bodies[body_id]
	var world_pixels := body.get_world_pixels()
	for wp in world_pixels:
		if wp.x >= 0 and wp.x < map_w and wp.y >= 0 and wp.y < map_h:
			var idx := wp.y * map_w + wp.x
			if body_map[idx] == body_id:
				body_map[idx] = 0
