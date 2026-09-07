class_name Cursor
extends CanvasLayer
## 光标系统（方案 A 混合式）
## 状态：pointer(默认=open_hand) / peek / flip。默认关闭（Settings.cursor.enabled=false）。
## 开启时：open_hand 挂 POINTING_HAND shape（全局默认）、peek 挂 CROSS shape；flip 走场景内 AnimatedSprite2D。
## 关闭时：set_default_cursor_shape(ARROW) 回原生箭头（ARROW shape 从不注册自定义纹理，无需清除）。
## 哑渲染：卡牌语义由 game 层通过 set_card_resolver 提供。不负责任何规则判断。

const PHASE_TURN_DRAW := 2

const STATE_POINTER := "pointer"
const STATE_PEEK := "peek"
const STATE_FLIP := "flip"

const CURSOR_OPEN_HAND_TEX := "res://assets/Cursor/card_game_cursors/cursor_open_hand_64px.png"
const CURSOR_PEEK_TEX := "res://assets/Cursor/card_game_cursors/cursor_peek_64px.png"

## OS 光标热点（掌心/眼睛中心，可在编辑器调）。
@export var open_hand_hotspot := Vector2(27, 32)
@export var peek_hotspot := Vector2(29, 32)
## flip 动画相对鼠标的额外偏移（默认 0；也可直接调 AnimatedSprite2D 自身的 offset）。
@export var flip_offset := Vector2.ZERO

var _card_resolver: Callable
var _anim: AnimatedSprite2D
var _current := STATE_POINTER
var _enabled := false

func _ready() -> void:
	_anim = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	_enabled = bool(Settings.get_setting("cursor", "enabled", false))
	if _enabled:
		_enable()
	else:
		_disable()
	Settings.setting_changed.connect(_on_setting_changed)

## 设置菜单切换即时生效。
func _on_setting_changed(section: String, key: String, value: Variant) -> void:
	if section == "cursor" and key == "enabled":
		_enabled = bool(value)
		if _enabled:
			_enable()
		else:
			_disable()

## 启用：注册 OS 光标 + 断言初始状态（隐藏并停掉 autoplay 的 flip 动画）。_apply 内已强制刷新。
func _enable() -> void:
	_register_os_cursors()
	_current = STATE_POINTER
	_apply(STATE_POINTER)
	set_process(true)

## 禁用：回原生箭头（ARROW shape 从不注册自定义纹理），停掉一切自定义光标与动画 + 强制刷新 OS 光标。
## 注意：不能 set_custom_mouse_cursor(null,...) 清纹理——macOS DisplayServer 报 "imgrep is null"。
func _disable() -> void:
	set_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _anim != null:
		_anim.visible = false
		_anim.stop()
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	_current = STATE_POINTER
	_force_cursor_refresh()

## 强制 Viewport 重新评估鼠标光标形状：set_default_cursor_shape 只在鼠标移动时生效，
## 切换开关后需 warp 到原位触发一次鼠标移动，OS 光标才会立即更新。
func _force_cursor_refresh() -> void:
	var vp := get_viewport()
	if vp != null:
		vp.warp_mouse(vp.get_mouse_position())

## 注册 OS 自定义光标：open_hand 挂 POINTING_HAND、peek 挂 CROSS。ARROW shape 保持原生（关闭时直接切回）。
func _register_os_cursors() -> void:
	var open_hand := load(CURSOR_OPEN_HAND_TEX) as Texture2D
	var peek := load(CURSOR_PEEK_TEX) as Texture2D
	if open_hand != null:
		Input.set_custom_mouse_cursor(open_hand, Input.CURSOR_POINTING_HAND, open_hand_hotspot)
	if peek != null:
		Input.set_custom_mouse_cursor(peek, Input.CURSOR_CROSS, peek_hotspot)

## game 层注册卡牌状态解析器：card(Control) -> String（pointer/peek/flip）。
func set_card_resolver(resolver: Callable) -> void:
	_card_resolver = resolver

func _process(_delta: float) -> void:
	if not _enabled:
		return
	var hovered := get_viewport().gui_get_hovered_control()
	var is_card := hovered is CardView
	var card_state := STATE_POINTER
	if is_card and _card_resolver.is_valid():
		card_state = _card_resolver.call(hovered)
	var state := resolve_state(is_card, card_state)
	state = apply_hold(state, Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))
	if state == STATE_FLIP and _anim != null:
		_anim.position = get_viewport().get_mouse_position() + flip_offset
	if state == _current:
		return
	_current = state
	_apply(state)

## 状态应用：flip 走场景内动画（隐藏 OS 光标），其余走 OS 光标。
func _apply(state: String) -> void:
	if state == STATE_FLIP:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		if _anim != null:
			_anim.visible = true
			_anim.frame = 0
			_anim.stop()
			if _anim.sprite_frames != null and _anim.sprite_frames.has_animation("flip"):
				_anim.play("flip")
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _anim != null:
		_anim.visible = false
		_anim.stop()
	if state == STATE_PEEK:
		Input.set_default_cursor_shape(Input.CURSOR_CROSS)
	else:
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
	_force_cursor_refresh()

## ── 纯函数（headless 可测，不依赖节点/viewport）──

## 卡牌状态：贴牌窗口（任意卡牌，自己或他人）→flip；peek 能力模式可点牌→peek；其余→pointer(open_hand)。
static func resolve_card_state(state: Dictionary, action_mode: String, actionable: bool) -> String:
	if bool(state.get("slap_open", false)) and int(state.get("phase", 0)) == PHASE_TURN_DRAW:
		return STATE_FLIP
	if action_mode in ["peek_own", "peek_other", "queen_target"] and actionable:
		return STATE_PEEK
	return STATE_POINTER

## 通用 hover：卡牌用 resolver 结果；其余一律 pointer(open_hand)。
static func resolve_state(is_card_hovered: bool, card_state: String) -> String:
	if is_card_hovered:
		return card_state
	return STATE_POINTER

## hold 升级：peek 状态下按住鼠标左键 → flip 动画（pointer 按住不升级）。
static func apply_hold(state: String, mouse_down: bool) -> String:
	if state == STATE_PEEK and mouse_down:
		return STATE_FLIP
	return state