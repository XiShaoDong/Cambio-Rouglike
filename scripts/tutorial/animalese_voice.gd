class_name AnimaleseVoice
extends Node
## 动物森友会式逐字母发音：a-z / 0-9 映射到 36 个短音效，按字母变调播放。
## 音效来自 Animal Voices（GameMaker 资源包）的 snd_light_ 一组。

const CHARS := "abcdefghijklmnopqrstuvwxyz0123456789"
const BASE_CHARS_PER_SECOND := 18.0
const LOOKAHEAD := 5

@export var stream_folder := "res://assets/animalese/light"
@export var prefix := "snd_light_"
## 基准音高（1.0 为原速原调）。动物森友会常用 2.0：音更高、每个字母更短。
@export_range(0.05, 4.0, 0.01) var base_pitch := 2.0
## 每个字母在基准音高上随机上浮的比例；0.32 即 2.0~2.64。
@export_range(0.0, 0.6, 0.01) var pitch_variance := 0.32
## 打字/发音速度倍率（1.0 = 18 字母/秒）。
@export_range(0.25, 3.0, 0.01) var speed := 1.25
@export_range(-40.0, 6.0, 0.5) var gain_db := -3.0
## 英文以外的字符（中文等）是否也用字母音代替发音。
@export var babble_unknown := true
@export var pool_size := 16

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _cursor := 0
var _base_db := 0.0


func _ready() -> void:
	load_streams()
	_build_pool()
	_apply_volume()
	var settings := get_node_or_null("/root/Settings")
	if settings != null and settings.has_signal("setting_changed"):
		settings.setting_changed.connect(_on_setting_changed)


func load_streams() -> int:
	_streams.clear()
	for i in CHARS.length():
		var ch := CHARS[i]
		var stream := _load_letter(ch)
		if stream != null:
			_streams[ch] = stream
	return _streams.size()


func _load_letter(ch: String) -> AudioStream:
	for ext in [".ogg", ".wav"]:
		var path := "%s/%s%s%s" % [stream_folder, prefix, ch, ext]
		if ResourceLoader.exists(path):
			var stream: AudioStream = load(path)
			if stream != null:
				return stream
	return null


func stream_count() -> int:
	return _streams.size()


func seconds_per_char() -> float:
	return 1.0 / maxf(BASE_CHARS_PER_SECOND * speed, 0.001)


func play_char(_ch: String, _question := false) -> bool:
	if _players.is_empty():
		return false
	var key := _ch.to_lower()
	var stream: AudioStream = _streams.get(key)
	if stream == null:
		if not babble_unknown:
			return false
		var code := _ch.unicode_at(0)
		if code < 128:
			return false
		key = CHARS[code % CHARS.length()]
		stream = _streams.get(key)
		if stream == null:
			return false
	var player := _next_player()
	if player == null:
		return false
	player.stream = stream
	var pitch := base_pitch * (1.0 + randf() * pitch_variance)
	if _question:
		pitch += 0.5
	player.pitch_scale = clampf(pitch, 0.05, 4.0)
	player.volume_db = _base_db + gain_db
	player.play()
	return true


func stop_all() -> void:
	for player in _players:
		player.stop()


func is_question(text: String, index: int) -> bool:
	var end := mini(text.length(), index + LOOKAHEAD)
	for i in range(maxi(index, 0), end):
		var ch := text[i]
		if ch == " " or ch == "," or ch == ":" or ch == ";" or ch == "\"" or ch == "'":
			continue
		if ch == "?":
			return true
		if ch == "." or ch == "!":
			return false
	return false


func _build_pool() -> void:
	_players.clear()
	for i in pool_size:
		var player := AudioStreamPlayer.new()
		player.name = "Letter%d" % i
		add_child(player)
		_players.append(player)


func _next_player() -> AudioStreamPlayer:
	for player in _players:
		if not player.playing:
			return player
	if _players.is_empty():
		return null
	var player: AudioStreamPlayer = _players[_cursor]
	_cursor = (_cursor + 1) % _players.size()
	return player


func _apply_volume() -> void:
	var linear := 1.0
	var settings := get_node_or_null("/root/Settings")
	if settings != null and settings.has_method("get_setting"):
		linear = float(settings.get_setting("audio", "volume", 1.0))
	_base_db = linear_to_db(maxf(clampf(linear, 0.0, 1.0), 0.0001))


func _on_setting_changed(section: String, key: String, _value: Variant) -> void:
	if section == "audio" and key == "volume":
		_apply_volume()
