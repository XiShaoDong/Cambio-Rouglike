# KONG 卡牌皮肤（Card Template）设计 v1

> **前置**：纯客户端展示层改动。不接入玩法规则（石头/纸/玻璃的效果未定义），不改服务器权威 / 私有快照 / 网络协议 / RPC。`card_data["type"]` 仅作为**预留字段**（未来接入玩法时零改渲染层）。不启 GUI，以 headless 单测 + `tools/run_all_tests.sh` 回归验证。

## 1. 目标

1. 卡牌正/背面**默认使用原始素材**（`res://assets/Cards/*.png` + `back07.png`），保持既有观感。
2. 在开发者工具面板（`T` 开发者模式，房主对局中）集成**全局单选**的卡牌皮肤切换：**原始 / 普通 / 石头 / 纸牌 / 玻璃**（后四者来自 4× 高清图集，含各自卡背）。

## 2. 图集规格

- 运行时文件：`assets/TypeCards/opersze-cards-full-clear-4x.png`，尺寸 **3080×4928**（4× 高清版）。
  - 源文件：`assets/TypeCards/opersze-cards-full.png`（770×1232，1×）仅作素材保留，不用于运行时（1× 每卡 55×77，在游戏里是放大显示会糊）。
- 网格：**14 列 × 16 行**，每格 **220×308**（= 逻辑 55×77 × 4）。
- 组：4 行一组，共 4 组 —— `normal`(行0-3) / `stone`(行4-7) / `paper`(行8-11) / `glass`(行12-15)。
- 组内行 = 花色，顺序：**红心♥(0) / 黑桃♠(1) / 方片♦(2) / 梅花♣(3)**。
- 列 c0..c12 = 点数：**2,3,4,5,6,7,8,9,10,J,Q,K,A**（2→0 … 10→8，J→9，Q→10，K→11，A→12）。
- 第 14 列（c13）：
  - 组内**第一行**（`g*4+0`）= 该 type 的**卡背**。
  - 组内**第三行**（`g*4+2`）= **红 Joker**。
  - 组内**第四行**（`g*4+3`）= **黑 Joker**。
  - `stone` / `paper` 无黑 Joker → **回退使用红 Joker 格**（`g*4+2`）。

## 3. 组件与文件

| 文件 | 职责 |
| --- | --- |
| `scripts/ui/card_atlas.gd`（新增，`class_name CardAtlas`） | 图集查表：`(type,suit,rank)` → `AtlasTexture`；`type` → 卡背；全局 `preview_type` |
| `scripts/ui/card_view.gd`（改） | 正脸/卡背改用 `CardAtlas`（默认 `normal`，素材缺失回退现有 `back07.png`） |
| `scripts/ui/dev_tools.gd`（改） | 开发者面板新增"卡牌皮肤"全局单选按钮行 |
| `tests/verify_card_skin.gd` + `.tscn`（新增） | 断言各 type 的 region 坐标 / 回退 / 切换重绘 |

**不改**：`game_state.gd` / `hidden_info.gd` / 网络协议 / 快照 / RPC / 各 core 系统。`card_data["type"]` 目前不写入（仅读取时带默认值）。

## 4. CardAtlas 接口

```gdscript
class_name CardAtlas
extends RefCounted

const SHEET_PATH := "res://assets/TypeCards/opersze-cards-full-clear-4x.png"
const TILE_W := 55
const TILE_H := 77
const UPSCALE := 4
const CELL_W := TILE_W * UPSCALE   # 220
const CELL_H := TILE_H * UPSCALE   # 308
const ORIGINAL := "original"
const TYPES := ["normal", "stone", "paper", "glass"]
const SKINS := ["original", "normal", "stone", "paper", "glass"]   # 开发者面板可选项
const SUIT_ROWS := {"♥": 0, "♠": 1, "♦": 2, "♣": 3}
const RANK_COLS := {"2":0,"3":1,"4":2,"5":3,"6":4,"7":5,"8":6,"9":7,"10":8,"J":9,"Q":10,"K":11,"A":12}
const BACK_COL := 13
const RED_JOKER_OFFSET := 2   # 组内相对行
const BLACK_JOKER_OFFSET := 3
const NO_BLACK_JOKER := ["stone", "paper"]

static var preview_type := ORIGINAL    # 默认原始素材；图集 type 仅供预览

static func set_preview_type(t: String) -> void   # 无效值回退 ORIGINAL
static func preview() -> String          # 返回 preview_type

static func face(type: String, suit: String, rank: String) -> Texture2D
static func back(type: String) -> Texture2D
```

- `ORIGINAL` 不查图集：`CardView` 直接走旧素材 `res://assets/Cards/*` + `back07.png`。
- 未知 `type` → 回退 `normal`；未知 `suit` → 回退 ♠ 行；未知 `rank` → 回退 c0。
- `AtlasTexture` 按 `(row,col)` 缓存，避免重复创建。

**素材缺失容错**：`SHEET_PATH` 加载失败（null）时，`CardView` 回退现有 `res://assets/Cards/back07.png` 与 `{suit}_{rank}.png` 逻辑，保证不崩。

## 5. 渲染层

- `CardView._current_type()` = `card_data.get("type", CardAtlas.preview())`（默认 `original`）。
- `type == "original"` → 旧素材：正面 `assets/Cards/{suit}_{rank}.png`（Joker 用 `Joker1/2.png`），背面 `back07.png`。
- 其他 `type` → 图集：正面 `CardAtlas.face(type, suit, rank)`，背面 `CardAtlas.back(type)`；图集缺失时回退旧素材。
- `CardView._refresh()` 同时刷新正面与背面纹理（切换预览类型后重建渲染即可生效）。

## 6. 开发者面板

- 在现有面板标题/抢牌调试之后，新增"卡牌皮肤"分组（3 列网格）：**原始 / 普通 / 石头 / 纸牌 / 玻璃** 五个按钮。
- 当前 `CardAtlas.preview()` 对应按钮禁用（高亮）。
- 点击 → `CardAtlas.set_preview_type(t)` → `main._show_toast(...)` → `main._render_game_if_active()`（GAME_OVER 时不打扰结算棋盘，符合 B26 约定）。

## 7. 测试与验证

`tests/verify_card_skin.gd`（headless，不启 GUI，35/35）：
1. `CardAtlas.preview()` 默认 `original`。
2. 图集为 4× 高清版：每格 220×308，图集 3080×4928。
3. 正脸 region（`rect(col,row)` 由 `CELL_W/CELL_H` 计算）：
   - `face("normal","♥","2")` == col0,row0；`face("normal","♥","A")` == col12,row0
   - `face("stone","♣","K")` == col11,row7；`face("paper","♦","7")` == col5,row10；`face("glass","♠","J")` == col9,row13
4. 卡背 region：`back("normal")`=col13,row0 / `stone`=row4 / `paper`=row8 / `glass`=row12。
5. Joker：红 `normal`=row2；黑 `normal`=row3；黑 `stone`/`paper` **回退红**(row6/row10)；黑 `glass`=row15。
6. 未知 type 回退 normal；未知 suit/rank 不崩；`set_preview_type` 无效值回退 `original`。
7. 默认皮肤 `original`：`CardView` 正/背面取旧素材（`texture.resource_path` 为 `assets/Cards/back07.png`、`hearts_07.png`、`Joker1.png`）。
8. 切到图集皮肤后：`CardView` 正/背面为 `AtlasTexture` 且 region 随 type 变化；`card_data["type"]` 可显式覆盖（含 `original`）。

**回归**：`tools/run_all_tests.sh`（或 `--quick`）。
**导入**：首次需触发 Godot 导入图集 PNG（生成 `.import` 与 `.godot/imported`），否则 headless 下 `load()` 返回 null；导入后跑 `verify_card_skin`（含图集尺寸断言）确认。

## 8. 边界与不做

- 不做玩法属性（type 不进 `game_state`/快照/协议）。
- 不做按花色/逐张切换（仅全局单选预览）。
- 不做图片切分工具；region 常量写死在 `CardAtlas`。
- 卡牌显示尺寸统一改为图集原生比例 **5:7（55:77）**（`CARD_SELF_SIZE` 64×90、`CARD_PILE_SIZE` 76×107、`CARD_BIG_SIZE` 110×154、`player_area.card_size` 64×90、商店卡位 94×132），避免非等比缩放/letterbox；尺寸与原来接近。
- **模糊修复**：图集 1× 每卡仅 55×77 像素，被放大（手牌 64/55≈1.16×、大牌 110/55=2×，HiDPI/窗口缩放再 ×2）→ 糊。解决：改用 **4× 高清图集**（每卡 220×308），卡牌显示尺寸小于格子 → 缩小采样、清晰。注意 `TextureRect` 一直用 `KEEP_ASPECT_CENTERED`（等比、无变形），故问题只是像素不足而非拉伸变形。
