# Sprite-loader — lataa assets/sprites/manifest.json + PNG-framet ajonaikaisesti.
# EI kayta load("res://...")-resurssilatausta: nama PNG:t ovat uusia eika niilla ole
# Godotin .import-tiedostoja, joten resurssilataus ei toimi (varsinkaan headlessissa).
# Image.load_from_file() + ImageTexture.create_from_image() lukee tiedoston suoraan levylta.
class_name SpriteAtlas
extends RefCounted

var _frames: Dictionary = {}   # nimi -> Array[Texture2D] (framet jarjestyksessa)
var _meta: Dictionary = {}     # nimi -> { "w": int, "h": int, "anchor": String }


# Lataa manifest.json + kaikki PNG-framet hakemistosta dir (esim. "res://assets/sprites").
# Virheet (puuttuva manifest/PNG) eivat kaadu — atlas jaa vain vajaaksi ja tex()/has()
# palauttavat null/false kutsujalle, joka piirtaa fallback-primitiivin.
func load_dir(dir: String) -> void:
	var mf := FileAccess.get_file_as_string(dir + "/manifest.json")
	if mf.is_empty():
		push_warning("SpriteAtlas: manifest.json puuttuu tai tyhja (%s)" % dir)
		return
	var data: Variant = JSON.parse_string(mf)
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("SpriteAtlas: manifest.json ei ole kelvollinen JSON (%s)" % dir)
		return
	for e: Dictionary in data.get("sprites", []):
		var name: String = e.get("name", "")
		if name.is_empty():
			continue
		var texs: Array = []
		for fn in e.get("files", []):
			var img := Image.load_from_file(dir + "/" + String(fn))
			if img == null:
				push_warning("SpriteAtlas: PNG:n lataus epaonnistui (%s/%s)" % [dir, fn])
				continue
			texs.append(ImageTexture.create_from_image(img))
		if texs.is_empty():
			continue
		_frames[name] = texs
		_meta[name] = { "w": e.get("w", 0), "h": e.get("h", 0), "anchor": e.get("anchor", "topleft") }


# Palauttaa spriten framen (kiertaa framejen lukumaaralla). null jos nimea ei tunneta.
func tex(name: String, frame: int) -> Texture2D:
	var a: Array = _frames.get(name, [])
	if a.is_empty():
		return null
	return a[frame % a.size()]


func has(name: String) -> bool:
	return _frames.has(name)


# Metatieto (w/h/anchor) nimella. Tyhja Dictionary jos ei loydy.
func meta(name: String) -> Dictionary:
	return _meta.get(name, {})
