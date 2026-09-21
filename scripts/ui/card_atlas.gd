class_name CardAtlas
extends RefCounted
## 卡牌图集查表（Feature 16 / UI）
## 职责：把 (type, suit, rank) 映射为 4× 高清图集的 AtlasTexture。
## 纯展示层：不做规则判断。皮肤默认 `original`（旧素材 assets/Cards/*），
## 图集 4 种 type（normal/stone/paper/glass）仅由开发者面板切换预览。
## 图集：14 列 × 16 行；4 行一组（normal/stone/paper/glass），
## 组内行=♥♠♦♣，列 c0..c12=2..A，c13=卡背（组首行）/红 Joker（组第 3 行）/黑 Joker（组第 4 行）。
## 分辨率：使用 4× 高清版（3080×4928，每格 220×308），卡牌显示尺寸取 5:7 且小于格子 → 缩小采样、清晰。
## 1× 原图（每格 55×77）仅在游戏里是放大显示、会糊，故不用作运行时贴图。

const SHEET_PATH := "res://assets/TypeCards/opersze-cards-full-clear-4x.png"
const TILE_W := 55
const TILE_H := 77
const UPSCALE := 4
const CELL_W := TILE_W * UPSCALE
const CELL_H := TILE_H * UPSCALE
const GROUP_ROWS := 4
const ORIGINAL := "original"
const TYPES := ["normal", "stone", "paper", "glass"]
const SKINS := ["original", "normal", "stone", "paper", "glass"]
const SUIT_ROWS := {"♥": 0, "♠": 1, "♦": 2, "♣": 3}
const RANK_COLS := {
	"2": 0, "3": 1, "4": 2, "5": 3, "6": 4, "7": 5, "8": 6, "9": 7, "10": 8,
	"J": 9, "Q": 10, "K": 11, "A": 12,
}
const BACK_COL := 13
const RED_JOKER_OFFSET := 2
const BLACK_JOKER_OFFSET := 3
const NO_BLACK_JOKER := ["stone", "paper"]

static var preview_type := ORIGINAL
static var _sheet_cache: Texture2D = null
static var _cell_cache := {}

static func sheet() -> Texture2D:
	if _sheet_cache == null:
		_sheet_cache = load(SHEET_PATH)
	return _sheet_cache

## 设置全局预览皮肤（无效值回退 original）。
static func set_preview_type(type: String) -> void:
	preview_type = type if SKINS.has(type) else ORIGINAL

static func preview() -> String:
	return preview_type

static func group_index(type: String) -> int:
	var i := TYPES.find(type)
	return i if i >= 0 else 0

## 取单个网格单元（按 (行,列) 缓存 AtlasTexture）；图集缺失返回 null。
static func cell(row: int, col: int) -> Texture2D:
	var key := row * 100 + col
	if _cell_cache.has(key):
		return _cell_cache[key]
	var atlas := sheet()
	if atlas == null:
		return null
	var tex := AtlasTexture.new()
	tex.atlas = atlas
	tex.region = Rect2(col * CELL_W, row * CELL_H, CELL_W, CELL_H)
	_cell_cache[key] = tex
	return tex

## 正脸：rank=="JOKER" 时按 Joker 取图；未知 type/suit/rank 分别回退 normal/♠/2。
static func face(type: String, suit: String, rank: String) -> Texture2D:
	if rank == "JOKER":
		return joker(type, suit)
	var row := group_index(type) * GROUP_ROWS + int(SUIT_ROWS.get(suit, SUIT_ROWS["♠"]))
	return cell(row, int(RANK_COLS.get(rank, 0)))

## Joker：stone/paper 无黑 Joker，回退用红 Joker 格。
static func joker(type: String, suit: String) -> Texture2D:
	var g := group_index(type)
	var offset := RED_JOKER_OFFSET
	if suit == "black" and not NO_BLACK_JOKER.has(TYPES[g]):
		offset = BLACK_JOKER_OFFSET
	return cell(g * GROUP_ROWS + offset, BACK_COL)

static func back(type: String) -> Texture2D:
	return cell(group_index(type) * GROUP_ROWS, BACK_COL)
