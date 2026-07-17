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

# --- Idle-syyt (P0-1): JOHDETAAN tyonjaon tilannekuvasta get_fleet_statsissa, EI pysyvaa tilaa ---
# UI (ui_bot_status_overlay + ui.gd:n herateet) lukee naita. NO_QUEUED/ALL_BLOCKED koskevat
# mineria, NO_LOOSE hauleria. OK = idle mutta tyota on tulossa (frontier/kasa loytyy).
const IDLE_REASON_ACTIVE := 0    # ei idle (botilla on tyo)
const IDLE_REASON_OK := 1        # idle, mutta tyota on saatavilla (siirtyy pian tyohon)
const IDLE_REASON_NO_QUEUED := 2 # miner: ei yhtaan louhintadesignaatiota jaljella
const IDLE_REASON_ALL_BLOCKED := 3  # miner: designaatioita on, mutta yksikaan ei ole tavoitettavissa
const IDLE_REASON_NO_LOOSE := 4  # hauler: ei kerattavaa irtomateriaalia

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
const MAT_COPPER_ORE := 20   # lane C lisaa worldgeniin (suonet)
const MAT_RARE_EARTH := 21   # lane C lisaa worldgeniin (suonet)

# --- Ajastimet ja kynnykset ---
const ASSIGN_INTERVAL := 0.5       # tyonjako 2 Hz
const MINE_STALL_TIME := 2.0        # jos kiinteat eivat vahene taman ajan -> lopeta solu
const MINE_MAX_TIME := 20.0         # kova katto louhinnalle (turvavahti)
const MOVE_MAX_TIME := 30.0         # kova katto liikkeelle (turvavahti)
const FAIL_COOLDOWN := 2.0          # epaonnistunut kohde jaahylle
const EMPTY_DIG_COOLDOWN := 2.0     # tyhjentynyt dig_site jaahylle
const DUMP_RETRY_DELAY := 1.0        # s; mikaan dump-vyohyke ei hyvaksynyt kuormaa -> odota ennen uutta yritysta
# Kerros 3: ajallinen dumppi. Kuorma purkautuu DUMP_RATE * _crowd_factor px/s -> ruuhkainen
# dropoff hidastuu. DUMP_MAX_TIME on kova turvakatto: mitoitus Mk3 180 px lattiatahdilla
# (80 * CONGEST_FLOOR 0.25 = 20 px/s -> 9 s) < 12 s, joten normaali purku valmistuu aina ennen sita.
const DUMP_RATE := 80.0             # px/s purkunopeus (ennen ruuhkakerrointa)
const DUMP_MAX_TIME := 12.0         # kova katto dumpille (turvavahti): myy loput ja lopeta
const VACUUM_MAX_TIME := 30.0       # kova katto imulle (peralauta): ruuhkalattiallakin Mk3 tayttyy 24 s < tama
const ARRIVE_DIST := 4.0            # waypoint saavutettu kun etaisyys alle tama
const MINE_REACH_DIST := 48.0       # kuinka lahella solua louhinta saa alkaa
const VACUUM_RADIUS := 10           # haulerin imurointisade px
const MAX_DIG_SITES := 400          # dig_site-katto (B1: aktiivinen tyhjien siivous pitaa listan matalana)
const MAX_PILE_SCANS := 24          # montako dig_sitea skannataan / hauler-varaus
const PILE_MIN_PX := 5              # minimikasa jotta kannattaa hakea
const PILE_SCAN_DEPTH := 240        # 15 navsolua alaspain (15*16)
const PILE_SCAN_HALF_W := 4         # sarakkeen levennys molemmin puolin px

# --- Kerros 1: kohteiden hajautus (ruuhkanhallinta) ---
# Kaikki varaustieto JOHDETAAN bottien nykytilasta joka tyonjakokierroksella (_run_assignment,
# 2 Hz) -> ei pysyvia laskureita, joten varausvuoto (abort/roolinvaihto nollaa target_cellin)
# on rakenteellisesti mahdoton. Sakot ovat PEHMEITA: jos kaikki kandidaatit ovat sakotettuja,
# lahin valitaan silti -> tyo ei koskaan pysahdy (worst case = nykyinen kayttaytyminen).
const MINER_CROWD_PEN := 4          # frontier-sakko (soluina) toisen minerin kohteen vieressa
const PILE_CLAIM_UNIT := 40         # px-maara jonka yksi hakija "kuluttaa" kapasiteettilaskussa (Mk1 carry)
const PILE_MAX_CLAIMS := 3          # kova katto hakijoille per kasa
const PICKUP_CLAIM_PEN := 96.0      # metriikkasakko per samaan pickup-vyohykkeeseen jo menossa oleva hauler

# --- Kerros 2: separation-tyonto + ruuhkakerroin ---
# Botit ovat lentavia droneja (ei tormaystarkistusta, ei painovoimaa) -> pieni sijainnin
# tyonto levittaa lauman loyhaksi letkaksi rikkomatta mitaan. Tyonto on PEHMEA (max SEP_FACTOR
# osuus omasta nopeudesta) ja _follow_path ajetaan ensin taydella budjetilla -> nettoliike
# kohti waypointtia sailyy positiivisena (ei livelockia). Max tyonto/tikki ~0.8 px << ARRIVE_DIST.
const SEP_RADIUS := 12.0            # separation-tyonnon vaikutussade px
const SEP_FACTOR := 0.3            # tyonnon katto osuutena botin omasta move_speedista
const SEP_WORK_MULT := 0.5         # vaimennus WORK/DUMP-tiloissa (jono saa tiivistya tyopisteessa)
const CONGEST_RADIUS := 16.0       # ruuhkakertoimen naapurisade px
const CONGEST_K := 0.4            # ruuhkakertoimen jyrkkyys
const CONGEST_FREE := 1            # monta MUUTA bottia lahella on "ilmaisia" (2 bottia pisteessa = ei sakkoa)
const CONGEST_FLOOR := 0.25        # kertoimen lattia: tyo etenee aina

# 8 suuntaa (nav-naapurit)
const NAV_DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

# --- Tila ---
var bots: Array[Bot] = []
var world: Node = null
var dig_sites: Array[Vector2i] = []       # louhitut solut (designaatiokoordinaatit)
var _assign_timer: float = 0.0
var _cell_cooldown: Dictionary = {}        # cell_key (dy*GW+dx) -> jaljella oleva jaahy (s)

# Kierroskohtaiset varauskartat (kerros 1). Rakennetaan _run_assignmentin alussa bottien
# nykytilasta ja ovat VALIDEJA VAIN yhden tyonjakokierroksen sisalla — ei pysyvaa varaustilaa,
# joten varausvuotoa ei voi syntya. Suorat re-taskaus-kutsut (_finish_mining/_st_dump) kayttavat
# edellisen kierroksen tilannekuvaa; se on itsekorjautuva (seuraava kierros rakentaa uudet kartat).
var _round_hauler_claims: Dictionary = {}  # dig_site cell_key (y*GW+x) -> montako hauleria matkalla
var _round_miner_penalty: Dictionary = {}  # cell_key -> true: minerin kohteen ±1 ruuhkasakkoalue

# Kerros 2: crowd index — joka tikilla TYHJASTA uudelleenrakennettava naapurihakemisto.
# Johdettu tila (EI inkrementaalista kirjanpitoa) -> pomminvarma, ei kirjanpitovuotoa.
# key: navsoluavain cy*NW+cx botin posista (klampattu gridiin), value: Array[Bot] solun boteista.
var _crowd_index: Dictionary = {}

# Logistiikka (pickup/dump/base-filtteri). null = vanha kayttaytyminen (kaikki baseen).
# Asetetaan setupissa world.logistics:sta jos se on olemassa (lane G kytkee), tai suoraan.
var logistics: Logistics = null

# Osto & tunnisteet
var _bought_count: int = 0                 # ostettujen bottien maara (aloitus-2 EI laske) -> hinnankorotus
var _next_id: int = 0                       # monotoninen bot-id-jakaja

# A4/B2: frontier-cache. _scan_designations rakentaa taman kerran/kierros (yksi kevyt
# byte-skannaus + naapuritarkistus vain designoiduille soluille); _assign_miner valitsee
# tasta lahimman EIKA skannaa koko 6240-gridia per botti.
var _frontier_cells: Array[Vector2i] = []

# P0-1: designaatioiden tilannekooste, paivitetaan _scan_designationsissa (2 Hz). get_fleet_stats
# lukee naita (ei omaa skannausta) -> idle-syyt ja UI-herateet ilman per-frame-gridiskannausta.
var _scan_blocked_count: int = 0    # D_BLOCKED-solut (designaatioita on mutta ei tavoitettavissa)
var _scan_working_count: int = 0    # D_CLAIMED + D_MINING (louhinta kaynnissa)
# P0-3: onko yksikaan designaatiosolu koskaan louhittu valmiiksi (estaa "merkkaa lisaa" -herate
# heti pelin alussa ennen ekaa designaatiota). Nollataan setupissa, kasvaa _finish_miningissa.
var _designations_consumed: int = 0

# LUT:t suoraan mat-ID:lla (256 alkiota)
var _mineable_lut: PackedByteArray         # miner louhii nama
var _granular_lut: PackedByteArray         # hauler poimii nama
var _floor_lut: PackedByteArray            # kasan pysayttava kiintea pohja


# ============================================================
#  Setup
# ============================================================

func setup(world: Node) -> void:
	self.world = world
	# Nollaa tila (uusi peli / regenerate): osto, tunnisteet, frontier, jaahyt.
	_bought_count = 0
	_next_id = 0
	_frontier_cells.clear()
	_cell_cooldown.clear()
	_assign_timer = 0.0
	_scan_blocked_count = 0
	_scan_working_count = 0
	_designations_consumed = 0
	# Poimi logistics-instanssi worldista jos se on jo luotu (lane G kytkee). null on ok.
	if logistics == null:
		logistics = world.get("logistics")
	_build_luts()


func _build_luts() -> void:
	_mineable_lut = PackedByteArray()
	_mineable_lut.resize(256)
	_granular_lut = PackedByteArray()
	_granular_lut.resize(256)
	_floor_lut = PackedByteArray()
	_floor_lut.resize(256)
	# Louhittavat kiinteat (miner). COPPER/RARE_EARTH mukana malmeina (kuten IRON/GOLD_ORE).
	for m in [MAT_STONE, MAT_DIRT, MAT_SAND, MAT_IRON_ORE, MAT_GOLD_ORE, MAT_COAL, MAT_WOOD,
			MAT_COPPER_ORE, MAT_RARE_EARTH]:
		_mineable_lut[m] = 1
	# Granulaariset (haulerin poimittavat). COPPER/RARE_EARTH imuroitavia (jauheita).
	for m in [MAT_SAND, MAT_DIRT, MAT_GRAVEL, MAT_IRON_ORE, MAT_GOLD_ORE, MAT_COAL, MAT_ASH,
			MAT_COPPER_ORE, MAT_RARE_EARTH]:
		_granular_lut[m] = 1
	# Kasan pysayttava kiintea pohja (ei-granulaarinen kiintea)
	for m in [MAT_STONE, MAT_WOOD, MAT_WOOD_FALLING, MAT_GLASS, MAT_IRON, MAT_GOLD, MAT_BEDROCK]:
		_floor_lut[m] = 1


func add_bot(role: int, p: Vector2) -> Bot:
	var b := Bot.new()
	b.id = _next_id
	_next_id += 1
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
#  Osto, roolinvaihto, upgrade, tilastot (A1 + A2 — API_CONTRACT_demo.md)
# ============================================================

# M2: Botti rakennetaan inventaarion IRON_ORE:sta rahan sijaan. Resepti kasvaa
# rakennettujen bottien maaran (_bought_count) mukaan: cost_px = ceil(10 * 1.35^n).
# Aloitusbotit (2 kpl) eivat kasvata kerrointa -> ensimmainen rakennettu (3. botti) = 10 px.
# Progressio: 10, 14, 19, 26, 35, 47, ...
func next_bot_cost() -> Dictionary:
	var px := int(ceil(10.0 * pow(1.35, float(_bought_count))))
	return { MAT_IRON_ORE: px }


# Onko varaa rakentaa (world.inventory kattaa reseptin)?
func can_build_bot() -> bool:
	if world == null:
		return false
	return world.can_afford_materials(next_bot_cost())


# Rakenna botti: kuluta materiaalit inventaariosta, spawnaa basesta. Korvaa vanhan
# rahapohjaisen buy_bot():in. true jos onnistui, false jos ei varaa tai basea ei ole.
func build_bot(role: int) -> bool:
	if world == null or world.base == null or not is_instance_valid(world.base):
		return false
	if not world.spend_materials(next_bot_cost()):
		return false
	_bought_count += 1
	add_bot(role, world.base.spawn_pos())
	return true


# Vaihda botin rooli lennossa. Keskeyttaa tyon siististi:
#   - varattu louhintadesignaatio (CLAIMED/MINING) -> QUEUED (muille vapaaksi, ei jaahya),
#   - cargo dumpataan baseen ensin jos ei tyhja (heti jos tyhja),
#   - tilakone nollataan IDLEen.
func set_role(bot_id: int, new_role: int) -> void:
	var b := _bot_by_id(bot_id)
	if b == null or b.role == new_role:
		return
	# 1) Vapauta varattu designaatio takaisin jonoon (ei jaahya -> toinen miner voi napata heti)
	_release_designation(b)
	# 2) Purki mahdollinen kuorma baseen (haulerilla voi olla lastia kesken).
	#    M1: deposit_cargo reitittaa politiikan mukaan (SELL -> money, STORE -> inventory).
	if b.cargo_total > 0:
		world.deposit_cargo(b.cargo)
	b.clear_cargo()
	# 3) Nollaa tilakonedata ja vaihda rooli
	b.role = new_role
	b.target_cell = Vector2i(-1, -1)
	b.pickup_pos = Vector2.ZERO
	b.mine_targets = []
	b.mine_cursor = 0
	b.dump_target = {}
	b.path = PackedVector2Array()
	b.path_idx = 0
	_set_state(b, Bot.BotState.IDLE)


# Upgrade botti seuraavaan tieriin. Mk1->Mk2 400, Mk2->Mk3 900. false jos ei varaa tai jo Mk3.
func upgrade_bot(bot_id: int) -> bool:
	var b := _bot_by_id(bot_id)
	if b == null or b.tier >= Bot.MAX_TIER:
		return false
	var price := upgrade_price(bot_id)
	if world == null or world.money < price:
		return false
	world.money -= price
	b.tier += 1
	return true


# Seuraavan upgraden hinta: Mk1->Mk2 400, Mk2->Mk3 900, 0 jos jo Mk3 (tai tuntematon botti).
func upgrade_price(bot_id: int) -> int:
	var b := _bot_by_id(bot_id)
	if b == null:
		return 0
	match b.tier:
		1: return 400
		2: return 900
		_: return 0


# Laumatilastot UI:lle (API_CONTRACT_demo.md). "aktiivinen" = ei IDLE.
func get_fleet_stats() -> Dictionary:
	var miners := 0
	var haulers := 0
	var miners_active := 0
	var haulers_active := 0
	var bot_list: Array = []
	for b in bots:
		var active: bool = b.state != Bot.BotState.IDLE
		if b.role == Bot.Role.MINER:
			miners += 1
			if active:
				miners_active += 1
		else:
			haulers += 1
			if active:
				haulers_active += 1
		# pos/cargo_total/carry_cap: additiivisia read-only-kenttiä (UI-REDESIGN Vaihe 4,
		# scripts/ui_bot_status_overlay.gd) — eivät vaikuta bottilogiikkaan, vain UI lukee niitä.
		# idle_reason (P0-1): johdettu tilannekuvasta, kertoo MIKSI botti on idle (overlay + herateet).
		bot_list.append({
			"id": b.id, "role": b.role, "tier": b.tier, "state": b.state,
			"pos": b.pos, "cargo_total": b.cargo_total, "carry_cap": b.carry_cap(),
			"idle_reason": _idle_reason_for(b),
		})
	# P0-1/P0-3: laumatason tilannekooste UI-heratteita varten (kaikki JOHDETTUA tilaa,
	# paivitetaan _scan_designationsissa 2 Hz -> ei omaa gridiskannausta per kutsu).
	var loose: bool = _has_loose_material()
	return {
		"miners": miners, "haulers": haulers,
		"miners_active": miners_active, "haulers_active": haulers_active,
		"bots": bot_list,
		# Designaatiotilanne: frontier = tavoitettavat QUEUED-solut, blocked = tavoittamattomat,
		# working = louhinta kesken (CLAIMED/MINING). "any_designation" = onko yhtaan tyokohdetta jaljella.
		"frontier": _frontier_cells.size(),
		"desig_blocked": _scan_blocked_count,
		"desig_working": _scan_working_count,
		"any_designation": (_frontier_cells.size() + _scan_blocked_count + _scan_working_count) > 0,
		"loose_material": loose,
		"designations_consumed": _designations_consumed,
	}


func bot_count() -> int:
	return bots.size()


# P0-1: johda idle-botin syy tyonjaon tilannekuvasta (EI pysyvaa tilaa — laske joka kutsulla
# cachetetuista _scan_*-kentista). Ei-idle botti -> ACTIVE. Miner: frontier tyhja + designaatioita
# on -> ALL_BLOCKED; ei designaatioita lainkaan -> NO_QUEUED; muuten OK (tyo tulossa). Hauler:
# kuorma tallella tai kerattavaa on -> OK; muuten NO_LOOSE.
func _idle_reason_for(b: Bot) -> int:
	if b.state != Bot.BotState.IDLE:
		return IDLE_REASON_ACTIVE
	if b.role == Bot.Role.MINER:
		if not _frontier_cells.is_empty():
			return IDLE_REASON_OK
		if _scan_blocked_count > 0 or _scan_working_count > 0:
			return IDLE_REASON_ALL_BLOCKED
		return IDLE_REASON_NO_QUEUED
	# HAULER
	if b.cargo_total > 0 or _has_loose_material():
		return IDLE_REASON_OK
	return IDLE_REASON_NO_LOOSE


# Onko kerattavaa irtomateriaalia tarjolla (hauler-idle-syyn heuristiikka). Halpa tarkistus:
# dig_site-kasoja tai aktiivisia pickup-vyohykkeita on -> oletetaan etta kerattavaa loytyy.
func _has_loose_material() -> bool:
	if not dig_sites.is_empty():
		return true
	if logistics != null and not logistics.pickup_zones().is_empty():
		return true
	return false


func _bot_by_id(bot_id: int) -> Bot:
	for b in bots:
		if b.id == bot_id:
			return b
	return null


# Vapauta botin varaama louhintadesignaatio takaisin QUEUEDiksi (ei jaahya). Kaytetaan
# roolinvaihdossa: solu on heti muiden minereiden napattavissa.
func _release_designation(b: Bot) -> void:
	var c := b.target_cell
	if c.x < 0 or b.role != Bot.Role.MINER:
		return
	if world.desig == null or world.desig.cells.size() < GW * GH:
		return
	var v: int = world.desig.cells[c.y * GW + c.x]
	if v == D_CLAIMED or v == D_MINING:
		world.desig.set_cell(c.x, c.y, D_QUEUED)


# ============================================================
#  Tikki
# ============================================================

func tick(delta: float) -> void:
	if world == null:
		return
	_tick_cooldowns(delta)
	# Kerros 2: rakenna naapurihakemisto ENNEN tyonjakoa ja tilakoneita (johdettu, tuore tila).
	_build_crowd_index()
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
#  Kerros 2: crowd index + separation
# ============================================================

# Rakenna naapurihakemisto TYHJASTA joka tikilla (O(n)). Johdettu tila -> ei varausvuotoa.
# Jokainen botti lisataan navsoluunsa; koordinaatit klampataan gridiin ENNEN jakoa NCELLilla.
func _build_crowd_index() -> void:
	_crowd_index.clear()
	for b in bots:
		var cx := clampi(int(b.pos.x), 0, SIM_W - 1) / NCELL
		var cy := clampi(int(b.pos.y), 0, SIM_H - 1) / NCELL
		var key := cy * NW + cx
		if _crowd_index.has(key):
			(_crowd_index[key] as Array).append(b)
		else:
			_crowd_index[key] = [b]


# Palauta botin naapurit sateella `radius`. Skannaa 3x3 navsolua botin solun ymparilta
# (16 px solut kattavat <=16 px sateen). Palauttaa [toinen_botti, etaisyys]-pareja joilla
# dist <= radius, itsensa poislukien (VIITTAUSvertailu, ei posivertailu — kaksi bottia voi
# olla samassa pisteessa).
func _crowd_neighbors(b: Bot, radius: float) -> Array:
	var res: Array = []
	var bcx := clampi(int(b.pos.x), 0, SIM_W - 1) / NCELL
	var bcy := clampi(int(b.pos.y), 0, SIM_H - 1) / NCELL
	for oy in range(-1, 2):
		var cy := bcy + oy
		if cy < 0 or cy >= NH:
			continue
		var row := cy * NW
		for ox in range(-1, 2):
			var cx := bcx + ox
			if cx < 0 or cx >= NW:
				continue
			var key := row + cx
			if not _crowd_index.has(key):
				continue
			for other in (_crowd_index[key] as Array):
				if other == b:
					continue
				var dd: float = b.pos.distance_to(other.pos)
				if dd <= radius:
					res.append([other, dd])
	return res


# Ruuhkakerroin 0..1 (KERROS 3): kaytossa imussa ja dumpissa (_work_vacuum/_st_dump).
# Hidastaa tyotahtia tungoksessa: n = muut botit CONGEST_RADIUS-sateella. Kayra: 0-1 naapuria
# -> 1.0; 2 -> ~0.714; 3 -> ~0.556; paljon -> lattia CONGEST_FLOOR (0.25).
func _crowd_factor(b: Bot) -> float:
	var n := _crowd_neighbors(b, CONGEST_RADIUS).size()
	return maxf(1.0 / (1.0 + CONGEST_K * float(maxi(0, n - CONGEST_FREE))), CONGEST_FLOOR)


# Separation-tyonto: levita paallekkaiset botit loyhaksi letkaksi (pieni overlap sallittu,
# EI kova tormays). Ajetaan _update_botin lopussa kaikille tiloille.
func _apply_separation(b: Bot, delta: float) -> void:
	var neighbors := _crowd_neighbors(b, SEP_RADIUS)
	if neighbors.is_empty():
		return
	var push := Vector2.ZERO
	for pair in neighbors:
		var other: Bot = pair[0]
		var dd: float = pair[1]
		if dd < 0.001:
			# Taysin paallekkain (esim. basen spawn) -> deterministinen id-suunta.
			# EI randf: toistettavuus testeissa + NaN-suoja (ei nollajakoa).
			push += Vector2.RIGHT.rotated(float(b.id) * 2.399963)
		else:
			# Suunta pois naapurista, paino kasvaa mita lahempana ollaan (1 kun paallekkain).
			push += (b.pos - other.pos) / dd * (1.0 - dd / SEP_RADIUS)
	# WORK/DUMP vaimennetaan: jono saa tiivistya tyopisteessa (ei tyonna pois tyosta).
	var mult := SEP_WORK_MULT if (b.state == Bot.BotState.WORK or b.state == Bot.BotState.DUMP) else 1.0
	b.pos += push.limit_length(1.0) * b.move_speed() * SEP_FACTOR * mult * delta
	# Klampaa sim-rajoihin (drone ei saa karata ruudukon ulkopuolelle).
	b.pos.x = clampf(b.pos.x, 0.0, float(SIM_W - 1))
	b.pos.y = clampf(b.pos.y, 0.0, float(SIM_H - 1))


# ============================================================
#  Tyonjako (2 Hz)
# ============================================================

func _run_assignment() -> void:
	# Lazy-poiminta: jos lane G loi logistics-instanssin setupin jalkeen, ota se kayttoon.
	if logistics == null and world != null:
		logistics = world.get("logistics")
	_scan_designations()
	_build_round_claims()
	for b in bots:
		if b.state == Bot.BotState.IDLE:
			if b.role == Bot.Role.MINER:
				_assign_miner(b)
			else:
				_assign_hauler(b)


# Rakenna kierroskohtaiset varauskartat bottien nykytilasta (kerros 1). Vain MOVE/WORK-tilaiset
# botit "varaavat" kohteensa (IDLE ei ole viela sitoutunut mihinkaan). Kartat johdetaan aina
# tuoreesta tilasta -> ei pysyvaa laskuria, ei varausvuotoa.
func _build_round_claims() -> void:
	_round_hauler_claims.clear()
	_round_miner_penalty.clear()
	for b in bots:
		if b.state != Bot.BotState.MOVE and b.state != Bot.BotState.WORK:
			continue
		if b.target_cell.x < 0:
			continue  # hauler pickup-vyohykkeella (ei dig_site-solua) -> ei kuulu dig_site-varaukseen
		if b.role == Bot.Role.HAULER:
			var key: int = b.target_cell.y * GW + b.target_cell.x
			_round_hauler_claims[key] = int(_round_hauler_claims.get(key, 0)) + 1
		else:  # MINER
			_mark_miner_penalty(b.target_cell.x, b.target_cell.y)


# Merkitse minerin kohdesolun ±1-naapurusto (Chebyshev ≤1 = 9 solua, klampattu gridiin)
# ruuhkasakkoalueeksi. Kaytetaan seka olemassa olevista MOVE/WORK-minereista etta saman
# kierroksen tuoreista varauksista -> minerit hajautuvat frontieria pitkin.
func _mark_miner_penalty(cx: int, cy: int) -> void:
	for oy in range(-1, 2):
		var y := cy + oy
		if y < 0 or y >= GH:
			continue
		var row := y * GW
		for ox in range(-1, 2):
			var x := cx + ox
			if x < 0 or x >= GW:
				continue
			_round_miner_penalty[row + x] = true


# Skannaa designaatiogridi: QUEUED <-> BLOCKED nav-naapuruuden mukaan JA rakenna frontier-cache.
# (A4/B2) Ulkosilmukka on yksi kevyt byte-skannaus (6240 vertailua); kallis _has_open_neighbor
# ajetaan VAIN designoiduille soluille (QUEUED/BLOCKED), ei koko gridille. _frontier_cells
# taytetaan louhittavilla QUEUED-soluilla -> _assign_miner valitsee tasta lahimman eika
# skannaa koko gridia per botti. Aja 2 Hz, ei joka framella.
func _scan_designations() -> void:
	_frontier_cells.clear()
	# P0-1: nollaa tilannekooste — paivittyy taman skannauksen aikana (get_fleet_stats lukee).
	_scan_blocked_count = 0
	_scan_working_count = 0
	var d = world.desig
	if d == null or d.cells.size() < GW * GH:
		return
	var cells: PackedByteArray = d.cells
	var n := GW * GH
	for i in n:
		var v: int = cells[i]
		if v == D_CLAIMED or v == D_MINING:
			_scan_working_count += 1   # louhinta kaynnissa (miner varannut/louhii solua)
			continue
		if v != D_QUEUED and v != D_BLOCKED:
			continue
		var dx := i % GW
		var dy := i / GW
		var has_open := _has_open_neighbor(dx, dy)
		if v == D_QUEUED:
			if has_open:
				_frontier_cells.append(Vector2i(dx, dy))
			else:
				d.set_cell(dx, dy, D_BLOCKED)
				_scan_blocked_count += 1
		else:  # D_BLOCKED
			if has_open:
				d.set_cell(dx, dy, D_QUEUED)
				_frontier_cells.append(Vector2i(dx, dy))
			else:
				_scan_blocked_count += 1


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


# Miner: varaa lahin louhittava solu frontier-cachesta, reitita viereen.
# (A4/B2) Iteroi VAIN _frontier_cells-listaa (louhittavat QUEUED-solut), ei koko 6240-gridia.
# Tarkistaa etta solu on yha D_QUEUED (toinen miner saattoi varata sen tallä kierroksella).
func _assign_miner(b: Bot) -> void:
	var d = world.desig
	if d == null or d.cells.size() < GW * GH:
		return
	if _frontier_cells.is_empty():
		return  # ei tyota -> jaa IDLEen
	var bcx := int(b.pos.x) / DCELL
	var bcy := int(b.pos.y) / DCELL
	var best := Vector2i(-1, -1)
	var best_dist := 0x7fffffff
	for cell in _frontier_cells:
		var key: int = cell.y * GW + cell.x
		if d.cells[key] != D_QUEUED:
			continue  # varattu/muuttunut tallä kierroksella
		if _cell_cooldown.has(key):
			continue
		var dist := absi(cell.x - bcx) + absi(cell.y - bcy)
		# PEHMEA ruuhkasakko: toisen minerin kohteen viereinen solu (±1) on vahemman houkutteleva.
		# Sakko vain kasvattaa etaisyytta -> jos KAIKKI kandidaatit ovat sakotettuja, lahin
		# sakotettu valitaan silti (tyo ei koskaan pysahdy).
		if _round_miner_penalty.has(key):
			dist += MINER_CROWD_PEN
		if dist < best_dist:
			best_dist = dist
			best = cell
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
	# Saman kierroksen seuraavat minerit hajautuvat: merkitse tama tuore varaus sakkoalueeksi.
	_mark_miner_penalty(best.x, best.y)


# Hauler: etsi lahin kasa (1) designaatioalueiden dig_site-kasoista, ja jos ei loydy,
# (2) logisticsin pickup-vyohykkeilta. Reitita kasalle ja siirry MOVEen.
func _assign_hauler(b: Bot) -> void:
	# Kesken oleva kuorma (dump hylattiin viime yrityksella) -> yrita purkaa uudelleen sen
	# sijaan etta haettaisiin lisaa tyota. Ei uutta pickup/dig-hakua kesken purun uudelleenyrityksen.
	if b.cargo_total > 0:
		if b.dump_retry_cooldown <= 0.0:
			_start_dump(b)
		return
	if _assign_hauler_dig(b):
		return
	# Ei dig_site-kasaa -> yrita pickup-vyohykkeita (GDD §4.3)
	if logistics != null:
		_assign_hauler_pickup(b)


# Dig_site-kasat (louhittu irtomateriaali designaatioalueilla). Palauttaa true jos tyo loytyi.
# (B1) Tyhjentyneet dig_sitet poistetaan listasta tassa -> lista pysyy matalana eika FIFO
# koskaan pudota viela-materiaalia sisaltavia kasoja.
func _assign_hauler_dig(b: Bot) -> bool:
	if dig_sites.is_empty():
		return false
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
		# (Kerros 1) Kova katto hakijoille per kasa — HALPA esitarkistus ennen skannausbudjettia:
		# jos jo PILE_MAX_CLAIMS hauleria matkalla tahan soluun, ohita heti (ei kuluta _find_pilea).
		var claims: int = int(_round_hauler_claims.get(key, 0))
		if claims >= PILE_MAX_CLAIMS:
			continue
		scans += 1
		var pile := _find_pile(cell.x, cell.y)
		if int(pile["count"]) < PILE_MIN_PX:
			_remove_dig_site(cell)  # (B1) vahvistetusti tyhja -> pois listasta
			_cell_cooldown[key] = EMPTY_DIG_COOLDOWN
			continue
		# (Kerros 1) Kapasiteetti kasan koon mukaan: pieni kasa -> yksi hakija, iso -> useampi
		# (katto PILE_MAX_CLAIMS). Varattu-mutta-validi kasa EI mene _cell_cooldowniin — se on vain
		# varattu (ei rikki), joten se vapautuu heti kun varaajat vahenevat tai kasa kasvaa.
		var capacity := clampi(int(ceil(float(pile["count"]) / float(PILE_CLAIM_UNIT))), 1, PILE_MAX_CLAIMS)
		if claims >= capacity:
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
		# Saman kierroksen seuraavat haulerit hajautuvat: merkitse tama tuore varaus.
		_round_hauler_claims[key] = claims + 1
		return true
	return false  # ei kelvollista kasaa talla kierroksella


# Pickup-vyohykkeet (logistics): valitse prio-painotetusti lahin vyohyke jolla on kasa.
func _assign_hauler_pickup(b: Bot) -> void:
	var zones := logistics.pickup_zones()
	if zones.is_empty():
		return
	var bpos := b.pos
	var best_pos := Vector2(-1.0, -1.0)
	var best_metric := INF
	var best_path := PackedVector2Array()
	for z in zones:
		var rect: Rect2i = z["rect"]
		var pile := _find_pile_in_rect(rect, int(z["filter_mask"]))
		if int(pile["count"]) < PILE_MIN_PX:
			continue
		var pos: Vector2 = pile["pos"]
		# Korkea prioriteetti pienentaa tehollista etaisyytta (haetaan ensin).
		var prio: int = int(z.get("priority", 0))
		var metric := bpos.distance_to(pos) - float(prio) * 64.0
		# (Kerros 1) Ruuhkasakko: montako MUUTA hauleria on jo menossa tahan pickup-vyohykkeeseen.
		# Kasvattaa tehollista etaisyytta -> haulerit hajautuvat eri vyohykkeille. Laske live per
		# kutsu iteroimalla bots-listaa (n pieni) -> saman kierroksen aiemmat tyonannot nakyvat heti.
		metric += PICKUP_CLAIM_PEN * float(_pickup_zone_congestion(rect, b))
		if metric >= best_metric:
			continue
		var path: PackedVector2Array = world.nav.find_path_px(bpos, pos)
		if path.is_empty():
			continue
		best_metric = metric
		best_pos = pos
		best_path = path
	if best_pos.x < 0.0:
		return
	b.target_cell = Vector2i(-1, -1)  # pickup-vyohyke, ei dig_site-solua
	b.pickup_pos = best_pos
	b.path = best_path
	b.path_idx = 0
	_set_state(b, Bot.BotState.MOVE)


# (Kerros 1) Montako MUUTA hauleria on jo menossa/toissa tahan pickup-vyohykkeeseen (rect).
# Pickup-keikka tunnistetaan target_cell.x < 0:sta (ei dig_site-solua) + pickup_pos rectin sisalta.
# Laske live per kutsu (n pieni) -> saman kierroksen aiemmat pickup-tyonannot nakyvat automaattisesti.
func _pickup_zone_congestion(rect: Rect2i, self_bot: Bot) -> int:
	var n := 0
	for other in bots:
		if other == self_bot or other.role != Bot.Role.HAULER:
			continue
		if other.state != Bot.BotState.MOVE and other.state != Bot.BotState.WORK:
			continue
		if other.target_cell.x >= 0:
			continue  # dig_site-keikalla, ei pickup-vyohykkeella
		if rect.has_point(Vector2i(int(other.pickup_pos.x), int(other.pickup_pos.y))):
			n += 1
	return n


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
	# Kerros 2: separation-tyonto KAIKILLE tiloille, tilakone-matchin JALKEEN. _follow_path
	# (MOVE/CARRY) ajettiin jo taydella budjetilla -> nettoliike waypointtia kohti sailyy
	# positiivisena, ei livelockia. Tyonto on max SEP_FACTOR osuus omasta nopeudesta.
	_apply_separation(b, delta)


func _st_idle(b: Bot, delta: float) -> void:
	# Dump-uudelleenyrityksen jaahy (ei hyvaksyvaa dump-vyohyketta viime yrityksella).
	b.dump_retry_cooldown = maxf(0.0, b.dump_retry_cooldown - delta)
	# Leiju basen lahella
	if world.base == null:
		return
	var hp: Vector2 = world.base.spawn_pos() + b.hover_offset
	var to := hp - b.pos
	var dl := to.length()
	if dl > 2.0:
		var step := minf(b.move_speed() * delta, dl)
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
		# Kerros 3: nollaa purkubudjetti ennen ajallista dumppia (ei imu-tilan jaannosta).
		b.work_accum = 0.0
		_set_state(b, Bot.BotState.DUMP)


# Kerros 3: AJALLINEN dumppi. Kuorma purkautuu DUMP_RATE * _crowd_factor px/s tahtiin
# (ruuhkainen dropoff hidastuu -> ruuhka maksaa oikeasti). Joka tikilla sijoitetaan enintaan
# int(work_accum) px kohteeseen; kun kohde tayttyy tai kuorma tyhjenee, dump paattyy.
# SAILYVYYSINVARIANTTI (joka polku): jokainen kuorma-px joko kirjoitetaan maailmaan TAI myydaan
# accept_cargo:lla — kuormaa ei koskaan kadoteta eika tuplata.
func _st_dump(b: Bot, delta: float) -> void:
	# Turvavahti ENSIN: dump ei saa kestaa loputtomiin (esim. kohde jumissa) -> myy jaljella
	# oleva kuorma baseen, siivoa ja palaa IDLEen. DUMP_MAX_TIME mitoitettu niin etta taysi
	# Mk3-kuorma valuu lattiatahdillakin (80*0.25=20 px/s -> 180 px 9 s) ennen tata kattoa.
	if b.state_timer > DUMP_MAX_TIME:
		_sell_remaining_cargo(b)
		_finish_dump(b)
		return
	# Kuorma jo tyhja -> valmistu heti (hae seuraava tyo).
	if b.cargo_total <= 0:
		_finish_dump(b)
		return
	# Kerry purkubudjettia; ruuhka hidastaa (sama _crowd_factor kuin imussa).
	b.work_accum += DUMP_RATE * _crowd_factor(b) * delta
	var budget := int(b.work_accum)
	if budget <= 0:
		return  # odota lisaa budjettia, pysy DUMPissa
	# Sijoita enintaan budget px kohteeseen (kohde valitaan dump_target-lipusta). Palauttaa
	# montako px TOSIASIASSA sijoitettiin ja vahentaa kuorman sen mukaan.
	var placed := _place_cargo_budget(b, budget)
	b.work_accum -= float(placed)
	# Kohde tayttyi kesken purun (budjettia jai mutta kuormaa on viela) -> myy loput ja lopeta.
	if placed < budget and b.cargo_total > 0:
		_sell_remaining_cargo(b)
		_finish_dump(b)
		return
	# Kuorma tyhjeni talla tikilla -> valmistu.
	if b.cargo_total <= 0:
		_finish_dump(b)


# Dump valmis: nollaa dump-tila, palaa IDLEen ja hae heti seuraava tyo (pysy toimeliaana).
# Kutsutaan VAIN kun kuorma on jo kirjattu (tyhjentynyt tai myyty) -> ei nollaa kuormaa itse,
# jottei sailyvyysinvariantti riko (kadonnut kuorma).
func _finish_dump(b: Bot) -> void:
	b.dump_target = {}
	_set_state(b, Bot.BotState.IDLE)
	_assign_hauler(b)


# Purki koko jaljella oleva kuorma baseen — dumpin leftover/watchdog-fallback.
# M1: deposit_cargo reitittaa politiikan mukaan (SELL -> money, STORE -> inventory).
# Kuorma tyhjennetaan aina (myos jos world puuttuu) jotta dump paattyy varmasti;
# world==null on vain degeneroitunut testitapaus.
func _sell_remaining_cargo(b: Bot) -> void:
	if b.cargo_total <= 0:
		return
	if world != null:
		world.deposit_cargo(b.cargo)
	b.clear_cargo()


# Sijoita enintaan budget px kuormasta oikeaan kohteeseen dump_target-lipun mukaan:
#   - is_base_dropoff=true tai ei dump_targetia -> basen intake-sarakkeet (_drop_cargo_above_base),
#   - muu dump-vyohyke -> koko klikattava rect (_deposit_cargo_to_zone).
# Palauttaa TOSIASIASSA sijoitetut px (< budget = kohde tayynna, kutsuja myy loput).
func _place_cargo_budget(b: Bot, budget: int) -> int:
	var dt := b.dump_target
	if not dt.is_empty() and String(dt.get("kind", "")) == "dump" and not bool(dt.get("is_base_dropoff", false)):
		return _deposit_cargo_to_zone(b, budget)
	# base-dropoff TAI ei dump_targetia (esim. suora _st_dump-testikutsu) -> basen intake.
	return _drop_cargo_above_base(b, budget)


# Litista kuormasta ENINTAAN max_px pikselia deterministiseen jarjestykseen (materiaali-avaimet
# NOUSEVASTI). Palauttaa Array[int] (mat per px). EI muuta kuormaa — kutsuja vahentaa cargon
# tosiasiassa sijoitettujen px:ien mukaan (remove_cargo). Deterministinen jarjestys takaa etta
# osittaisessa purussa myyty jaannos on aina sama.
func _flatten_cargo(b: Bot, max_px: int) -> Array:
	var out: Array = []
	if max_px <= 0:
		return out
	var mats: Array = b.cargo.keys()
	mats.sort()  # nousevat mat-ID:t -> deterministinen
	for mat in mats:
		var n := int(b.cargo[mat])
		for _i in n:
			if out.size() >= max_px:
				return out
			out.append(int(mat))
	return out


# Pura ENINTAAN budget px kuormasta dump-vyohykkeelle irtopikseleina (kone/pickup poimii).
# Palauttaa montako px TOSIASIASSA kirjoitettiin ja vahentaa kuorman sen mukaan. Alueen
# tayttyminen nakyy kutsujalle paluuarvona (placed < budget) -> _st_dump myy loput.
# dump_target["rect"] = kohdealue.
func _deposit_cargo_to_zone(b: Bot, budget: int) -> int:
	var rect: Rect2i = b.dump_target.get("rect", Rect2i())
	if rect.size.x <= 0 or rect.size.y <= 0:
		return 0  # ei kelvollista aluetta -> 0 sijoitettu (kutsuja myy loput)
	# Litista enintaan budget px deterministiseen jarjestykseen (mat-avaimet nousevasti).
	var to_place := _flatten_cargo(b, budget)
	if to_place.is_empty():
		return 0
	var pi := 0
	var y1 := mini(rect.position.y + rect.size.y, SIM_H)
	var x1 := mini(rect.position.x + rect.size.x, SIM_W)
	var y := maxi(rect.position.y, 0)
	var x0 := maxi(rect.position.x, 0)
	# Laajenna CA-rajaus dump-alueelle (headless cpu_ca) — sama mekanismi kuin
	# _drop_cargo_above_basessa, jotta pelaajan ilmaan rakentama custom-dump toimii.
	if world.has_method("_ca_expand_bounds"):
		world._ca_expand_bounds(Rect2i(x0, y, x1 - x0, y1 - y))
	# Kirjoita alueen tyhjiin, ei-rakennuspikseleihin.
	while y < y1 and pi < to_place.size():
		var base_i := y * SIM_W
		var x := x0
		while x < x1 and pi < to_place.size():
			var idx := base_i + x
			if not world.building_pixels.has(idx) and world.grid[idx] == MAT_EMPTY:
				world.mvp_write_pixel(x, y, to_place[pi])
				pi += 1
			x += 1
		y += 1
	# Vahenna kuormasta TOSIASIASSA sijoitetut px (to_place[0..pi]).
	for k in pi:
		b.remove_cargo(to_place[k], 1)
	return pi


# Pura ENINTAAN budget px haulerin kuormaa FYYSISINA pikseleina basen intake-aukon ylapuolelle.
# Pikselit kirjoitetaan intake-sarakkeisiin (drop_columns) alhaalta (drop_start_y) ylospain, vain
# tyhjiin ei-rakennuspikseleihin. CA pudottaa ne intakeen -> update_exit syo rahaksi. Palauttaa
# montako px TOSIASIASSA kirjoitettiin ja vahentaa kuorman sen mukaan; sarakkeiden tayttyminen
# nakyy kutsujalle paluuarvona (placed < budget) -> _st_dump myy loput. CA-rajaus laajennetaan
# pudotusalueelle (headless cpu_ca); GPU-pelissa _ca_expand_bounds on no-op.
func _drop_cargo_above_base(b: Bot, budget: int) -> int:
	var base: MoneyExit = world.base
	if base == null or not is_instance_valid(base):
		return 0  # ei basea -> 0 sijoitettu (kutsuja myy/tyhjentaa loput)
	var to_place := _flatten_cargo(b, budget)
	if to_place.is_empty():
		return 0
	var cols: Array = base.drop_columns()
	if cols.is_empty():
		return 0  # ei aukkoa (ei pitaisi) -> 0 sijoitettu, kutsuja myy loput
	var start_y: int = base.drop_start_y()
	# Laajenna CA-rajaus pudotuspatsaan korkeudelle + intake-riville asti (headless).
	var need_rows := int(ceil(float(to_place.size()) / float(cols.size()))) + 2
	var min_x := int(cols[0])
	var max_x := int(cols[0])
	for cx in cols:
		min_x = mini(min_x, int(cx))
		max_x = maxi(max_x, int(cx))
	if world.has_method("_ca_expand_bounds"):
		var top := start_y - need_rows
		world._ca_expand_bounds(Rect2i(min_x, top, max_x - min_x + 1, (start_y + 2) - top))
	# Tayta alhaalta (start_y) ylospain: matala patsas joka valuu intakeen.
	var pi := 0
	var y := start_y
	while y >= 0 and pi < to_place.size():
		for cx in cols:
			if pi >= to_place.size():
				break
			var xi := int(cx)
			if xi < 0 or xi >= SIM_W:
				continue
			var idx := y * SIM_W + xi
			if world.building_pixels.has(idx):
				continue
			if world.grid[idx] != MAT_EMPTY:
				continue
			world.mvp_write_pixel(xi, y, int(to_place[pi]))
			pi += 1
		y -= 1
	# Vahenna kuormasta TOSIASIASSA sijoitetut px (to_place[0..pi]).
	for k in pi:
		b.remove_cargo(to_place[k], 1)
	return pi


# ============================================================
#  Liike (waypoint-seuranta, ei fysiikkaa)
# ============================================================

# Palauttaa true kun reitti on kuljettu loppuun.
func _follow_path(b: Bot, delta: float) -> bool:
	if b.path_idx >= b.path.size():
		return true
	var budget := b.move_speed() * delta
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
	b.work_accum += b.mine_rate() * delta
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
		_designations_consumed += 1   # P0-3: eka kulutettu designaatio avaa "merkkaa lisaa" -heratteen
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


# (B1) Lisaa dig_site. Yli katon: poista ENSIN vahvistetusti tyhjentyneet kasat, ja vasta
# jos lista on yha yli, pudota vanhin (aarimmainen fallback). Nain FIFO ei koskaan pudota
# kasaa jossa on viela materiaalia.
func _add_dig_site(c: Vector2i) -> void:
	if dig_sites.has(c):
		return
	dig_sites.append(c)
	if dig_sites.size() <= MAX_DIG_SITES:
		return
	_prune_empty_dig_sites()
	while dig_sites.size() > MAX_DIG_SITES:
		dig_sites.pop_front()


func _remove_dig_site(c: Vector2i) -> void:
	var i := dig_sites.find(c)
	if i >= 0:
		dig_sites.remove_at(i)


# Poistaa dig_sitesista kaikki kasat joissa ei ole enaa poimittavaa (kevyt early-exit-skannaus).
func _prune_empty_dig_sites() -> void:
	var kept: Array[Vector2i] = []
	for c in dig_sites:
		if _dig_site_has_material(c):
			kept.append(c)
	dig_sites = kept


# Kevyt tarkistus: onko dig_site-sarakkeessa yhtaan poimittavaa (PILE_MIN_PX asti, early-exit).
func _dig_site_has_material(c: Vector2i) -> bool:
	var x0 := c.x * DCELL - PILE_SCAN_HALF_W
	var x1 := c.x * DCELL + DCELL + PILE_SCAN_HALF_W
	var top := c.y * DCELL
	var maxy := mini(top + PILE_SCAN_DEPTH, SIM_H)
	var found := 0
	var y := top
	while y < maxy:
		var base_i := y * SIM_W
		for x in range(x0, x1):
			if x < 0 or x >= SIM_W:
				continue
			var mat: int = world.grid[base_i + x]
			if _granular_lut[mat] == 1:
				found += 1
				if found >= PILE_MIN_PX:
					return true
		y += 1
	return false


# Etsi kasa mielivaltaiselta suorakulmiolta (pickup-vyohyke). filter_mask rajaa poimittavat
# materiaalit (0 = kaikki granulaarit). Palauttaa { "count": int, "pos": Vector2 (massakeskipiste) }.
func _find_pile_in_rect(rect: Rect2i, filter_mask: int) -> Dictionary:
	var y0 := maxi(rect.position.y, 0)
	var y1 := mini(rect.position.y + rect.size.y, SIM_H)
	var x0 := maxi(rect.position.x, 0)
	var x1 := mini(rect.position.x + rect.size.x, SIM_W)
	var count := 0
	var sx := 0.0
	var sy := 0.0
	var y := y0
	while y < y1:
		var base_i := y * SIM_W
		for x in range(x0, x1):
			var idx := base_i + x
			if world.building_pixels.has(idx):
				continue
			var mat: int = world.grid[idx]
			if _granular_lut[mat] != 1:
				continue
			if filter_mask != 0 and (filter_mask & (1 << mat)) == 0:
				continue
			count += 1
			sx += float(x)
			sy += float(y)
		y += 1
	if count < PILE_MIN_PX:
		return {"count": count, "pos": Vector2.ZERO}
	return {"count": count, "pos": Vector2(sx / float(count), sy / float(count))}


# ============================================================
#  Imurointi (hauler WORK)
# ============================================================

const VACUUM_RATE := 30.0   # px/s imunopeus (kuorma virtaa tayteen ~1.3 s @ CARRY_CAP=40)
const FX_MAX := 48          # yhtaaikaisten imuvirtapartikkelien katto per botti


func _work_vacuum(b: Bot, delta: float) -> void:
	# Kerros 3: ruuhka hidastaa imua (saturoituva throughput). _crowd_factor 1.0 -> CONGEST_FLOOR.
	# Minerin louhintaan EI sovelleta tata (MINE_MAX_TIME-turvakatto), vain haulerin imuun ja dumppiin.
	b.work_accum += VACUUM_RATE * _crowd_factor(b) * delta
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
	if b.cargo_total >= b.carry_cap():
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
	# Turvavahti (VAIN peralauta, sama periaate kuin MOVE_MAX_TIME): oikea jumi poistuu jo
	# valittomasti picked==0-haarasta ylla, joten tama katto suojaa vain logiikkavirheelta.
	# Mitoitus: HITAAN mutta ETENEVAN imun pitaa mahtua alle — ruuhkalattia 30*0.25=7.5 px/s
	# -> Mk3 180 px = 24 s < 30 s. (Vanha 6.0 s katkaisi Mk2/Mk3-imun kesken ruuhkassa ->
	# turhia osakuormareissuja juuri kun ruuhka oli pahin.)
	if b.state_timer > VACUUM_MAX_TIME:
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
func _vacuum(b: Bot, budget: int = -1) -> int:
	# budget < 0 -> koko kuorman verran (botin tierin carry_cap). Sailyttaa suoran _vacuum(b)
	# -kutsun vanhan "tayta kerralla" -kayttaytymisen (testit).
	var cap := b.carry_cap()
	if budget < 0:
		budget = cap
	var cx := int(b.pickup_pos.x)
	var cy := int(b.pickup_pos.y)
	var r := VACUUM_RADIUS
	var r2 := r * r
	var picked := 0
	var room := mini(cap - b.cargo_total, budget)
	if room <= 0:
		return picked
	for oy in range(-r, r + 1):
		var y := cy + oy
		if y < 0 or y >= SIM_H:
			continue
		var base_i := y * SIM_W
		for ox in range(-r, r + 1):
			if b.cargo_total >= cap or picked >= room:
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
	# Valitse dump: logistics valitsee filtterin (dump-vyohykkeet, sis. base-dropoff) ja
	# etaisyyden mukaan (GDD §4.2). Base EI ole enaa automaattinen fallback-kandidaatti —
	# jos mikaan dump-vyohyke ei hyvaksy kuormaa, hauler pitaa kuorman ja jaa IDLEen
	# basen luo, yrittaen uudelleen DUMP_RETRY_DELAY-backoffilla (ks. _assign_hauler/_st_idle).
	var chosen: Dictionary = {}
	if logistics != null:
		chosen = logistics.choose_dump(b.cargo, b.pos)
	if chosen.is_empty():
		b.dump_retry_cooldown = DUMP_RETRY_DELAY
		_set_state(b, Bot.BotState.IDLE)
		return
	b.dump_target = chosen
	# Kerros 3: deterministinen per-botti lentohajautus (±8 px) ettei koko lauma jonota
	# TASMALLEEN samaan pisteeseen dumpin edessa. VAIN lentokohteeseen — pikselit kirjoitetaan
	# silti kohteen omaan rectiin / intake-sarakkeisiin (dump_target["rect"] sailyy ennallaan).
	var scatter := Vector2(float((b.id * 7) % 5 - 2) * 4.0, 0.0)
	var target: Vector2 = chosen.get("pos", b.pos) + scatter
	var path: PackedVector2Array = world.nav.find_path_px(b.pos, target)
	if path.is_empty():
		# Kohde voi olla avoimella alueella -> lenna suoraan (drone lapaisee kaiken)
		path = PackedVector2Array([target])
	b.path = path
	b.path_idx = 0
	_set_state(b, Bot.BotState.CARRY_MOVE)


# Etsi kasa dig_site-solun (dx,dy) sarakkeesta alaspain (kasat valuvat alas).
# Palauttaa { "count": int, "pos": Vector2 }.
func _find_pile(dx: int, dy: int) -> Dictionary:
	var cx0 := dx * DCELL                          # solun OMA sarake (louhittu kuoppa)
	var cx1 := dx * DCELL + DCELL
	var x0 := cx0 - PILE_SCAN_HALF_W               # levennys molemmin puolin: nappaa sivuille
	var x1 := cx1 + PILE_SCAN_HALF_W               # valunut irtomateriaali granulaarilaskuriin
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
			elif x >= cx0 and x < cx1 and (world.building_pixels.has(idx) or _floor_lut[mat] == 1):
				# Lattia (skannauksen pysaytin) tunnistetaan VAIN solun omasta sarakkeesta.
				# Viereiset louhimattomat kiviseinat (4 px marginaali molemmin puolin) EIVAT ole
				# "pohja" — muuten kapea yhden solun kuoppa katkeaisi heti ensimmaiseen gravel-riviin,
				# kasa aliarvioituisi alle PILE_MIN_PX:n ja hauler hylkaisi dig_siten (bugi: ekan
				# blokin saalis jai keraamatta). Leveassa kaivannossa kasan vieressa on tyhjaa, joten
				# tama ei muuta kayttaytymista siella.
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
		var frac := clampf(float(b.cargo_total) / float(b.carry_cap()), 0.0, 1.0)
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
	# Piirto jaettu erillisiin passeihin z-order-artefaktin valttamiseksi: jos jokainen botti
	# piirtaisi laserin+reunuksen+rungon perakkain omassa silmukka-iteraatiossaan, seuraavan
	# botin tumma reunus (12x12) voi piirtya jo valmiin botin varillisen rungon (10x10) paalle
	# kun botit ovat lahella toisiaan (esim. jonottavat tyokohteella/pudotuspisteella) -> nakyva
	# tumma lovi bahtaa rungon reunaan. Korjaus: kaikki reunukset ENSIN, sitten kaikki rungot,
	# jotta jokainen runko paatyy varmasti kaikkien reunusten paalle riippumatta botti-indeksista.
	# Keskipisteet lasketaan kerran ja valimuistiin (vältetään sin()-toisto per passi).
	var centers: Array[Vector2] = []
	centers.resize(bots.size())
	for i in bots.size():
		var b := bots[i]
		# Huojunta vain y-suunnassa (sin-aalto per botti-indeksi). Pohjana kaytetaan silotettua
		# render_pos:ia (pehmeampi kuin raaka pos); jos visualisointia ei ole viela alustettu
		# (ensimmainen frame), fallbackaa raakaan pos:iin ettei botti nayta hyppaavan origosta.
		var base_pos: Vector2 = b.render_pos if b.visuals_init else b.pos
		var offset_y := sin(t * 2.5 + float(i) * 1.7) * 2.0
		centers[i] = Vector2(base_pos.x, base_pos.y + offset_y)

	# Passi 1: louhintalaserit (piirretaan ensin, jaavat rungon/reunuksen alle)
	for i in bots.size():
		var b := bots[i]
		if b.role == Bot.Role.MINER and b.state == Bot.BotState.WORK \
				and not b.mine_targets.is_empty() and b.mine_cursor < b.mine_targets.size():
			var cx := centers[i].x
			var cy := centers[i].y
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

	# Passi 2: kaikkien bottien tummat reunukset (12x12, keskitetty)
	for i in bots.size():
		var cx := centers[i].x
		var cy := centers[i].y
		canvas.draw_rect(Rect2(cx - 6.0, cy - 6.0, 12.0, 12.0), Color(0.05, 0.05, 0.08, 0.92))

	# Passi 3: kaikkien bottien varilliset rungot (10x10, keskitetty) — piirtyvat AINA
	# kaikkien reunusten paalle, koska koko passi 2 on jo suoritettu loppuun.
	for i in bots.size():
		var b := bots[i]
		var col: Color
		if b.role == Bot.Role.MINER:
			col = Color(0.88, 0.66, 0.25)   # amber/kulta
		else:
			col = Color(0.35, 0.62, 0.95)   # kirkas sininen
		var cx := centers[i].x
		var cy := centers[i].y
		canvas.draw_rect(Rect2(cx - 5.0, cy - 5.0, 10.0, 10.0), col)

	# Passi 4: haulerien kannettu kuorma — nakyva fysikaalinen klontti (ei enaa abstrakti palkki).
	# Klontti roikkuu load_pos:n ymparilla (jousifysiikka paivittaa sen update_visualsissa),
	# joten se laahaa liikkeessa ja heiluu kaannoksissa -> tuntuu oikealta painavalta kuormalta.
	# Piirretaan viimeisena kaikkien runkojen paalle, kuten alkuperaisessakin jarjestyksessa.
	for i in bots.size():
		var b := bots[i]
		if b.role == Bot.Role.HAULER and b.cargo_total > 0:
			# 1) Imuvirtapartikkelit ensin (piirtyvat klontin taakse)
			for fx in b.intake_fx:
				var tt := 1.0 - pow(1.0 - clampf(float(fx["t"]), 0.0, 1.0), 2.0)
				var fp: Vector2 = (fx["from"] as Vector2).lerp(b.load_pos, tt)
				var fcol := _mat_color(int(fx["mat"]))
				fcol.a = 1.0 - tt * 0.3   # himmenee lahestyessaan klonttia
				canvas.draw_rect(Rect2(floor(fp.x), floor(fp.y), 1.0, 1.0), fcol)
			# 2) Kuormaklontti: 1x1 px per kannettu yksikko (sama koko kuin sim-pikseli), kultaisen kulman spiraalilla
			# sironnettuna sateelle (tasainen tayttö) + smear liikesuuntaan (laahaa perassa).
			# Taysi-signaali: pieni "hengitys"-pulssi klontin sateeseen kun kuorma on tayssa.
			var cap := b.carry_cap()
			var full_pulse := 0.0
			if b.cargo_total >= cap:
				full_pulse = sin(t * 6.0) * 0.15 + 0.15   # ~0.0 .. 0.3
			var vel := b.load_vel.limit_length(5.0)
			var k := 0
			for mat in b.cargo:
				if k >= cap:
					break
				var c := _mat_color(int(mat))
				for _n in int(b.cargo[mat]):
					if k >= cap:
						break
					var ang := float(k) * 2.399963      # kultainen kulma -> tasainen tayttö
					# Tiiviimpi pakkaus: pienempi sädekerroin -> pikselit lomittuvat kiinteäksi
					# möykyksi (imuroitu pikseliryhmä näyttää tiheältä, ei hajanaiselta pilveltä).
					var rad := (0.4 + sqrt(float(k)) * 0.40) * (1.0 + full_pulse)
					var jit := sin(t * 9.0 + float(k) * 1.3) * 0.25   # granulaarinen vare (pienennetty)
					var p := b.load_pos + Vector2(cos(ang), sin(ang)) * rad
					p += vel * (float(k) / float(cap)) * 0.4   # kevyempi laahaus -> möykky pysyy koossa
					p += Vector2(jit, 0.0)
					canvas.draw_rect(Rect2(floor(p.x), floor(p.y), 1.0, 1.0), c)
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
