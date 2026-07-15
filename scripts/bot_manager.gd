# Kaikkien bottien paivitys: tyonjako, tilakoneiden ajaminen, piirto.
# Tikataan CPU-logiikkavaiheessa (delta = kumuloitu, ~4 framen arvo).
# world = pixel_world. Kaytetaan sokkona kontraktin rajapintaa:
#   world.grid (PackedByteArray), world.nav (NavGrid), world.desig (DesignationGrid),
#   world.base (MoneyExit Base-roolissa), world.mvp_write_pixel(x,y,mat),
#   world.building_pixels (Dictionary idx->true), world.money (int).
class_name BotManager
extends RefCounted

# --- Simulaatioruudukko (kontraktin mukainen kiinteä koko) ---
const SIM_W := 1664
const SIM_H := 960

# --- Designaatiogridi (peilaus DesignationGridista) ---
# DCELL = NCELL = 16 -> designaatiosolu vastaa navsolua 1:1 (saavutettavuus suoraviivainen).
const DCELL := 16
const GW := 104
const GH := 60
const D_NONE := 0
const D_QUEUED := 1
const D_BLOCKED := 2
const D_CLAIMED := 3
const D_MINING := 4

# --- Navigaatiogridi (peilaus NavGridista) ---
const NCELL := 16
const NW := 104
const NH := 60

# --- Materiaali-ID:t ---
const MAT_EMPTY := 0
const MAT_SAND := 1
const MAT_STONE := 3
const MAT_WOOD := 4
const MAT_ASH := 8
const MAT_WOOD_FALLING := 9
const MAT_GLASS := 10
const MAT_DIRT := 11
const MAT_IRON_ORE := 12
const MAT_GOLD_ORE := 13
const MAT_IRON := 14
const MAT_GOLD := 15
const MAT_COAL := 16
const MAT_GRAVEL := 18
const MAT_BEDROCK := 19

# --- Ajastimet ja kynnykset ---
const ASSIGN_INTERVAL := 0.5       # tyonjako 2 Hz
const MINE_STALL_TIME := 2.0        # jos kiinteat eivat vahene taman ajan -> lopeta solu
const MINE_MAX_TIME := 20.0         # kova katto louhinnalle (turvavahti)
const MOVE_MAX_TIME := 30.0         # kova katto liikkeelle (turvavahti)
const FAIL_COOLDOWN := 2.0          # epaonnistunut kohde jaahylle
const EMPTY_DIG_COOLDOWN := 2.0     # tyhjentynyt dig_site jaahylle
const ARRIVE_DIST := 4.0            # waypoint saavutettu kun etaisyys alle tama
const MINE_REACH_DIST := 48.0       # kuinka lahella solua louhinta saa alkaa
const VACUUM_RADIUS := 10           # haulerin imurointisade px
const MAX_DIG_SITES := 200          # FIFO-katto
const MAX_PILE_SCANS := 24          # montako dig_sitea skannataan / hauler-varaus
const PILE_MIN_PX := 5              # minimikasa jotta kannattaa hakea
const PILE_SCAN_DEPTH := 240        # 15 navsolua alaspain (15*16)
const PILE_SCAN_HALF_W := 4         # sarakkeen levennys molemmin puolin px

# 8 suuntaa (nav-naapurit)
const NAV_DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

# --- Tila ---
var bots: Array[Bot] = []
var world: Node = null
var dig_sites: Array[Vector2i] = []       # FIFO louhitut solut (designaatiokoordinaatit)
var _assign_timer: float = 0.0
var _cell_cooldown: Dictionary = {}        # cell_key (dy*GW+dx) -> jaljella oleva jaahy (s)

# LUT:t suoraan mat-ID:lla (256 alkiota)
var _mineable_lut: PackedByteArray         # miner louhii nama
var _granular_lut: PackedByteArray         # hauler poimii nama
var _floor_lut: PackedByteArray            # kasan pysayttava kiintea pohja


# ============================================================
#  Setup
# ============================================================

func setup(world: Node) -> void:
	self.world = world
	_build_luts()


func _build_luts() -> void:
	_mineable_lut = PackedByteArray()
	_mineable_lut.resize(256)
	_granular_lut = PackedByteArray()
	_granular_lut.resize(256)
	_floor_lut = PackedByteArray()
	_floor_lut.resize(256)
	# Louhittavat kiinteat (miner)
	for m in [MAT_STONE, MAT_DIRT, MAT_SAND, MAT_IRON_ORE, MAT_GOLD_ORE, MAT_COAL, MAT_WOOD]:
		_mineable_lut[m] = 1
	# Granulaariset (haulerin poimittavat)
	for m in [MAT_SAND, MAT_DIRT, MAT_GRAVEL, MAT_IRON_ORE, MAT_GOLD_ORE, MAT_COAL, MAT_ASH]:
		_granular_lut[m] = 1
	# Kasan pysayttava kiintea pohja (ei-granulaarinen kiintea)
	for m in [MAT_STONE, MAT_WOOD, MAT_WOOD_FALLING, MAT_GLASS, MAT_IRON, MAT_GOLD, MAT_BEDROCK]:
		_floor_lut[m] = 1


func add_bot(role: int, p: Vector2) -> Bot:
	var b := Bot.new()
	b.role = role
	b.pos = p
	b.spawn_pos = p
	b.state = Bot.BotState.IDLE
	# Pieni deterministinen hajautusoffset IDLE-leijuntaan (ettei botit ole paallekkain)
	var i := bots.size()
	b.hover_offset = Vector2(float((i % 4) * 6 - 9), float((i / 4) * 6))
	bots.append(b)
	return b


# ============================================================
#  Tikki
# ============================================================

func tick(delta: float) -> void:
	if world == null:
		return
	_tick_cooldowns(delta)
	# Tyonjako harvakseltaan (ei joka tikilla)
	_assign_timer += delta
	if _assign_timer >= ASSIGN_INTERVAL:
		_assign_timer = 0.0
		_run_assignment()
	# Tilakoneet joka tikilla
	for b in bots:
		_update_bot(b, delta)


func _tick_cooldowns(delta: float) -> void:
	if _cell_cooldown.is_empty():
		return
	var to_del: Array = []
	for k in _cell_cooldown:
		var t: float = _cell_cooldown[k] - delta
		if t <= 0.0:
			to_del.append(k)
		else:
			_cell_cooldown[k] = t
	for k in to_del:
		_cell_cooldown.erase(k)


# ============================================================
#  Tyonjako (2 Hz)
# ============================================================

func _run_assignment() -> void:
	_scan_designations()
	for b in bots:
		if b.state == Bot.BotState.IDLE:
			if b.role == Bot.Role.MINER:
				_assign_miner(b)
			else:
				_assign_hauler(b)


# Skannaa koko designaatiogridi: QUEUED <-> BLOCKED nav-naapuruuden mukaan.
# Halpa 2 Hz -taajuudella; ALA aja joka framella.
func _scan_designations() -> void:
	var d = world.desig
	if d == null or d.cells.size() < GW * GH:
		return
	for dy in GH:
		var row := dy * GW
		for dx in GW:
			var v: int = d.cells[row + dx]
			if v == D_QUEUED:
				if not _has_open_neighbor(dx, dy):
					d.set_cell(dx, dy, D_BLOCKED)
			elif v == D_BLOCKED:
				if _has_open_neighbor(dx, dy):
					d.set_cell(dx, dy, D_QUEUED)


# Onko designaatiosolulla (dx,dy) vahintaan yksi OPEN-navnaapuri?
func _has_open_neighbor(dx: int, dy: int) -> bool:
	var ncx := (dx * DCELL + DCELL / 2) / NCELL
	var ncy := (dy * DCELL + DCELL / 2) / NCELL
	for dir in NAV_DIRS:
		var cx := ncx + dir.x
		var cy := ncy + dir.y
		if cx < 0 or cx >= NW or cy < 0 or cy >= NH:
			continue
		if world.nav.is_open(cx, cy):
			return true
	return false


# Miner: varaa lahin louhittava (QUEUED, ei jaahylla) solu, reitita viereen.
func _assign_miner(b: Bot) -> void:
	var d = world.desig
	if d == null or d.cells.size() < GW * GH:
		return
	var bcx := int(b.pos.x) / DCELL
	var bcy := int(b.pos.y) / DCELL
	var best := Vector2i(-1, -1)
	var best_dist := 0x7fffffff
	for dy in GH:
		var row := dy * GW
		for dx in GW:
			if d.cells[row + dx] != D_QUEUED:
				continue
			if _cell_cooldown.has(row + dx):
				continue
			var dist := absi(dx - bcx) + absi(dy - bcy)
			if dist < best_dist:
				best_dist = dist
				best = Vector2i(dx, dy)
	if best.x < 0:
		return  # ei tyota -> jaa IDLEen
	# Varaa solu
	d.set_cell(best.x, best.y, D_CLAIMED)
	var target_px := Vector2(float(best.x * DCELL + DCELL / 2), float(best.y * DCELL + DCELL / 2))
	var path: PackedVector2Array = world.nav.find_path_px(b.pos, target_px)
	if path.is_empty():
		# Ei reittia -> vapauta varaus, jaahylle, yrita myohemmin
		d.set_cell(best.x, best.y, D_QUEUED)
		_cell_cooldown[best.y * GW + best.x] = FAIL_COOLDOWN
		return
	b.target_cell = best
	b.path = path
	b.path_idx = 0
	_set_state(b, Bot.BotState.MOVE)


# Hauler: etsi lahin kasa dig_site-alueilta ja reitita viereen.
func _assign_hauler(b: Bot) -> void:
	if dig_sites.is_empty():
		return  # ei louhittua tavaraa -> jaa IDLEen
	var bcx := int(b.pos.x) / DCELL
	var bcy := int(b.pos.y) / DCELL
	# Jarjesta ehdokkaat etaisyyden mukaan (Manhattan soluina)
	var cand := dig_sites.duplicate()
	cand.sort_custom(func(a, z): return (absi(a.x - bcx) + absi(a.y - bcy)) < (absi(z.x - bcx) + absi(z.y - bcy)))
	var scans := 0
	for cell in cand:
		if scans >= MAX_PILE_SCANS:
			break
		var key: int = cell.y * GW + cell.x
		if _cell_cooldown.has(key):
			continue
		scans += 1
		var pile := _find_pile(cell.x, cell.y)
		if int(pile["count"]) < PILE_MIN_PX:
			_cell_cooldown[key] = EMPTY_DIG_COOLDOWN
			continue
		var pos: Vector2 = pile["pos"]
		var path: PackedVector2Array = world.nav.find_path_px(b.pos, pos)
		if path.is_empty():
			_cell_cooldown[key] = FAIL_COOLDOWN
			continue
		b.target_cell = cell
		b.pickup_pos = pos
		b.path = path
		b.path_idx = 0
		_set_state(b, Bot.BotState.MOVE)
		return
	# Ei kelvollista kasaa -> jaa IDLEen, yrita seuraavalla kierroksella


# ============================================================
#  Tilakoneet (joka tikki)
# ============================================================

func _update_bot(b: Bot, delta: float) -> void:
	b.state_timer += delta
	# Telemetria: seuraa suurinta etaisyytta spawnista (assert_bots_moved-testia varten)
	var d := b.pos.distance_to(b.spawn_pos)
	if d > b.max_dist_from_spawn:
		b.max_dist_from_spawn = d
	match b.state:
		Bot.BotState.IDLE:
			_st_idle(b, delta)
		Bot.BotState.MOVE:
			_st_move(b, delta)
		Bot.BotState.WORK:
			_st_work(b, delta)
		Bot.BotState.CARRY_MOVE:
			_st_carry(b, delta)
		Bot.BotState.DUMP:
			_st_dump(b, delta)


func _st_idle(b: Bot, delta: float) -> void:
	# Leiju basen lahella
	if world.base == null:
		return
	var hp: Vector2 = world.base.spawn_pos() + b.hover_offset
	var to := hp - b.pos
	var dl := to.length()
	if dl > 2.0:
		var step := minf(Bot.MOVE_SPEED * delta, dl)
		b.pos += to / dl * step


func _st_move(b: Bot, delta: float) -> void:
	var arrived := _follow_path(b, delta)
	if not arrived:
		# Turvavahti: jos liike ei valmistu jarkevassa ajassa -> vapauta ja IDLE
		if b.state_timer > MOVE_MAX_TIME:
			_abort_job(b)
		return
	if b.role == Bot.Role.MINER:
		# Tarkista etta ollaan riittavan lahella louhittavaa solua
		var c := b.target_cell
		var cpx := Vector2(float(c.x * DCELL + DCELL / 2), float(c.y * DCELL + DCELL / 2))
		if b.pos.distance_to(cpx) > MINE_REACH_DIST:
			_abort_job(b)
			return
		if world.desig != null:
			world.desig.set_cell(c.x, c.y, D_MINING)
		# Nappaa solun louhittavat pikselit tyolistaksi (alhaalta ylos: irtomateriaali
		# valuu auki jaavaan tilaan). Louhinta etenee tata listaa pitkin work_accumin mukaan
		# -> valmistuu deterministisesti ajassa targets.size()/MINE_RATE.
		b.mine_targets = _cell_solids(c.x, c.y)
		b.mine_targets.sort_custom(_cmp_y_desc)
		b.mine_cursor = 0
		b.last_solids = 0x7fffffff
		b.stall_timer = 0.0
		b.work_accum = 0.0
		_set_state(b, Bot.BotState.WORK)
	else:
		# Hauler perilla kasalla
		b.work_accum = 0.0
		_set_state(b, Bot.BotState.WORK)


func _st_work(b: Bot, delta: float) -> void:
	if b.role == Bot.Role.MINER:
		_work_mine(b, delta)
	else:
		_work_vacuum(b, delta)


func _st_carry(b: Bot, delta: float) -> void:
	var arrived := _follow_path(b, delta)
	if arrived or b.state_timer > MOVE_MAX_TIME:
		_set_state(b, Bot.BotState.DUMP)


func _st_dump(b: Bot, _delta: float) -> void:
	if world.base != null and b.cargo_total > 0:
		world.money += world.base.accept_cargo(b.cargo)
	b.clear_cargo()
	_set_state(b, Bot.BotState.IDLE)
	# Hae heti seuraava tyo (pysy toimeliaana)
	_assign_hauler(b)


# ============================================================
#  Liike (waypoint-seuranta, ei fysiikkaa)
# ============================================================

# Palauttaa true kun reitti on kuljettu loppuun.
func _follow_path(b: Bot, delta: float) -> bool:
	if b.path_idx >= b.path.size():
		return true
	var budget := Bot.MOVE_SPEED * delta
	while budget > 0.0 and b.path_idx < b.path.size():
		var wp := b.path[b.path_idx]
		var to := wp - b.pos
		var d := to.length()
		if d <= ARRIVE_DIST:
			b.path_idx += 1
			continue
		var step := minf(budget, d)
		b.pos += to / d * step
		budget -= step
		if b.pos.distance_to(wp) <= ARRIVE_DIST:
			b.path_idx += 1
	return b.path_idx >= b.path.size()


# ============================================================
#  Louhinta (miner WORK)
# ============================================================

func _work_mine(b: Bot, delta: float) -> void:
	# Tyhja tyolista -> solu louhittu (tai siina ei ollut mitaan louhittavaa).
	if b.mine_targets.is_empty() or b.mine_cursor >= b.mine_targets.size():
		_finish_mining(b)
		return
	# Kerry tyota MINE_RATEn mukaan; kasittele niin monta tyolistan pikselia kuin budjetti riittaa.
	# Jokainen kasitelty pikseli = yksi "louhittu" px riippumatta materiaalista -> louhinta
	# etenee tasaisesti (ei jumissa granulaariin, ei stall-vahdin varassa kuin turvana).
	b.work_accum += Bot.MINE_RATE * delta
	var budget := int(b.work_accum)
	var done := 0
	while done < budget and b.mine_cursor < b.mine_targets.size():
		var p: Vector2i = b.mine_targets[b.mine_cursor]
		b.mine_cursor += 1
		var idx := p.y * SIM_W + p.x
		if world.building_pixels.has(idx):
			continue  # rakennuspikseli livahti listalle (ei pitaisi) -> ohita, ei kuluta budjettia
		var mat: int = world.grid[idx]
		if _mineable_lut[mat] != 1:
			continue  # jo muuttunut (esim. hauler imuroi) -> ohita
		# 25 % hukka: osa kivestä murenee pölyksi (tyhjaksi) eika tuota poimittavaa.
		if randf() < 0.25:
			world.mvp_write_pixel(p.x, p.y, MAT_EMPTY)
		else:
			# STONE->GRAVEL, WOOD->ASH kirjoitetaan irtomuotoon; granulaarit (DIRT/SAND/malmit/COAL)
			# ovat jo irtomuotoa (sama ID) ja jaavat paikoilleen haulerin poimittaviksi.
			var conv := _mine_convert(mat)
			if conv != mat:
				world.mvp_write_pixel(p.x, p.y, conv)
		done += 1
	b.work_accum -= float(done)
	# Tyolista katy lapi -> solu valmis. MINE_MAX_TIME jaa kovaksi turvakatoksi.
	if b.mine_cursor >= b.mine_targets.size() or b.state_timer >= MINE_MAX_TIME:
		_finish_mining(b)


func _finish_mining(b: Bot) -> void:
	var c := b.target_cell
	if c.x >= 0 and world.desig != null:
		world.desig.set_cell(c.x, c.y, D_NONE)
		var r: Rect2i = world.desig.cell_px_rect(c.x, c.y)
		world.nav.mark_dirty_px_rect(r)
		_add_dig_site(c)
		# Paivita naapurit heti (BLOCKED -> QUEUED kun tama aukesi)
		for dir in NAV_DIRS:
			_reeval_cell(c.x + dir.x, c.y + dir.y)
	b.target_cell = Vector2i(-1, -1)
	b.mine_targets = []
	b.mine_cursor = 0
	_set_state(b, Bot.BotState.IDLE)
	# Hae heti seuraava tyo
	_assign_miner(b)


# Kerää solun 16x16-alueen louhittavat kiinteat px (ei BEDROCK, ei building_pixels).
func _cell_solids(dx: int, dy: int) -> Array:
	var res: Array[Vector2i] = []
	var x0 := dx * DCELL
	var y0 := dy * DCELL
	for yy in DCELL:
		var y := y0 + yy
		if y < 0 or y >= SIM_H:
			continue
		var base_i := y * SIM_W
		for xx in DCELL:
			var x := x0 + xx
			if x < 0 or x >= SIM_W:
				continue
			var idx := base_i + x
			if world.building_pixels.has(idx):
				continue
			var mat: int = world.grid[idx]
			if _mineable_lut[mat] == 1:
				res.append(Vector2i(x, y))
	return res


func _mine_convert(mat: int) -> int:
	if mat == MAT_STONE:
		return MAT_GRAVEL
	if mat == MAT_WOOD:
		return MAT_ASH
	return mat  # DIRT/SAND/IRON_ORE/GOLD_ORE/COAL: sama ID (irtomuoto valuu CA:ssa)


func _reeval_cell(dx: int, dy: int) -> void:
	if dx < 0 or dx >= GW or dy < 0 or dy >= GH:
		return
	var d = world.desig
	if d == null or d.cells.size() < GW * GH:
		return
	var v: int = d.cells[dy * GW + dx]
	if v == D_BLOCKED and _has_open_neighbor(dx, dy):
		d.set_cell(dx, dy, D_QUEUED)
	elif v == D_QUEUED and not _has_open_neighbor(dx, dy):
		d.set_cell(dx, dy, D_BLOCKED)


func _add_dig_site(c: Vector2i) -> void:
	if dig_sites.has(c):
		return
	dig_sites.append(c)
	if dig_sites.size() > MAX_DIG_SITES:
		dig_sites.pop_front()


# ============================================================
#  Imurointi (hauler WORK)
# ============================================================

const VACUUM_RATE := 30.0   # px/s imunopeus (kuorma virtaa tayteen ~1.3 s @ CARRY_CAP=40)
const FX_MAX := 48          # yhtaaikaisten imuvirtapartikkelien katto per botti


func _work_vacuum(b: Bot, delta: float) -> void:
	b.work_accum += VACUUM_RATE * delta
	var budget := int(b.work_accum)
	if budget <= 0:
		return  # odota lisaa budjettia, pysy WORKissa (EI tulkita tyhjaksi kasaksi)
	var picked := _vacuum(b, budget)
	b.work_accum -= float(picked)
	if picked > 0:
		# Merkitse vapautunut tila nav-dirtyksi (frontier etenee, reitit paivittyvat)
		var cx := int(b.pickup_pos.x)
		var cy := int(b.pickup_pos.y)
		var x0 := maxi(cx - VACUUM_RADIUS, 0)
		var y0 := maxi(cy - VACUUM_RADIUS, 0)
		var x1 := mini(cx + VACUUM_RADIUS, SIM_W)
		var y1 := mini(cy + VACUUM_RADIUS, SIM_H)
		world.nav.mark_dirty_px_rect(Rect2i(x0, y0, x1 - x0, y1 - y0))
	# Paatos:
	if b.cargo_total >= Bot.CARRY_CAP:
		_start_dump(b)
		return
	if picked == 0:
		# Sateella ei enaa imtavaa
		if b.cargo_total > 0:
			_start_dump(b)
		else:
			# Kasa katosi ennen saapumista -> jaahylle ja IDLE
			_vacuum_give_up(b)
		return
	# Turvavahti: jos imu ei koskaan tayty tai tyhjene jarkevassa ajassa -> pakota ulos
	# WORK-tilasta (sama periaate kuin MOVE_MAX_TIME/MINE_MAX_TIME muualla).
	if b.state_timer > 6.0:
		if b.cargo_total > 0:
			_start_dump(b)
		else:
			_vacuum_give_up(b)
		return
	# Muuten jatka imua seuraavalla tikilla (pysy WORKissa)


# "Kasa katosi ennen saapumista" -haara: vapauta kohde jaahylle ja palaa IDLEen.
func _vacuum_give_up(b: Bot) -> void:
	if b.target_cell.x >= 0:
		_cell_cooldown[b.target_cell.y * GW + b.target_cell.x] = EMPTY_DIG_COOLDOWN
	b.target_cell = Vector2i(-1, -1)
	_set_state(b, Bot.BotState.IDLE)


# Imuroi granulaariset px sateella pickup_pos:n ymparilta. `budget` rajoittaa montako
# pikselia TALLA kutsulla imetaan (oletus = CARRY_CAP eli koko kuorma kerralla - sailyttaa
# suoran _vacuum(b)-kutsun vanhan kayttaytymisen testeissa). _work_vacuum antaa pienemman
# per-tikki-budjetin niin etta kuorma virtaa tayteen ajan yli eika hypy suoraan tayteen.
func _vacuum(b: Bot, budget: int = Bot.CARRY_CAP) -> int:
	var cx := int(b.pickup_pos.x)
	var cy := int(b.pickup_pos.y)
	var r := VACUUM_RADIUS
	var r2 := r * r
	var picked := 0
	var room := mini(Bot.CARRY_CAP - b.cargo_total, budget)
	if room <= 0:
		return picked
	for oy in range(-r, r + 1):
		var y := cy + oy
		if y < 0 or y >= SIM_H:
			continue
		var base_i := y * SIM_W
		for ox in range(-r, r + 1):
			if b.cargo_total >= Bot.CARRY_CAP or picked >= room:
				return picked
			if ox * ox + oy * oy > r2:
				continue
			var x := cx + ox
			if x < 0 or x >= SIM_W:
				continue
			var idx := base_i + x
			if world.building_pixels.has(idx):
				continue
			var mat: int = world.grid[idx]
			if _granular_lut[mat] == 1:
				world.mvp_write_pixel(x, y, MAT_EMPTY)
				b.add_cargo(mat, 1)
				picked += 1
				# Imuvirtapartikkeli: pikseli "lentaa" louhintakohdasta dronen voimakenttaan
				# (renderointi piirtaa taman bot.intake_fx-taulukon avulla).
				if b.intake_fx.size() < FX_MAX:
					b.intake_fx.append({"from": Vector2(float(x), float(y)), "mat": mat, "t": 0.0})
	return picked


func _start_dump(b: Bot) -> void:
	b.target_cell = Vector2i(-1, -1)
	if world.base == null:
		# Ei basea -> pida kuorma, odota
		_set_state(b, Bot.BotState.IDLE)
		return
	var target: Vector2 = world.base.intake_pos()
	var path: PackedVector2Array = world.nav.find_path_px(b.pos, target)
	if path.is_empty():
		# Base on avoimella alueella -> lenna suoraan (drone lapaisee kaiken)
		path = PackedVector2Array([target])
	b.path = path
	b.path_idx = 0
	_set_state(b, Bot.BotState.CARRY_MOVE)


# Etsi kasa dig_site-solun (dx,dy) sarakkeesta alaspain (kasat valuvat alas).
# Palauttaa { "count": int, "pos": Vector2 }.
func _find_pile(dx: int, dy: int) -> Dictionary:
	var x0 := dx * DCELL - PILE_SCAN_HALF_W
	var x1 := dx * DCELL + DCELL + PILE_SCAN_HALF_W
	var top := dy * DCELL
	var maxy := mini(top + PILE_SCAN_DEPTH, SIM_H)
	var count := 0
	var lowest_y := -1
	var y := top
	while y < maxy:
		var base_i := y * SIM_W
		var row_gran := 0
		var row_floor := false
		for x in range(x0, x1):
			if x < 0 or x >= SIM_W:
				continue
			var idx := base_i + x
			var mat: int = world.grid[idx]
			if _granular_lut[mat] == 1:
				row_gran += 1
				lowest_y = y
			elif world.building_pixels.has(idx) or _floor_lut[mat] == 1:
				row_floor = true
		count += row_gran
		# Pysahdy pohjaan kun kasa on loytynyt, tai jos umpikiinnea heti solun alla
		if row_floor and (count > 0 or y >= top + DCELL):
			break
		y += 1
	if count >= PILE_MIN_PX and lowest_y >= 0:
		var px := float(dx * DCELL) + float(DCELL) * 0.5
		return {"count": count, "pos": Vector2(px, float(lowest_y))}
	return {"count": count, "pos": Vector2.ZERO}


# ============================================================
#  Vikasieto / apurit
# ============================================================

# Vapauta varaus ja jaa IDLEen (aina laillinen ulospaasy tilakoneesta).
func _abort_job(b: Bot) -> void:
	var c := b.target_cell
	if c.x >= 0:
		if b.role == Bot.Role.MINER and world.desig != null and world.desig.cells.size() >= GW * GH:
			var v: int = world.desig.cells[c.y * GW + c.x]
			if v == D_CLAIMED or v == D_MINING:
				world.desig.set_cell(c.x, c.y, D_QUEUED)
		_cell_cooldown[c.y * GW + c.x] = FAIL_COOLDOWN
	b.target_cell = Vector2i(-1, -1)
	b.mine_targets = []
	b.mine_cursor = 0
	b.path = PackedVector2Array()
	b.path_idx = 0
	_set_state(b, Bot.BotState.IDLE)


func _set_state(b: Bot, s: int) -> void:
	b.state = s
	b.state_timer = 0.0


func _cmp_y_desc(a: Vector2i, c: Vector2i) -> bool:
	return a.y > c.y


# ============================================================
#  Visuaalinen kuormafysiikka (joka frame, EI logiikkatikin tahdissa)
# ============================================================
# Jousi-vaimennettu riippukuorma: kuorman painopiste roikkuu dronen vatsasta
# jousella. Levossa roikkuu alla, liikkeessa laahaa taakse-alas (traction-fiilis),
# kaannoksissa heiluu ja asettuu (heiluri), kiihdytyksessa nytkahtaa. Raskas lasti
# roikkuu matalammalla ja heiluu velttommin -> paino nakyy ilman erillista logiikkaa.
const RENDER_LERP := 0.0008    # pow-kanta render_pos-seurannalle (pienempi = napakampi)
const BELLY_OFFSET := 5.0      # kuorma roikkuu dronen "vatsasta"
const LOAD_SPRING := 55.0      # perusjaykkyys (tyhja/kevyt kuorma)
const LOAD_SPRING_FULL := 26.0 # jaykkyys taydella lastilla (veltompi -> enemman laahaa/heiluu)
const LOAD_GRAVITY := 60.0     # roikuttaa alas; lepoetaisyys = LOAD_GRAVITY / spring
const LOAD_DAMP := 0.10        # vaimennuksen pow-kanta/s (alivaimennettu = mehukas swing)
const FX_SPEED := 6.0          # imuvirtapartikkelin t-nopeus (1/s) -> lento ~0.17 s


func update_visuals(delta: float) -> void:
	var dt := clampf(delta, 0.0, 0.05)   # kattaa spike-framet
	for b in bots:
		if not b.visuals_init:
			b.render_pos = b.pos
			b.load_pos = b.pos + Vector2(0.0, BELLY_OFFSET + LOAD_GRAVITY / LOAD_SPRING)
			b.load_vel = Vector2.ZERO
			b.visuals_init = true
		# 1) Silota logiikkatikin nykays (render_pos seuraa bot.pos:ia pehmeasti)
		var a := 1.0 - pow(RENDER_LERP, dt)
		b.render_pos = b.render_pos.lerp(b.pos, a)
		# 2) Jousi-vaimennettu riippukuorma. Jaykkyys skaalautuu lastilla:
		#    tyhja = napakka (snappaa tiukalle), tays = veltto (laahaa & heiluu -> paino tuntuu).
		var anchor := b.render_pos + Vector2(0.0, BELLY_OFFSET)
		var frac := clampf(float(b.cargo_total) / float(Bot.CARRY_CAP), 0.0, 1.0)
		var spring := lerpf(LOAD_SPRING, LOAD_SPRING_FULL, frac)
		# Jousi vetaa kohti ankkuria; gravitaatio roikuttaa alas.
		# Lepoetaisyys ankkurista = LOAD_GRAVITY / spring -> raskas roikkuu matalammalla itsestaan.
		b.load_vel += (anchor - b.load_pos) * spring * dt
		b.load_vel += Vector2(0.0, LOAD_GRAVITY) * dt
		b.load_vel *= pow(LOAD_DAMP, dt)   # alivaimennettu -> 1-2 nakyvaa swingia
		b.load_pos += b.load_vel * dt
		# 3) Imuvirtapartikkelit: etene t 0->1, poista perilla olleet
		if not b.intake_fx.is_empty():
			var keep: Array = []
			for fx in b.intake_fx:
				fx["t"] = float(fx["t"]) + FX_SPEED * dt
				if float(fx["t"]) < 1.0:
					keep.append(fx)
			b.intake_fx = keep


# ============================================================
#  Piirto (canvasin lokaalit koordinaatit = sim-pikselit)
# ============================================================

func draw_bots(canvas: CanvasItem) -> void:
	# Piirtoaikainen leijuntahuojunta: VAIN visuaalinen, ei kosketa bot.pos-logiikkaa.
	# Jokaisella botilla oma vaihe (i * 1.7) -> lauma ei huoju synkassa, maailma nayttaa elavalta.
	var t := float(Time.get_ticks_msec()) / 1000.0
	for i in bots.size():
		var b := bots[i]
		var col: Color
		if b.role == Bot.Role.MINER:
			col = Color(0.88, 0.66, 0.25)   # amber/kulta
		else:
			col = Color(0.35, 0.62, 0.95)   # kirkas sininen
		# Huojunta vain y-suunnassa (sin-aalto per botti-indeksi). Pohjana kaytetaan silotettua
		# render_pos:ia (pehmeampi kuin raaka pos); jos visualisointia ei ole viela alustettu
		# (ensimmainen frame), fallbackaa raakaan pos:iin ettei botti nayta hyppaavan origosta.
		var base_pos: Vector2 = b.render_pos if b.visuals_init else b.pos
		var offset_y := sin(t * 2.5 + float(i) * 1.7) * 2.0
		var cx := base_pos.x
		var cy := base_pos.y + offset_y
		# Louhintalaser: miner joka louhii kohdepikselia -> nakyva sade botilta kohteeseen.
		# Piirretaan ENNEN runkoa jotta origo jaa rungon alle; osumapiste erottuu silti kohteessa.
		if b.role == Bot.Role.MINER and b.state == Bot.BotState.WORK \
				and not b.mine_targets.is_empty() and b.mine_cursor < b.mine_targets.size():
			var tp: Vector2i = b.mine_targets[b.mine_cursor]
			# Pieni vareily jotta sade elaa (ei staattinen viiva)
			var jit := Vector2(sin(t * 40.0 + i) * 1.0, cos(t * 37.0 + i) * 1.0)
			var target := Vector2(float(tp.x), float(tp.y)) + jit
			# Ulompi hehku
			canvas.draw_line(Vector2(cx, cy), target, Color(1.0, 0.35, 0.1, 0.5), 2.5)
			# Kirkas ydin
			canvas.draw_line(Vector2(cx, cy), target, Color(1.0, 0.8, 0.45, 0.95), 1.0)
			# Osumapiste
			canvas.draw_circle(target, 2.0, Color(1.0, 0.9, 0.55, 0.9))
		# Tumma reunus: 12x12 tausta keskitettyna -> 1 px reuna rungon ymparille
		canvas.draw_rect(Rect2(cx - 6.0, cy - 6.0, 12.0, 12.0), Color(0.05, 0.05, 0.08, 0.92))
		# Varillinen runko 10x10 keskitettyna
		canvas.draw_rect(Rect2(cx - 5.0, cy - 5.0, 10.0, 10.0), col)
		# Haulerin kannettu kuorma: nakyva fysikaalinen klontti (ei enaa abstrakti palkki).
		# Klontti roikkuu load_pos:n ymparilla (jousifysiikka paivittaa sen update_visualsissa),
		# joten se laahaa liikkeessa ja heiluu kaannoksissa -> tuntuu oikealta painavalta kuormalta.
		if b.role == Bot.Role.HAULER and b.cargo_total > 0:
			# 1) Imuvirtapartikkelit ensin (piirtyvat klontin taakse)
			for fx in b.intake_fx:
				var tt := 1.0 - pow(1.0 - clampf(float(fx["t"]), 0.0, 1.0), 2.0)
				var fp: Vector2 = (fx["from"] as Vector2).lerp(b.load_pos, tt)
				var fcol := _mat_color(int(fx["mat"]))
				fcol.a = 1.0 - tt * 0.3   # himmenee lahestyessaan klonttia
				canvas.draw_rect(Rect2(fp.x - 1.0, fp.y - 1.0, 2.0, 2.0), fcol)
			# 2) Kuormaklontti: 2x2 px per kannettu yksikko, kultaisen kulman spiraalilla
			# sironnettuna sateelle (tasainen tayttö) + smear liikesuuntaan (laahaa perassa).
			# Taysi-signaali: pieni "hengitys"-pulssi klontin sateeseen kun kuorma on tayssa.
			var full_pulse := 0.0
			if b.cargo_total >= Bot.CARRY_CAP:
				full_pulse = sin(t * 6.0) * 0.15 + 0.15   # ~0.0 .. 0.3
			var vel := b.load_vel.limit_length(5.0)
			var k := 0
			for mat in b.cargo:
				if k >= Bot.CARRY_CAP:
					break
				var c := _mat_color(int(mat))
				for _n in int(b.cargo[mat]):
					if k >= Bot.CARRY_CAP:
						break
					var ang := float(k) * 2.399963      # kultainen kulma -> tasainen tayttö
					var rad := (1.2 + sqrt(float(k)) * 0.9) * (1.0 + full_pulse)
					var jit := sin(t * 9.0 + float(k) * 1.3) * 0.5   # granulaarinen vare
					var p := b.load_pos + Vector2(cos(ang), sin(ang)) * rad
					p += vel * (float(k) / float(Bot.CARRY_CAP))     # koko klontti laahaa
					p += Vector2(jit, 0.0)
					canvas.draw_rect(Rect2(p.x - 1.0, p.y - 1.0, 2.0, 2.0), c)
					k += 1


# Materiaalivari (0-1 skaalattuna) render-shaderin paletista. Kaytetaan kuormaklontin
# ja imuvirtapartikkelien varitykseen ilman riippuvuutta shader-resursseihin.
func _mat_color(mat: int) -> Color:
	match mat:
		MAT_SAND:     return Color(0.859, 0.780, 0.447)
		MAT_ASH:      return Color(0.349, 0.329, 0.298)
		MAT_DIRT:     return Color(0.447, 0.318, 0.176)
		MAT_IRON_ORE: return Color(0.549, 0.420, 0.376)
		MAT_GOLD_ORE: return Color(0.718, 0.647, 0.247)
		MAT_COAL:     return Color(0.180, 0.169, 0.208)
		MAT_GRAVEL:   return Color(0.698, 0.588, 0.455)
		_:            return Color(0.60, 0.60, 0.60)
