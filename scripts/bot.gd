# Yksittaisen louhintarobotin data + tilakone-apurit.
# Botti on CPU-overlay-agentti (kuten player.gd) — EI CA-pikseli.
# Lentava drone: ei painovoimaa, ei tormaystarkistusta. Liikkuu nav-waypointteja pitkin.
# Varsinainen tilakonelogiikka ajetaan BotManagerissa (silla on world-viittaus).
class_name Bot
extends RefCounted

# Rooli — yksi rooli / botti (ei molempia)
enum Role { MINER, HAULER }

# Tilakone: IDLE -> MOVE -> WORK -> CARRY_MOVE -> DUMP
# M3: SEEK_CHARGE=5, CHARGING=6 LISATTY LOPPUUN. Ala muuta 0-4 numerointia
# (skenaariot/UI/testit viittaavat niihin numeroin).
enum BotState { IDLE, MOVE, WORK, CARRY_MOVE, DUMP, SEEK_CHARGE, CHARGING }

# --- Upgrade-tierit (Mk1/Mk2/Mk3), taulukkoindeksi = tier - 1 ---
# GDD §2.5 lahtoarvot olivat mine 25/50/90, mutta koodin nykybalanssi kayttaa jo MINE_RATE=80
# (tayden kivisolun louhinta ~3.2 s tuntui oikealta). Sailytamme Mk1 = nykyinen 80 jottei
# ennestaan viritetty balanssi hyppaa, ja skaalaamme Mk2/Mk3 tehtavan ohjeen mukaan 140/220
# (~1.75x / 2.75x — sama suhteellinen kasvu-idea kuin GDD:n 25->50->90). Carry ja move_speed
# tulevat suoraan GDD:sta (40/90/180 ja 40/70/110); Mk1 = nykyinen balanssi.
const TIER_CARRY: Array[int] = [40, 90, 180]
const TIER_MINE_RATE: Array[float] = [80.0, 140.0, 220.0]
const TIER_MOVE_SPEED: Array[float] = [40.0, 70.0, 110.0]
const MAX_TIER := 3        # Mk3 on korkein

# Mk1-perusarvot vakioina — sailytetaan yhteensopivuutena (Bot.CARRY_CAP-viittaukset + testit).
# Nama vastaavat TIER_*[0]:aa; kayta bot-instanssin carry_cap()/mine_rate()/move_speed()
# -metodeja aina kun tier-riippuvuus on tarpeen.
const MOVE_SPEED := 40.0   # px/s (Mk1)
const MINE_RATE := 80.0    # px/s (Mk1; 16x16-solu = 256 px -> tayden kivisolun louhinta ~3.2 s)
const CARRY_CAP := 40      # px  (Mk1)

# --- Akku (M3) ---
# Akkuyksikko = "tyosekunti". Hupenee VAIN WORK/DUMP-tilassa (BotManager.BATTERY_DRAIN).
# Botti hakeutuu lataukseen kun akku alittaa BotManager.BATTERY_SEEK-kynnyksen.
const BATTERY_MAX := 90.0
var battery: float = BATTERY_MAX
var charger_slot: int = -1       # varattu latausslotin globaali indeksi; -1 = ei varausta

# --- Kontraktin mukainen julkinen tila ---
var id: int = -1                         # pysyva tunniste (BotManager antaa add_botissa)
var tier: int = 1                        # 1=Mk1, 2=Mk2, 3=Mk3 (upgrade_bot nostaa)
var role: int = Role.MINER
var state: int = BotState.IDLE
var pos: Vector2 = Vector2.ZERO          # sim-pikselikoordinaatit
var path: PackedVector2Array = PackedVector2Array()
var cargo: Dictionary = {}               # mat_id (int) -> px-maara (int)
var cargo_total: int = 0

# --- Sisainen tilakonedata (BotManager kayttaa) ---
var path_idx: int = 0                     # nykyinen waypoint-indeksi
var target_cell: Vector2i = Vector2i(-1, -1)  # miner: varattu designaatiosolu; hauler: kohde-dig_site
var pickup_pos: Vector2 = Vector2.ZERO    # hauler: kohdekasan px-sijainti
var work_accum: float = 0.0               # murto-px kerain louhinnalle
var state_timer: float = 0.0              # aika nykyisessa tilassa (watchdog)
var stall_timer: float = 0.0              # louhinnan pysahtymisvahti
var dump_retry_cooldown: float = 0.0      # s; >0 = odota ennen uutta dump-yritysta (ei dump-vyohyketta hyvaksynyt)
var last_solids: int = 0x7fffffff         # edellinen kiinteiden lkm (progressin seuranta)
# Louhinnan tyolista: WORK-tilaan siirryttaessa napataan solun louhittavat pikselit
# tahan (jarjestetty alhaalta ylos). mine_cursor etenee kun tyota kertyy MINE_RATEn
# mukaan -> louhinta valmistuu ajassa targets.size()/MINE_RATE, ei stall-vahdin varassa.
var mine_targets: Array = []              # Array[Vector2i] — solun louhittavat px snapshot
var mine_cursor: int = 0                  # montako mine_targets-pikselia jo kasitelty
var hover_offset: Vector2 = Vector2.ZERO  # IDLE-leijunnan hajautus per botti

# --- Telemetria (testaus/diagnostiikka) ---
var spawn_pos: Vector2 = Vector2.ZERO     # botin luontipiste (asetetaan add_botissa)
var max_dist_from_spawn: float = 0.0      # suurin etaisyys spawnista koko elinajalta

# --- Visuaalinen kuormafysiikka (paivitetaan update_visualsissa per frame) ---
var render_pos: Vector2 = Vector2.ZERO   # silotettu bot.pos (logiikkatikki nykii ~15 Hz)
var load_pos: Vector2 = Vector2.ZERO     # kannetun kuorman painopiste
var load_vel: Vector2 = Vector2.ZERO
var intake_fx: Array = []                # imuvirtapartikkelit: {"from":Vector2,"mat":int,"t":float}
var visuals_init: bool = false           # false -> ensimmaisella framella snapataan pos:iin

# --- Kädet + antenni (proseduraalinen sekundaarianimaatio, update_visuals päivittää) ---
var hand_l_pos: Vector2 = Vector2.ZERO
var hand_l_vel: Vector2 = Vector2.ZERO
var hand_r_pos: Vector2 = Vector2.ZERO
var hand_r_vel: Vector2 = Vector2.ZERO
var ant_angle: float = 0.0      # antennin kulma (rad, 0 = suoraan ylos); + = taipuu oikealle
var ant_vel: float = 0.0        # kulmanopeus (jousiwobble)
var anim_phase: float = 0.0     # per-botti satunnaisvaihe idle-desynkkaukseen (asetetaan add_botissa)

# Hauler: valittu dumppikohde nykyiselle kuormalle (Logistics.choose_dump palauttaa taman).
# { "kind": "dump", "pos": Vector2, "rect": Rect2i, "id": int, "accepted": int,
#   "is_base_dropoff": bool }. Tyhja {} = mikaan dump-vyohyke (myos base-dropoff) ei
# hyvaksynyt kuormaa -> hauler jaa IDLEen, kuorma sailyy, yrittaa uudelleen (dump_retry_cooldown).
var dump_target: Dictionary = {}


# --- Tier-riippuvaiset arvot (Mk1/Mk2/Mk3) ---

# Kantokyky (px) nykyisella tierilla.
func carry_cap() -> int:
	return TIER_CARRY[tier - 1]


# Louhintanopeus (px/s) nykyisella tierilla.
func mine_rate() -> float:
	return TIER_MINE_RATE[tier - 1]


# Liikenopeus (px/s) nykyisella tierilla.
func move_speed() -> float:
	return TIER_MOVE_SPEED[tier - 1]


func add_cargo(mat: int, n: int) -> void:
	cargo[mat] = int(cargo.get(mat, 0)) + n
	cargo_total += n


# Poista n px materiaalia kuormasta (ajallinen dumppi purkaa kuorman pikseli kerrallaan).
# Ei mene negatiiviseksi; tyhjentynyt materiaaliavain poistetaan dictista (deterministinen
# tyhjeneminen). cargo_total pidetaan synkassa avaimien summan kanssa.
func remove_cargo(mat: int, n: int = 1) -> void:
	var have := int(cargo.get(mat, 0))
	var take := mini(n, have)
	if take <= 0:
		return
	if have - take > 0:
		cargo[mat] = have - take
	else:
		cargo.erase(mat)
	cargo_total -= take


func clear_cargo() -> void:
	cargo.clear()
	cargo_total = 0
