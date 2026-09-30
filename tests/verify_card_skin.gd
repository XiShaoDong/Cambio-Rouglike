extends Node
## headless 单元测试：卡牌皮肤（CardAtlas 图集映射 + CardView 渲染）
## 覆盖：4 种 type 的正脸/卡背/Joker region 坐标、stone/paper 黑 Joker 回退、
##       未知 type/suit/rank 回退、preview_type 切换后卡牌正/背面随之变化。

const CARD_SCENE := "res://scenes/ui/card.tscn"

var failures := 0
var checks := 0

func _ready() -> void:
	await _run()
	print("=== CARD SKIN RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _rect(col: int, row: int) -> Rect2:
	return Rect2(col * CardAtlas.CELL_W, row * CardAtlas.CELL_H, CardAtlas.CELL_W, CardAtlas.CELL_H)

func _region(tex: Texture2D) -> Rect2:
	if tex is AtlasTexture:
		return (tex as AtlasTexture).region
	return Rect2(-1, -1, -1, -1)

func _make_card(data: Dictionary) -> CardView:
	var cv := load(CARD_SCENE).instantiate() as CardView
	add_child(cv)
	cv.setup(data)
	await get_tree().process_frame
	return cv

func _run() -> void:
	CardAtlas.preview_type = CardAtlas.ORIGINAL
	_check("默认预览 original", CardAtlas.preview() == "original")
	# 4× 高清图集（每格 220×308 = 55×77 × 4）
	_check("格子 220×308", CardAtlas.CELL_W == 220 and CardAtlas.CELL_H == 308)
	_check("图集 3080×4928", CardAtlas.sheet() != null and CardAtlas.sheet().get_size() == Vector2(3080, 4928))
	# 正脸：组行 = g*4 + 花色行(♥0/♠1/♦2/♣3)，列 = 点数(2→0..10→8,J9,Q10,K11,A12)
	_check("normal ♥2", _region(CardAtlas.face("normal", "♥", "2")) == _rect(0, 0))
	_check("normal ♥10", _region(CardAtlas.face("normal", "♥", "10")) == _rect(8, 0))
	_check("normal ♥A", _region(CardAtlas.face("normal", "♥", "A")) == _rect(12, 0))
	_check("normal ♠Q", _region(CardAtlas.face("normal", "♠", "Q")) == _rect(10, 1))
	_check("stone ♣K", _region(CardAtlas.face("stone", "♣", "K")) == _rect(11, 7))
	_check("paper ♦7", _region(CardAtlas.face("paper", "♦", "7")) == _rect(5, 10))
	_check("glass ♠J", _region(CardAtlas.face("glass", "♠", "J")) == _rect(9, 13))
	# 卡背：组首行 c13
	_check("back normal", _region(CardAtlas.back("normal")) == _rect(13, 0))
	_check("back stone", _region(CardAtlas.back("stone")) == _rect(13, 4))
	_check("back paper", _region(CardAtlas.back("paper")) == _rect(13, 8))
	_check("back glass", _region(CardAtlas.back("glass")) == _rect(13, 12))
	# Joker：组第 3 行=红、第 4 行=黑；stone/paper 无黑→回退红
	_check("红 Joker normal", _region(CardAtlas.face("normal", "red", "JOKER")) == _rect(13, 2))
	_check("黑 Joker normal", _region(CardAtlas.face("normal", "black", "JOKER")) == _rect(13, 3))
	_check("红 Joker stone", _region(CardAtlas.face("stone", "red", "JOKER")) == _rect(13, 6))
	_check("黑 Joker stone→红", _region(CardAtlas.face("stone", "black", "JOKER")) == _rect(13, 6))
	_check("黑 Joker paper→红", _region(CardAtlas.face("paper", "black", "JOKER")) == _rect(13, 10))
	_check("红 Joker glass", _region(CardAtlas.face("glass", "red", "JOKER")) == _rect(13, 14))
	_check("黑 Joker glass", _region(CardAtlas.face("glass", "black", "JOKER")) == _rect(13, 15))
	# 回退
	_check("未知 type→normal", _region(CardAtlas.back("nope")) == _rect(13, 0))
	_check("未知 suit→黑桃行", _region(CardAtlas.face("normal", "?", "2")) == _rect(0, 1))
	_check("未知 rank→2", _region(CardAtlas.face("normal", "♥", "?")) == _rect(0, 0))
	CardAtlas.set_preview_type("nope")
	_check("set_preview_type 无效值回退 original", CardAtlas.preview() == "original")
	# 默认皮肤 original：走旧素材（非 AtlasTexture）
	var o1 := await _make_card({})
	_check("默认空卡背=旧背 back07", o1.get_node("Back/BackTexture").texture.resource_path == "res://assets/Cards/back07.png")
	var o2 := await _make_card({"rank": "7", "suit": "♥"})
	_check("默认正面=旧素材 hearts_07", o2.get_node("Front/FrontTexture").texture.resource_path == "res://assets/Cards/hearts_07.png")
	var o3 := await _make_card({"rank": "JOKER", "suit": "red"})
	_check("默认红 Joker=旧素材 Joker1", o3.get_node("Front/FrontTexture").texture.resource_path == "res://assets/Cards/Joker1.png")
	# 切到图集皮肤后，正/背面改为 AtlasTexture 且 region 随 type 变化
	CardAtlas.set_preview_type("normal")
	var cv1 := await _make_card({})
	_check("空卡背 normal", _region(cv1.get_node("Back/BackTexture").texture) == _rect(13, 0))
	var cv1f := await _make_card({"rank": "7", "suit": "♥"})
	_check("正面 normal ♥7", _region(cv1f.get_node("Front/FrontTexture").texture) == _rect(5, 0))
	CardAtlas.set_preview_type("stone")
	var cv2 := await _make_card({})
	_check("空卡背 stone", _region(cv2.get_node("Back/BackTexture").texture) == _rect(13, 4))
	var cv3 := await _make_card({"rank": "7", "suit": "♥"})
	_check("正面 stone ♥7", _region(cv3.get_node("Front/FrontTexture").texture) == _rect(5, 4))
	CardAtlas.set_preview_type("glass")
	var cv4 := await _make_card({"rank": "K", "suit": "♦"})
	_check("正面 glass ♦K", _region(cv4.get_node("Front/FrontTexture").texture) == _rect(11, 14))
	var cv5 := await _make_card({"rank": "JOKER", "suit": "black", "type": "normal"})
	_check("显式 type 覆盖预览（黑 Joker normal）", _region(cv5.get_node("Front/FrontTexture").texture) == _rect(13, 3))
	var cv6 := await _make_card({"rank": "7", "suit": "♥", "type": "original"})
	_check("显式 type=original 回旧素材", cv6.get_node("Front/FrontTexture").texture.resource_path == "res://assets/Cards/hearts_07.png")
	CardAtlas.set_preview_type(CardAtlas.ORIGINAL)
