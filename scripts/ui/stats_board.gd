class_name StatsBoard
extends Control
## Stats 面板：把"弃牌堆出现过的牌"按 4 行花色（♠♥♣♦）扇形展开（A..K + Joker）。
## 每张牌有**固定槽位**（按 A..K 顺序），只在对应格出现（未出现则留空）。
## 纯展示层：数据来自快照 `discard_history`（公开信息）。红 Joker 入 ♥ 行、黑 Joker 入 ♠ 行。

const CARD_SIZE := Vector2(46, 64)
const STEP_FRAC := 0.62        # 相邻槽位间距（卡宽比例；越大越不遮挡）
const ROW_GAP := 24.0          # 行间距
const ARC := 6.0               # 扇形弧度（中点抬高）
const TILT_DEG := 2.5          # 两端最大倾角
const X0 := 46.0               # 行首（让开行标签）
const TEXT_MUTED := Color(0.35, 0.38, 0.44)
const ROW_SUITS := ["♠", "♥", "♣", "♦"]
const SUIT_LABEL := {"♠": "黑桃", "♥": "红桃", "♣": "梅花", "♦": "方片"}
const RANK_ORDER := ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "JOKER"]

var _shown := {}   # card id -> true（去重）
var _card_count := 0
var _factory: CardFactory

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## 用弃牌历史构建（history：公开卡牌字典数组）。
func setup(history: Array) -> void:
	if _factory == null:
		_factory = CardFactory.new()
	for c in get_children():
		c.queue_free()
	_shown.clear()
	_card_count = 0
	# 分组：普通牌按 suit；Joker 红→♥、黑→♠。
	var rows := {}
	for s in ROW_SUITS:
		rows[s] = {}
	for card in history:
		var cid := str(card.get("id", ""))
		if cid != "":
			if _shown.has(cid):
				continue
			_shown[cid] = true
		var rank := str(card.get("rank", ""))
		var suit := str(card.get("suit", ""))
		if rank == "JOKER":
			rows["♥" if suit == "red" else "♠"][rank] = card
		elif rows.has(suit):
			rows[suit][rank] = card
	var y := 0.0
	var max_w := 0.0
	for s in ROW_SUITS:
		var w := _layout_row(s, rows[s], y)
		max_w = maxf(max_w, w)
		y += CARD_SIZE.y + ROW_GAP
	if y > 0.0:
		y -= ROW_GAP
	custom_minimum_size = Vector2(maxf(max_w, 120.0), maxf(y, CARD_SIZE.y))

## 固定槽位：按 RANK_ORDER 每个槽位固定 X/Y/角度；只在有牌的槽位放置 CardView。
func _layout_row(suit: String, by_rank: Dictionary, y: float) -> float:
	var label := Label.new()
	label.text = SUIT_LABEL.get(suit, suit)
	label.add_theme_color_override("font_color", TEXT_MUTED)
	label.add_theme_font_size_override("font_size", 14)
	label.position = Vector2(0.0, y + CARD_SIZE.y * 0.5 - 8.0)
	add_child(label)
	var step := CARD_SIZE.x * STEP_FRAC
	var n := RANK_ORDER.size()
	var i := 0
	for rank in RANK_ORDER:
		if by_rank.has(rank):
			var t := 0.0 if n <= 1 else float(i) / float(n - 1)
			var card_node = _factory.make_card(by_rank[rank], CARD_SIZE)
			card_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card_node.focus_mode = Control.FOCUS_NONE
			card_node.pivot_offset = CARD_SIZE * 0.5
			card_node.position = Vector2(X0 + step * i, y + ARC * (1.0 - pow(2.0 * t - 1.0, 2.0)))
			card_node.rotation_degrees = -TILT_DEG * (2.0 * t - 1.0)
			add_child(card_node)
			_card_count += 1
		i += 1
	return X0 + step * (n - 1) + CARD_SIZE.x

## 测试访问器。
func card_count() -> int:
	return _card_count
