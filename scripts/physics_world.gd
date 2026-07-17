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
const MAX_DYNAMIC_BODIES := 40  # Enintään 40 aktiivista rigid bodyä
var next_body_id: int = 1
var body_map: PackedInt32Array  # cell → body_id (0 = ei kappaletta)
var map_w: int = 0
var map_h: int = 0
var force_damage_check := false  # Pakota vauriotarkistus (räjähdyksen jälkeen)

# Dirty rect — rajoittaa check_damage():n vain muuttuneelle alueelle
var damage_dirty_rect: Rect2i = Rect2i()
var has_damage_dirty_rect: bool = false
# Tallennettu dirty rect _split_if_needed()-kutsuja varten check_damage()-kutsun aikana
# (has_damage_dirty_rect nollataan ennen jonon käsittelyä, joten tarvitaan erillinen kopio)
var _active_split_dirty_rect: Rect2i = Rect2i()
var _has_active_split_dirty_rect: bool = false

# Vaurioitumisjono — hajautetaan splittaukset useammalle framelle
var damage_check_queue: Array = []
const MAX_SPLITS_PER_FRAME: int = 3


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
	# Laske ei-staattiset kappaleet — hylkää uusi jos kapasiteetti täynnä
	var dynamic_count := 0
	for bid in bodies:
		if not bodies[bid].is_static:
			dynamic_count += 1
	if dynamic_count >= MAX_DYNAMIC_BODIES:
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

	# Aseta dirty rect räjähdysalueelle — check_damage ohittaa kaukaisia kappaleita
	var blast_r := int(radius) + 20  # Marginaali kappaleiden liikkumiselle
	var rect_pos := Vector2i(int(center.x) - blast_r, int(center.y) - blast_r)
	var rect_size := Vector2i(blast_r * 2, blast_r * 2)
	if has_damage_dirty_rect:
		# Laajenna olemassa olevaa rekttiä
		damage_dirty_rect = damage_dirty_rect.merge(Rect2i(rect_pos, rect_size))
	else:
		damage_dirty_rect = Rect2i(rect_pos, rect_size)
		has_damage_dirty_rect = true
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

		# CCD: nopea kappale voi tunnelöida ohuiden seinien läpi — sweepaa väliaskeleet
		if not collision.hit and body.velocity.length() > 1.5:
			var ccd_n := ceili(body.velocity.length())
			for ci in range(1, ccd_n):
				var t_probe := float(ci) / float(ccd_n)
				body.position = old_pos + body.velocity * t_probe
				body.angle = old_angle + body.angular_velocity * t_probe
				var c := _find_env_collision(body, grid, w, h)
				if c.hit:
					collision = c
					break
			if not collision.hit:
				body.position = old_pos + body.velocity
				body.angle = old_angle + body.angular_velocity

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


# === APUFUNKTIOT ===

func _is_liquid(mat: int) -> bool:
	return mat == 2 or mat == 6 or mat == 7  # MAT_WATER, MAT_OIL, MAT_STEAM


# === ERASE / WRITE ===
# Iteroivat kappaleen aukotonta täytettyä muotoa (flat filled-cache).
# Maailmapikseli = filled-offset + pyöristetty positio.

func _erase_body(body: RigidBodyData, grid: PackedByteArray, seed: PackedByteArray, w: int, h: int) -> void:
	body._ensure_filled_cache()
	var px := roundi(body.position.x)
	var py := roundi(body.position.y)
	var fox := body.filled_ox
	var foy := body.filled_oy
	var bid := body.body_id
	for k in fox.size():
		var wx := fox[k] + px
		var wy := foy[k] + py
		if wx >= 0 and wx < w and wy >= 0 and wy < h:
			var idx := wy * w + wx
			if body_map[idx] == bid:
				grid[idx] = 0
				seed[idx] = 0
				body_map[idx] = 0


func _write_body(body: RigidBodyData, grid: PackedByteArray, seed: PackedByteArray, w: int, h: int) -> int:
	body._ensure_filled_cache()
	var px := roundi(body.position.x)
	var py := roundi(body.position.y)
	var fox := body.filled_ox
	var foy := body.filled_oy
	var fsrc := body.filled_src
	var seeds := body.pixel_seeds
	var seeds_n := seeds.size()
	var mat := body.material
	var bid := body.body_id
	var written := 0
	for k in fox.size():
		var wx := fox[k] + px
		var wy := foy[k] + py
		if wx >= 0 and wx < w and wy >= 0 and wy < h:
			var idx := wy * w + wx
			var cur := grid[idx]
			if cur == 0 or _is_liquid(cur):
				# Syrjäytä neste viereiseen tyhjään soluun
				if _is_liquid(cur):
					var liq_mat := cur
					var liq_seed := seed[idx]
					for disp in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, -1), Vector2i(1, -1)]:
						var nx: int = wx + disp.x
						var ny: int = wy + disp.y
						if nx >= 0 and nx < w and ny >= 0 and ny < h:
							var nidx := ny * w + nx
							if grid[nidx] == 0 and body_map[nidx] == 0:
								grid[nidx] = liq_mat
								seed[nidx] = liq_seed
								break
				grid[idx] = mat
				body_map[idx] = bid
				var pi := fsrc[k]
				if pi >= 0 and pi < seeds_n:
					seed[idx] = seeds[pi]
				elif seeds_n > 0:
					# Aukontäytön seed — ota naapurilta
					seed[idx] = seeds[0]
				written += 1
	return maxi(body.local_pixels.size() - written, 0)


# === YMPÄRISTÖTÖRMÄYS ===

class CollisionResult:
	var hit: bool = false
	var normal: Vector2 = Vector2.ZERO
	var contact_point: Vector2 = Vector2.ZERO
	var hit_body_id: int = 0  # Nukkuvan/staattisen kappaleen ID


func _check_env_collision(body: RigidBodyData, grid: PackedByteArray, w: int, h: int) -> bool:
	body._ensure_rot_cache()
	var px := roundi(body.position.x)
	var py := roundi(body.position.y)
	var rox := body.rot_ox
	var roy := body.rot_oy
	for i in rox.size():
		var wx := rox[i] + px
		var wy := roy[i] + py
		if wx < 0 or wx >= w or wy < 0 or wy >= h:
			return true
		var mat := grid[wy * w + wx]
		if mat != 0 and not _is_liquid(mat):
			return true
	return false


func _find_env_collision(body: RigidBodyData, grid: PackedByteArray, w: int, h: int) -> CollisionResult:
	var result := CollisionResult.new()
	body._ensure_rot_cache()
	var px := roundi(body.position.x)
	var py := roundi(body.position.y)
	var rox := body.rot_ox
	var roy := body.rot_oy
	var accumulated_normal := Vector2.ZERO
	# Kontaktipisteiden summa + lukumäärä (ei Array-allokaatiota keskiarvoon)
	var contact_sum := Vector2.ZERO
	var contact_count := 0

	for i in rox.size():
		var wx := rox[i] + px
		var wy := roy[i] + py
		var colliding := false

		if wx < 0 or wx >= w or wy < 0 or wy >= h:
			colliding = true
			if wx < 0: accumulated_normal += Vector2(1, 0)
			elif wx >= w: accumulated_normal += Vector2(-1, 0)
			if wy < 0: accumulated_normal += Vector2(0, 1)
			elif wy >= h: accumulated_normal += Vector2(0, -1)
		else:
			var idx := wy * w + wx
			var hit_mat := grid[idx]
			if hit_mat != 0 and not _is_liquid(hit_mat):
				colliding = true
				# Tunnista osuiko nukkuvaan kappaleeseen
				if body_map[idx] != 0 and result.hit_body_id == 0:
					result.hit_body_id = body_map[idx]
				var local_normal := Vector2.ZERO
				if wx > 0 and grid[idx - 1] == 0: local_normal.x -= 1.0
				if wx < w - 1 and grid[idx + 1] == 0: local_normal.x += 1.0
				if wy > 0 and grid[idx - w] == 0: local_normal.y -= 1.0
				if wy < h - 1 and grid[idx + w] == 0: local_normal.y += 1.0
				accumulated_normal += local_normal

		if colliding:
			contact_sum += Vector2(wx, wy)
			contact_count += 1

	if contact_count > 0:
		result.hit = true
		result.normal = accumulated_normal
		result.contact_point = contact_sum / float(contact_count)

	return result


# === KAPPALE-KAPPALE TÖRMÄYS ===

func _resolve_body_collision(a: RigidBodyData, b: RigidBodyData) -> void:
	# HUOM: tätä funktiota ei tällä hetkellä kutsuta mistään (kappale-kappale-
	# vuorovaikutus hoidetaan sekventiaalisella erase→write + body_map -tunnistuksella
	# step():ssä). Optimoitu silti flat-rakenteisiin: iteroi rot-offsetteja ja käyttää
	# b:n pikseleille flat-bittikarttaa Dictionaryn sijaan. Semantiikka ennallaan.
	a._ensure_rot_cache()
	b._ensure_rot_cache()
	var apx := roundi(a.position.x); var apy := roundi(a.position.y)
	var bpx := roundi(b.position.x); var bpy := roundi(b.position.y)
	var a_rox := a.rot_ox; var a_roy := a.rot_oy
	var b_rox := b.rot_ox; var b_roy := b.rot_oy

	# AABB-broadphase (maailmakoordinaatit = rot-AABB + pyöristetty positio)
	var a_min_x := a.rot_min_x + apx; var a_max_x := a.rot_max_x + apx
	var a_min_y := a.rot_min_y + apy; var a_max_y := a.rot_max_y + apy
	var b_min_x := b.rot_min_x + bpx; var b_max_x := b.rot_max_x + bpx
	var b_min_y := b.rot_min_y + bpy; var b_max_y := b.rot_max_y + bpy

	# AABB ei osu → ei törmäystä
	if a_max_x < b_min_x - 1 or b_max_x < a_min_x - 1:
		return
	if a_max_y < b_min_y - 1 or b_max_y < a_min_y - 1:
		return

	# Narrowphase: b:n pikselit flat-bittikartalle b:n AABB:n yli
	var bw := b_max_x - b_min_x + 1
	var bh := b_max_y - b_min_y + 1
	var b_set := PackedByteArray()
	b_set.resize(bw * bh)
	for i in b_rox.size():
		b_set[(b_roy[i] + bpy - b_min_y) * bw + (b_rox[i] + bpx - b_min_x)] = 1

	# Overlap tai kosketus (etäisyys ≤ 1)
	var contact_sum := Vector2.ZERO
	var contact_count := 0
	var overlap := false
	for i in a_rox.size():
		var ax := a_rox[i] + apx
		var ay := a_roy[i] + apy
		# Suora overlap
		if ax >= b_min_x and ax <= b_max_x and ay >= b_min_y and ay <= b_max_y \
				and b_set[(ay - b_min_y) * bw + (ax - b_min_x)] == 1:
			contact_sum += Vector2(ax, ay)
			contact_count += 1
			overlap = true
		else:
			# Kosketus (vierekkäiset pikselit)
			for dir in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
				var nx: int = ax + dir.x
				var ny: int = ay + dir.y
				if nx >= b_min_x and nx <= b_max_x and ny >= b_min_y and ny <= b_max_y \
						and b_set[(ny - b_min_y) * bw + (nx - b_min_x)] == 1:
					contact_sum += Vector2(ax, ay) + Vector2(dir) * 0.5
					contact_count += 1
					break

	if contact_count == 0:
		return

	# Kontaktipiste
	var contact := contact_sum / float(contact_count)

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
		var depth := minf(float(contact_count) * 0.3, 2.0)
		var total_mass := a.mass + b.mass
		a.position -= normal * depth * (b.mass / maxf(total_mass, 1.0))
		b.position += normal * depth * (a.mass / maxf(total_mass, 1.0))


# === TIPPING TORQUE ===
# Parannettu: laskee todellisen tukipinnan ja käyttää kappaleen leveyttä vertailussa
# Kappale kaatuu jos painopiste on tukialueen ulkopuolella

func _apply_tipping_torque(body: RigidBodyData, grid: PackedByteArray, w: int, h: int) -> void:
	# Pohjapinta cachetaan (offsetit joiden alla ei omaa pikseliä).
	body._ensure_bottom_cache()
	var px := roundi(body.position.x)
	var py := roundi(body.position.y)
	var box := body.bottom_ox
	var boy := body.bottom_oy
	if box.is_empty():
		return

	# Etsi tukipisteet — pohjapikselit joiden alla on jotain (maasto/muu kappale/reuna)
	var support_min := INF
	var support_max := -INF
	var has_support := false
	for k in box.size():
		var wx := box[k] + px
		var wy := boy[k] + py
		if wx < 0 or wx >= w or wy < 0 or wy >= h:
			continue
		var below_y := wy + 1
		var supported := false
		if below_y >= h:
			supported = true  # Maanpohja
		elif grid[below_y * w + wx] != 0:
			supported = true  # Jotain alla
		if supported:
			var fx := float(wx)
			if fx < support_min: support_min = fx
			if fx > support_max: support_max = fx
			has_support = true

	if not has_support:
		return  # Vapaassa pudotuksessa

	var support_center := (support_min + support_max) * 0.5
	var support_width := support_max - support_min + 1.0

	# Kappaleen kokonaisleveys (kierrettyjen offsettien AABB, position-riippumaton)
	var body_width := float(body.rot_max_x - body.rot_min_x) + 1.0

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
	var components := CCL.find_components_fast(grid, w, h, 3)  # MAT_STONE = 3, BFS-versio nopeampi

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


# Tarkistaa onko kappale vaurioitunut iteroimalla kappaleen pikselilistaa suoraan.
# Paljon nopeampi kuin bbox-skannaus — O(N_pikseleissä) eikä O(bbox²).
# Early-exit: palaa heti kun ensimmäinen puuttuva pikseli löytyy.
func is_body_damaged(body: RigidBodyData, grid: PackedByteArray, w: int, h: int) -> bool:
	body._ensure_rot_cache()
	var px := roundi(body.position.x)
	var py := roundi(body.position.y)
	var rox := body.rot_ox
	var roy := body.rot_oy
	var mat := body.material
	for i in rox.size():
		var wx := rox[i] + px
		var wy := roy[i] + py
		if wx < 0 or wx >= w or wy < 0 or wy >= h:
			continue
		if grid[wy * w + wx] != mat:
			return true  # Vaurioitunut — early-exit
	return false


func check_damage(grid: PackedByteArray, color_seed: PackedByteArray, w: int, h: int) -> void:
	_ensure_body_map(w, h)
	var check_static := force_damage_check  # Staattiset vain räjähdyksen jälkeen

	if not has_damage_dirty_rect:
		# Normaali frame: tarkista vain dynaamiset / herätetyt kappaleet vanhalla tavalla
		if check_static:
			# force_damage_check ilman dirty rect — tarkista kaikki (harvinainen tapaus)
			for body_id in bodies:
				var body: RigidBodyData = bodies[body_id]
				if is_body_damaged(body, grid, w, h):
					if not damage_check_queue.has(body_id):
						damage_check_queue.append(body_id)
		else:
			for body_id in bodies:
				var body: RigidBodyData = bodies[body_id]
				if body.is_static:
					continue
				if is_body_damaged(body, grid, w, h):
					if not damage_check_queue.has(body_id):
						damage_check_queue.append(body_id)
	else:
		# Räjähdys: skannaa VAIN dirty rect -alue body_mapista.
		# O(dirty_rect_area) ≈ O(1600) eikä O(body.pixels) ≈ O(361000).
		var damaged_ids: Dictionary = {}
		var x0 := maxi(damage_dirty_rect.position.x, 0)
		var y0 := maxi(damage_dirty_rect.position.y, 0)
		var x1 := mini(damage_dirty_rect.end.x, w - 1)
		var y1 := mini(damage_dirty_rect.end.y, h - 1)
		for y in range(y0, y1 + 1):
			var row := y * w
			for x in range(x0, x1 + 1):
				var idx := row + x
				var bid := body_map[idx]
				if bid != 0 and not damaged_ids.has(bid):
					if bodies.has(bid):
						var b: RigidBodyData = bodies[bid]
						# Tarkista onko tämä solu muuttunut — jos kyllä, body on vaurioitunut
						if grid[idx] != b.material:
							damaged_ids[bid] = true
		for body_id in damaged_ids:
			if not damage_check_queue.has(body_id):
				damage_check_queue.append(body_id)

	# Tallenna dirty rect _split_if_needed():ä varten ennen nollausta
	_has_active_split_dirty_rect = has_damage_dirty_rect
	_active_split_dirty_rect = damage_dirty_rect

	# Nollaa dirty rect ennen jonon käsittelyä
	has_damage_dirty_rect = false

	# Käsittele enintään MAX_SPLITS_PER_FRAME kappaletta tällä framella
	var processed := 0
	while not damage_check_queue.is_empty() and processed < MAX_SPLITS_PER_FRAME:
		var body_id: int = damage_check_queue.pop_front()
		_split_if_needed(body_id, grid, color_seed, w, h)
		processed += 1

	_has_active_split_dirty_rect = false


func _split_if_needed(body_id: int, grid: PackedByteArray, color_seed: PackedByteArray, w: int, h: int) -> void:
	if not bodies.has(body_id):
		return

	var body: RigidBodyData = bodies[body_id]

	# --- Nopea polku: suuri staattinen kappale + dirty rect saatavilla ---
	# Vältetään 361K-pikselin get_world_pixels()-kutsu kokonaan.
	# Päivitetään vain dirty rect -alue body_mapissa ja local_pixels-listassa.
	const LARGE_BODY_DIRTY_THRESHOLD := 400
	if body.is_static and body.local_pixels.size() > LARGE_BODY_DIRTY_THRESHOLD and _has_active_split_dirty_rect:
		var x0 := maxi(_active_split_dirty_rect.position.x, 0)
		var y0 := maxi(_active_split_dirty_rect.position.y, 0)
		var x1 := mini(_active_split_dirty_rect.end.x, w - 1)
		var y1 := mini(_active_split_dirty_rect.end.y, h - 1)
		# Poista dirty rect -alueelta kadonneet pikselit body_mapista
		for y in range(y0, y1 + 1):
			var row := y * w
			for x in range(x0, x1 + 1):
				var idx := row + x
				if body_map[idx] == body_id and grid[idx] != body.material:
					body_map[idx] = 0
		# Suuri staattinen kappale: ei CCL:ää eikä calculate_from_world_pixels().
		# body.local_pixels jää vanhentuneeksi mutta se on hyväksyttävää —
		# vaurioalueen pikselit ovat jo poistuneet body_mapista.
		# CCL-skip pätee edelleen: iso staattinen ei splitaudu pienestä räjähdyksestä.
		return

	# --- Normaali polku: pieni kappale tai dynaaminen ---
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

	# Suuri staattinen kappale ilman dirty rect (harvinainen: force_damage_check ilman räjähdystä) —
	# ohitetaan kallis CCL ja päivitetään pikselilista suoraan
	const LARGE_BODY_CCL_SKIP := 400
	if body.is_static and surviving_pixels.size() > LARGE_BODY_CCL_SKIP:
		_clear_body_from_map(body_id)
		body.calculate_from_world_pixels(surviving_pixels, surviving_seeds)
		# Staattinen kappale pysyy paikallaan
		body.is_static = true
		body.is_sleeping = true
		for wp in surviving_pixels:
			body_map[wp.y * w + wp.x] = body_id
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
	# Käytä kappaleen pikseleitä — paljon nopeampi (iteroi rot-offsetit suoraan)
	var body: RigidBodyData = bodies[body_id]
	body._ensure_rot_cache()
	var px := roundi(body.position.x)
	var py := roundi(body.position.y)
	var rox := body.rot_ox
	var roy := body.rot_oy
	for i in rox.size():
		var wx := rox[i] + px
		var wy := roy[i] + py
		if wx >= 0 and wx < map_w and wy >= 0 and wy < map_h:
			var idx := wy * map_w + wx
			if body_map[idx] == body_id:
				body_map[idx] = 0


# === JONOTETTU VAURIONKÄSITTELY ===
# Kutsutaan joka framella — käsittelee jäljellä olevat splittaukset jonosta

func process_damage_queue(grid: PackedByteArray, color_seed: PackedByteArray, w: int, h: int) -> bool:
	if damage_check_queue.is_empty():
		return false
	var processed := 0
	while not damage_check_queue.is_empty() and processed < MAX_SPLITS_PER_FRAME:
		var body_id: int = damage_check_queue.pop_front()
		_split_if_needed(body_id, grid, color_seed, w, h)
		processed += 1
	return true
