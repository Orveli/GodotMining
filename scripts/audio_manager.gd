# AudioManager — demon aaniohjaus PUHTAANA OBSERVERINA (autoload).
#
# Ei muokkaa pixel_world.gd / ui.gd / money_exit.gd / bot_manager.gd -tiedostoja lainkaan.
# Kytkeytyy peliin vain lukemalla julkista tilaa + kuuntelemalla signaaleja:
#   - Kassa-aani:    seuraa world.money -deltaa per frame (throttle 4/s, pitch +-10 %).
#   - Louhinta-aani: pollaa world.bot_manager.bots -tilat; MINER + WORK => toistuva chunk
#                    (samanaikaisia "stackeja" enintaan 3, aani skaalautuu louhijamaaralla).
#   - Milestone:     world.milestone / world.demo_complete -signaalit => fanfaari.
#   - UI-klik:       kaikki scene-puun BaseButtonit (pressed) => naks; uudet napit
#                    napataan node_added-signaalilla.
#   - Ambient:       matala saumaton humina heti alusta, hiljaisena pohjana.
#
# Defensiivinen: toimii vaikka world puuttuisi (etsii joka frame kunnes loytyy) ja
# vaikka audiolaitetta ei olisi (headless dummy-driver ei kaadu). Ei oleta reaaliaikaa —
# kaikki throttlet perustuvat kumuloituun deltaan, joten skenaario-run_frames ei tuota
# purskeita tai kaatumisia.
extends Node

# --- Master-volume (debug-saato myohemmin; ohjaa vain SFX-vaylaa) ---
@export var master_volume_db: float = 0.0:
	set(value):
		master_volume_db = value
		_apply_master_volume()

# --- Viritysvakiot ---
const CASH_MAX_PER_S := 4.0          # kassa-kilahduksia enintaan sekunnissa
const CASH_PITCH_JITTER := 0.10      # +-10 % satunnainen pitch
const MINE_INTERVAL := 0.20          # s per murskausisku kun louhinta aktiivista
const MINE_MAX_STACKS := 3           # samanaikaisia chunk-aania enintaan
const MINE_PITCH_JITTER := 0.15
const UI_CLICK_PITCH_JITTER := 0.06
const BOOT_SCAN_FRAMES := 8          # _process-frameja ennen UI-nappien kertaskannausta

# Aanenvoimakkuudet (dB) per aani. Ambient tarkoituksella hiljaisin pohja.
const AMBIENT_DB := -18.0
const CASH_DB := -6.0
const MINE_DB := -9.0
const MILESTONE_DB := -3.0
const UI_CLICK_DB := -8.0

const SFX_BUS := "MiningSFX"         # oma vayla -> master_volume_db ei koske pelin muihin aaniin

# Aanitiedostot
const PATH_MINE := "res://assets/audio/mine_chunk.wav"
const PATH_CASH := "res://assets/audio/cash.wav"
const PATH_MILESTONE := "res://assets/audio/milestone.wav"
const PATH_CLICK := "res://assets/audio/ui_click.wav"
const PATH_AMBIENT := "res://assets/audio/ambient_hum.wav"

# --- Aanivarat + soittimet ---
var _stream_mine: AudioStream = null
var _stream_cash: AudioStream = null
var _stream_milestone: AudioStream = null
var _stream_click: AudioStream = null
var _stream_ambient: AudioStream = null

var _ambient_player: AudioStreamPlayer = null
var _cash_player: AudioStreamPlayer = null
var _milestone_player: AudioStreamPlayer = null
var _mine_players: Array[AudioStreamPlayer] = []   # pooli (round-robin) -> max 3 stackia
var _mine_rr: int = 0
var _click_players: Array[AudioStreamPlayer] = []  # pooli nopeille perakkaisille klikeille
var _click_rr: int = 0

# --- SFX-vayla ---
var _bus_idx: int = -1
var _bus_ready: bool = false

# --- Observer-tila ---
var _world: Node = null
var _world_ready: bool = false
var _last_money: int = 0
var _cash_cooldown: float = 0.0
var _mine_accum: float = 0.0

# --- UI-nappien kytkenta ---
var _ui_scan_done: bool = false
var _boot_frames: int = 0

# Headlessissa ei ole audiolaitetta -> tosiasiallinen toisto ohitetaan (defensiivinen).
# Kaikki muu logiikka (lataus, vayla, world-haku, signaalit, pollaus) ajetaan silti,
# joten savutesti kattaa observer-polun ilman audiolaitteen "resource still in use" -jattea.
var _audio_enabled: bool = true


func _ready() -> void:
	_audio_enabled = DisplayServer.get_name() != "headless"
	# Autoload boottaa ennen paascenea -> lataa aanet ja kaynnista ambient heti.
	_load_streams()
	_setup_bus()
	_create_players()
	_apply_master_volume()
	_start_ambient()

	# Uudet napit (esim. UI:n dynaamisesti luomat) napataan heti niiden synnyttya.
	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)


# Lataa WAV-virrat defensiivisesti (null jos importtia ei viela ole).
func _load_streams() -> void:
	_stream_mine = _safe_load(PATH_MINE)
	_stream_cash = _safe_load(PATH_CASH)
	_stream_milestone = _safe_load(PATH_MILESTONE)
	_stream_click = _safe_load(PATH_CLICK)
	_stream_ambient = _safe_load(PATH_AMBIENT)
	# Ambient loopataan saumattomasti (WAV generoitu kokonaissyklein).
	_enable_loop(_stream_ambient)


func _safe_load(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	var res: Resource = load(path)
	if res is AudioStream:
		return res
	return null


# Aseta WAV-virta loopittamaan (saumaton pohjahumina).
func _enable_loop(stream: AudioStream) -> void:
	if stream is AudioStreamWAV:
		var wav: AudioStreamWAV = stream
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		var bytes_per_frame := 2                       # 16-bit mono
		if wav.format == AudioStreamWAV.FORMAT_8_BITS:
			bytes_per_frame = 1
		wav.loop_end = int(wav.data.size() / bytes_per_frame)


# Luo oma SFX-vayla, jotta master_volume_db saataa vain naita aania.
func _setup_bus() -> void:
	_bus_idx = AudioServer.get_bus_index(SFX_BUS)
	if _bus_idx == -1:
		AudioServer.add_bus()
		_bus_idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(_bus_idx, SFX_BUS)
		AudioServer.set_bus_send(_bus_idx, "Master")
	_bus_ready = _bus_idx >= 0


func _apply_master_volume() -> void:
	if _bus_ready and _bus_idx >= 0 and _bus_idx < AudioServer.bus_count:
		AudioServer.set_bus_volume_db(_bus_idx, master_volume_db)


# --- Soitinten luonti ------------------------------------------------------

func _make_player(stream: AudioStream, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	p.bus = SFX_BUS if _bus_ready else "Master"
	add_child(p)
	return p


func _create_players() -> void:
	_cash_player = _make_player(_stream_cash, CASH_DB)
	_milestone_player = _make_player(_stream_milestone, MILESTONE_DB)
	_ambient_player = _make_player(_stream_ambient, AMBIENT_DB)
	# Louhinta-pooli: MINE_MAX_STACKS paallekkaista aanta.
	for i in range(MINE_MAX_STACKS):
		_mine_players.append(_make_player(_stream_mine, MINE_DB))
	# UI-klik-pooli: sallii nopeat peraakkaiset klikit ilman leikkautumista.
	for i in range(3):
		_click_players.append(_make_player(_stream_click, UI_CLICK_DB))


func _start_ambient() -> void:
	if not _audio_enabled:
		return
	if _ambient_player != null and _ambient_player.stream != null:
		_ambient_player.play()


# Siisti sammutus: pysayta soittimet + vapauta virtaviitteet. Muuten looppaava
# ambient jattaa AudioStreamPlaybackin ja WAV-resurssin roikkumaan exitissa
# (ObjectDB-leak / "resource still in use" -varoitus headlessissa).
func _exit_tree() -> void:
	var players: Array[AudioStreamPlayer] = [_ambient_player, _cash_player, _milestone_player]
	players.append_array(_mine_players)
	players.append_array(_click_players)
	for p in players:
		if p != null and is_instance_valid(p):
			if p.playing:
				p.stop()
			p.stream = null
	_stream_mine = null
	_stream_cash = null
	_stream_milestone = null
	_stream_click = null
	_stream_ambient = null


# --- Per-frame observointi -------------------------------------------------

func _process(delta: float) -> void:
	# 1) UI-nappien kertaskannaus boot-viiveen jalkeen. Alussa olemassa olevat napit
	#    kaydaan lapi kerran; myohemmin luodut napit hoituvat node_addedilla.
	if not _ui_scan_done:
		_boot_frames += 1
		if _boot_frames >= BOOT_SCAN_FRAMES:
			var root := get_tree().root
			if root != null:
				_scan_and_connect_buttons(root)
			_ui_scan_done = true

	# 2) Etsi pelimaailma joka frame kunnes loytyy (boottausjarjestys voi vaihdella).
	if not _world_ready:
		_try_acquire_world()
		if not _world_ready:
			return

	# Maailma voi kadota (esim. scene-vaihto) -> nollaa ja etsi uudelleen.
	if not is_instance_valid(_world):
		_world = null
		_world_ready = false
		return

	_update_cash(delta)
	_update_mining(delta)


# Yrittaa loytaa pixel_world-noden: nopea polku scene-puusta + defensiivinen haku.
func _try_acquire_world() -> void:
	var w: Node = get_node_or_null("/root/Main/PixelWorld")
	if w == null or not _looks_like_world(w):
		var scene := get_tree().current_scene
		if scene != null:
			w = _find_world_recursive(scene)
	if w == null:
		return
	_world = w
	_world_ready = true
	# Alusta rahalahtoarvo NYT -> ei valhekilahdusta ensimmaisella framella.
	_last_money = _read_money()
	_connect_world_signals()


# Tunnistaa pixel_worldin ilman tyyppiriippuvuutta (duck typing).
func _looks_like_world(n: Node) -> bool:
	return n.has_signal("milestone") and n.has_signal("demo_complete") and ("money" in n)


func _find_world_recursive(node: Node) -> Node:
	if _looks_like_world(node):
		return node
	for c in node.get_children():
		var r := _find_world_recursive(c)
		if r != null:
			return r
	return null


# Kytke demo-kaaren signaalit observerista kasin (EI muutoksia pixel_worldiin).
func _connect_world_signals() -> void:
	if _world.has_signal("milestone") and not _world.is_connected("milestone", _on_milestone):
		_world.connect("milestone", _on_milestone)
	if _world.has_signal("demo_complete") and not _world.is_connected("demo_complete", _on_demo_complete):
		_world.connect("demo_complete", _on_demo_complete)


# --- Kassa-aani ------------------------------------------------------------

func _read_money() -> int:
	var m = _world.get("money")
	if typeof(m) == TYPE_INT or typeof(m) == TYPE_FLOAT:
		return int(m)
	return _last_money


func _update_cash(delta: float) -> void:
	_cash_cooldown = maxf(0.0, _cash_cooldown - delta)
	var m := _read_money()
	if m > _last_money and _cash_cooldown <= 0.0:
		_play_cash()
		_cash_cooldown = 1.0 / CASH_MAX_PER_S
	# Paivita aina (myos ostoksen jalkeen m<last) -> vain kasvu soittaa.
	_last_money = m


func _play_cash() -> void:
	if not _audio_enabled or _cash_player == null or _cash_player.stream == null:
		return
	_cash_player.pitch_scale = randf_range(1.0 - CASH_PITCH_JITTER, 1.0 + CASH_PITCH_JITTER)
	_cash_player.play()


# --- Louhinta-aani ---------------------------------------------------------

func _update_mining(delta: float) -> void:
	# Pause (sim_speed==0) pysayttaa botit -> ei louhinta-aanta.
	var speed = _world.get("sim_speed")
	if (typeof(speed) == TYPE_FLOAT or typeof(speed) == TYPE_INT) and float(speed) <= 0.0:
		_mine_accum = 0.0
		return

	var active := _count_active_miners()
	if active <= 0:
		_mine_accum = 0.0
		return

	_mine_accum += delta
	if _mine_accum >= MINE_INTERVAL:
		# Nollaus (ei -=) -> suuri delta (run_frames) ei tuota purskeita.
		_mine_accum = 0.0
		var voices: int = clampi(active, 1, MINE_MAX_STACKS)
		for i in range(voices):
			_play_mine_chunk()


# Laskee louhivat minerit (MINER-rooli + WORK-tila) READ-ONLY bottilistasta.
func _count_active_miners() -> int:
	var bm = _world.get("bot_manager")
	if bm == null:
		return 0
	var bots = bm.get("bots")
	if bots == null:
		return 0
	var c := 0
	for b in bots:
		if b == null:
			continue
		if int(b.role) == Bot.Role.MINER and int(b.state) == Bot.BotState.WORK:
			c += 1
	return c


func _play_mine_chunk() -> void:
	if not _audio_enabled or _mine_players.is_empty():
		return
	var p := _mine_players[_mine_rr]
	_mine_rr = (_mine_rr + 1) % _mine_players.size()
	if p == null or p.stream == null:
		return
	p.pitch_scale = randf_range(1.0 - MINE_PITCH_JITTER, 1.0 + MINE_PITCH_JITTER)
	p.play()


# --- Milestone / demo complete ---------------------------------------------

func _on_milestone(_text: String) -> void:
	_play_milestone()


func _on_demo_complete() -> void:
	_play_milestone()


func _play_milestone() -> void:
	if not _audio_enabled or _milestone_player == null or _milestone_player.stream == null:
		return
	_milestone_player.play()


# --- UI-klik ---------------------------------------------------------------

func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_connect_button(node)


func _scan_and_connect_buttons(node: Node) -> void:
	if node is BaseButton:
		_connect_button(node)
	for c in node.get_children():
		_scan_and_connect_buttons(c)


func _connect_button(btn: BaseButton) -> void:
	if not btn.pressed.is_connected(_on_ui_click):
		btn.pressed.connect(_on_ui_click)


func _on_ui_click() -> void:
	if not _audio_enabled or _click_players.is_empty():
		return
	var p := _click_players[_click_rr]
	_click_rr = (_click_rr + 1) % _click_players.size()
	if p == null or p.stream == null:
		return
	p.pitch_scale = randf_range(1.0 - UI_CLICK_PITCH_JITTER, 1.0 + UI_CLICK_PITCH_JITTER)
	p.play()
