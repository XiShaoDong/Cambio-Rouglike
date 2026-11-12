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
@export var bell_sfx: AudioStream  # Kongbaya 铃铛声
@export var bell_pitch := 0.667  # 铃铛音高偏高，降为 2/3（减少三分之一），可在 audio_manager.tscn 调试
@export var winner_sfx: Array[AudioStream] = []  # 结算胜利声（Winner01-04，随机播一个）

# 2026-11-08 音效强化（assets/Sounds2）：抽/弃/贴牌成功失败/触发/倒计时/点击。
@export var card_place_sfx: AudioStream   # 弃牌落堆
@export var card_slide_sfx: AudioStream   # 抽牌滑出（card-slide-8）
@export var click_sfx: AudioStream        # UI 点击（tech-click；Ready / 商店等）
@export var deal_sfx: AudioStream         # 发牌洗牌（card-shuffle，只播前 1.8s）
@export var countdown_sfx: AudioStream    # 结算贴牌 3s 倒计时（整段一次）
@export var notification_sfx: AudioStream # 效果/炸弹触发提示
@export var slap_fail_sfx: AudioStream    # 贴牌失败
@export var slap_success_sfx: AudioStream # 贴牌成功

## 每类事件的额外增益（dB），让关键反馈更明显；最终音量 = 全局音量 + 该值。
const GAIN_DB := {
	"select": 1.0,
	"draw": 2.0,
	"discard": 2.0,
	"slap_success": 4.0,
	"slap_fail": 4.0,
	"trigger": 3.0,
	"countdown": 3.0,
	"deal": 2.0,
}

## 结算倒计时裁剪：素材 countdown.wav 在 0/1/2/3s 各一声 beep（共 4 声）。
## 3s 窗口要 3 声 → 跳过最开始的 1s，从 1s 播到 4s。
const COUNTDOWN_START_SEC := 1.0
const COUNTDOWN_PLAY_SECONDS := 3.0
## 发牌洗牌只播前 1.8s（素材约 3.06s）。
const DEAL_PLAY_SECONDS := 1.8

## 播放器池：交换/替换动画多张卡同时飞，单节点会互相打断，故用池支持重叠。
const POOL_SIZE := 10

var _pool: Array[AudioStreamPlayer] = []
var _countdown_player: AudioStreamPlayer
var _countdown_timer: Timer
var _deal_player: AudioStreamPlayer
var _deal_timer: Timer
var _base_db := 0.0
## 最近一次播放的事件 token（headless 测试用）。
var last_event := ""

func _ready() -> void:
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_pool.append(player)
	# 倒计时单独一个播放器：不被池抢占，且可单独 stop。
	_countdown_player = AudioStreamPlayer.new()
	_countdown_player.name = "CountdownPlayer"
	add_child(_countdown_player)
	# 播放到 4s（=1s+3s）后停止，避免素材尾部静音继续占用。
	_countdown_timer = Timer.new()
	_countdown_timer.name = "CountdownTimer"
	_countdown_timer.one_shot = true
	_countdown_timer.wait_time = COUNTDOWN_PLAY_SECONDS
	_countdown_timer.timeout.connect(stop_countdown)
	add_child(_countdown_timer)
	_deal_player = AudioStreamPlayer.new()
	_deal_player.name = "DealPlayer"
	add_child(_deal_player)
	_deal_timer = Timer.new()
	_deal_timer.name = "DealTimer"
	_deal_timer.one_shot = true
	_deal_timer.wait_time = DEAL_PLAY_SECONDS
	_deal_timer.timeout.connect(stop_deal_shuffle)
	add_child(_deal_timer)
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
	last_event = "select"
	_play(click_sfx if click_sfx != null else select_sfx, 1.0, float(GAIN_DB["select"]))

## 抽牌（大牌出现）——card-slide。
func play_draw() -> void:
	last_event = "draw"
	_play(card_slide_sfx, 1.0, float(GAIN_DB["draw"]))

## 弃牌落堆——card-place。
func play_discard() -> void:
	last_event = "discard"
	_play(card_place_sfx, 1.0, float(GAIN_DB["discard"]))

## 贴牌成功/失败——slap-success / slap-fail。
func play_slap_success() -> void:
	last_event = "slap_success"
	_play(slap_success_sfx, 1.0, float(GAIN_DB["slap_success"]))

func play_slap_fail() -> void:
	last_event = "slap_fail"
	_play(slap_fail_sfx, 1.0, float(GAIN_DB["slap_fail"]))

## 效果/炸弹触发提示——notification。
func play_trigger() -> void:
	last_event = "trigger"
	_play(notification_sfx, 1.0, float(GAIN_DB["trigger"]))

## 结算贴牌 3s 倒计时：跳过素材最开始的 1s（0s 那声弃掉），从 1s 播到 4s。
func play_countdown() -> void:
	last_event = "countdown"
	if countdown_sfx == null or _countdown_player == null:
		return
	_countdown_player.stream = countdown_sfx
	_countdown_player.volume_db = _base_db + float(GAIN_DB["countdown"])
	_countdown_player.play(COUNTDOWN_START_SEC)
	if _countdown_timer != null:
		_countdown_timer.start(COUNTDOWN_PLAY_SECONDS)

## 窗口提前结束（贴中/离开结算）时停止倒计时。
func stop_countdown() -> void:
	if _countdown_player != null:
		_countdown_player.stop()
	if _countdown_timer != null:
		_countdown_timer.stop()

## 发牌洗牌：每次新局播放前 1.8s。
func play_deal_shuffle() -> void:
	last_event = "deal_shuffle"
	if deal_sfx == null or _deal_player == null:
		return
	_deal_player.stream = deal_sfx
	_deal_player.volume_db = _base_db + float(GAIN_DB["deal"])
	_deal_player.play()
	if _deal_timer != null:
		_deal_timer.start(DEAL_PLAY_SECONDS)

func stop_deal_shuffle() -> void:
	if _deal_player != null:
		_deal_player.stop()
	if _deal_timer != null:
		_deal_timer.stop()

func play_flip() -> void:
	last_event = "flip"
	_play(flip_sfx)

func play_flip_quick() -> void:
	last_event = "flip_quick"
	_play(flip_quick_sfx)

func play_fly() -> void:
	last_event = "fly"
	_play(fly_sfx)

## Kongbaya 铃铛声（全员收到；音高已按 bell_pitch 降低）。
func play_bell() -> void:
	_play(bell_sfx, bell_pitch)

## 结算胜利声：index>=0 时播指定曲目（服务器下发，保证所有客户端一致）；否则随机。
func play_winner(index := -1) -> float:
	if winner_sfx.is_empty():
		return 0.0
	var i := index if index >= 0 else randi()
	var stream := winner_sfx[clampi(i, 0, winner_sfx.size() - 1)]
	_play(stream)
	return stream.get_length() if stream != null else 0.0

## 播放一个音效；素材未绑定（stream 为 null）时静默跳过，不报错。
func _play(stream: AudioStream, pitch := 1.0, gain_db := 0.0) -> void:
	if stream == null:
		return
	var player := _next_player()
	player.stream = stream
	player.pitch_scale = pitch
	player.volume_db = _base_db + gain_db
	player.play()

## 取一个空闲播放器；全部占用时覆盖池中第一个（可接受丢弃最早音效）。
func _next_player() -> AudioStreamPlayer:
	for player in _pool:
		if not player.playing:
			return player
	return _pool[0]

## 线性音量 0.0~1.0，应用于池内所有播放器（各自的每次播放增益在 _play 时叠加）。
func set_volume(volume_linear: float) -> void:
	_base_db = linear_to_db(maxf(clampf(volume_linear, 0.0, 1.0), 0.0001))
	for player in _pool:
		player.volume_db = _base_db
	if _countdown_player != null:
		_countdown_player.volume_db = _base_db + float(GAIN_DB["countdown"])
	if _deal_player != null:
		_deal_player.volume_db = _base_db + float(GAIN_DB["deal"])

func set_muted(muted: bool) -> void:
	# AudioStreamPlayer 无 mute 属性，用 Master 总线静音（全局生效、即时打断）
	var bus := AudioServer.get_bus_index("Master")
	if bus >= 0:
		AudioServer.set_bus_mute(bus, muted)
