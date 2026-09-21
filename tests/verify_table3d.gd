extends Node
## headless 单元测试：3D 预览的节点层（CardBlock / 相机 / 快照渲染）。

var failures := 0
var checks := 0

func _ready() -> void:
	await _run()
	print("=== TABLE3D RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _run() -> void:
	_test_card_block()

func _test_card_block() -> void:
	var known := CardBlock.new()
	add_child(known)
	known.setup({"card": {"rank": "A", "suit": "♥"}})
	_check("CardBlock 已知牌文本 A♥", known.label_text() == "A♥")
	_check("CardBlock 已知牌颜色", known.block_color() == Table3dLayout.known_color_for_rank("A"))
	_check("CardBlock 非保护不自发光", not known.is_emissive())
	var unknown := CardBlock.new()
	add_child(unknown)
	unknown.setup({})
	_check("CardBlock 未知牌无文本", unknown.label_text() == "")
	_check("CardBlock 未知牌颜色", unknown.block_color() == Table3dLayout.UNKNOWN_COLOR)
	var prot := CardBlock.new()
	add_child(prot)
	prot.setup({"protected": true, "card": {"rank": "K", "suit": "♠"}})
	_check("CardBlock 护盾自发光", prot.is_emissive())
	_check("CardBlock 护盾紫色", prot.block_color() == CardBlock.PROTECTED_COLOR)
	_check("CardBlock 护盾仍显示点数", prot.label_text() == "K♠")
	_check("CardBlock Joker 文本", CardBlock.card_text({"rank": "JOKER", "suit": "red"}) == "JOKER")
	_check("CardBlock 空卡文本", CardBlock.card_text({}) == "")
