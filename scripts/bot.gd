# Yksittaisen louhintarobotin data + tilakone-apurit.
# Botti on CPU-overlay-agentti (kuten player.gd) — EI CA-pikseli.
# Lentava drone: ei painovoimaa, ei tormaystarkistusta. Liikkuu nav-waypointteja pitkin.
# Varsinainen tilakonelogiikka ajetaan BotManagerissa (silla on world-viittaus).
class_name Bot
extends RefCounted

# Rooli — yksi rooli / botti (ei molempia)
enum Role { MINER, HAULER }

# Tilakone: IDLE -> MOVE -> WORK -> CARRY_MOVE -> DUMP
enum BotState { IDLE, MOVE, WORK, CARRY_MOVE, DUMP }

# Mk1-arvot (upgrade-tierit lisataan myohemmin)
const MOVE_SPEED := 40.0   # px/s
const MINE_RATE := 80.0    # px/s (16x16-solu = 256 px -> tayden kivisolun louhinta ~3.2 s)
const CARRY_CAP := 40      # px

# --- Kontraktin mukainen julkinen tila ---
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


func add_cargo(mat: int, n: int) -> void:
	cargo[mat] = int(cargo.get(mat, 0)) + n
	cargo_total += n


func clear_cargo() -> void:
	cargo.clear()
	cargo_total = 0
