extends Node
## 全局音效管理器（autoload，scene 注册以便 @export 可在编辑器调整）
## 职责：统一播放卡牌交互音效。所有 CardView/CardAnimator/交互层通过本管理器发声，
## 不在卡牌实例上挂 AudioStreamPlayer（避免每张卡重复背一个播放器）。
## 命名约定：方法名 = 事件 token，@export 槽位同名；素材文件保持描述性原名：
##   select(有效点击)  -> mouse-click.mp3
##   flip(看牌慢翻)    -> card-flip.wav
##   flip_quick(飞行快翻) -> card-flip-quick.mp3
##   fly(卡牌移动嗖声)  -> card-fly.wav

@export var select_sfx: AudioStream
@export var flip_sfx: AudioStream
@export var flip_quick_sfx: AudioStream
@export var fly_sfx: AudioStream

## 播放器池：交换/替换动画多张卡同时飞，单节点会互相打断，故用池支持重叠。
const POOL_SIZE := 6

var _pool: Array[AudioStreamPlayer] = []

func _ready() -> void:
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_pool.append(player)
	set_volume(float(Settings.get_setting("audio", "volume", 1.0)))
	set_muted(bool(Settings.get_setting("audio", "muted", false)))
	Settings.setting_changed.connect(_on_setting_changed)

## 设置变更即时生效：音量/静音由 Settings 统一管理。
func _on_setting_changed(section: String, key: String, value: Variant) -> void:
	if section != "audio":
		return
	match key:
		"volume":
			set_volume(float(value))
		"muted":
			set_muted(bool(value))

func play_select() -> void:
	_play(select_sfx)

func play_flip() -> void:
	_play(flip_sfx)

func play_flip_quick() -> void:
	_play(flip_quick_sfx)

func play_fly() -> void:
	_play(fly_sfx)

## 播放一个音效；素材未绑定（stream 为 null）时静默跳过，不报错。
func _play(stream: AudioStream) -> void:
	if stream == null:
		return
	var player := _next_player()
	player.stream = stream
	player.play()

## 取一个空闲播放器；全部占用时覆盖池中第一个（可接受丢弃最早音效）。
func _next_player() -> AudioStreamPlayer:
	for player in _pool:
		if not player.playing:
			return player
	return _pool[0]

## 线性音量 0.0~1.0，应用于池内所有播放器。
func set_volume(volume_linear: float) -> void:
	var db := linear_to_db(maxf(clampf(volume_linear, 0.0, 1.0), 0.0001))
	for player in _pool:
		player.volume_db = db

func set_muted(muted: bool) -> void:
	# AudioStreamPlayer 无 mute 属性，用 Master 总线静音（全局生效、即时打断）
	var bus := AudioServer.get_bus_index("Master")
	if bus >= 0:
		AudioServer.set_bus_mute(bus, muted)