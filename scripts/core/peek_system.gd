class_name PeekSystem
extends RefCounted
## 看牌/揭示系统（Feature 08）
## 职责：把一张/多张牌私下揭示给指定玩家，并在目标卡牌位置由 UI 翻转展示。
## 本类持有 GameState 引用，负责：构造揭示数据、通过 RPC 发送到目标玩家。
## 不负责：能力合法性判断、玩家选择目标（由 GameState/EffectSystem 处理）。

var game: Node  # GameState 引用

func _init(state: Node) -> void:
	game = state

## 把 revealed_cards 私下发送给 seat 玩家，附带 target 上下文（用于 UI 定位翻转）。
func send_reveal(seat: int, title: String, revealed_cards: Array, target: Dictionary = {}) -> void:
	var peer := int(game.players.get(seat, {}).get("peer_id", 0))
	if peer <= 0:
		return
	if peer == 1:
		game._receive_reveal(title, revealed_cards, target)
	else:
		game.receive_reveal.rpc_id(peer, title, revealed_cards, target)

## 生成单张牌的公共表示（用于揭示）。
func public_card(card_id: String) -> Dictionary:
	return HiddenInfo.public_card(game, card_id)

## 本地接收揭示（host 自身）。
func _receive_local(title: String, revealed_cards: Array, target: Dictionary = {}) -> void:
	game._receive_reveal(title, revealed_cards, target)
