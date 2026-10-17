# KONG 3D 全息看板「按键映射」页签 + 页签可点击（部分穿透）设计 v1

> **目的**：在 3D 全息看板（`ManualPanel`）上新增第三页签「按键」，列出当前**界面/展示类**按键映射与作用，并支持**重新绑定**（冲突自动交换、保留键拒绝），底部「保存」经**确认浮层**后持久化到本机当前用户。
> **同时**：手册/Stats/按键页打开时，看板**不再完全接管点击**——只有页签、键行、保存/确认按钮等**可交互控件**接收点击，其余区域**穿透到牌桌**，从而可以一边看手册/页签一边点牌桌卡牌（需求 2 的"不完全接管"）。
> **纯客户端展示层**：不改规则 / 协议 / 快照 / `scripts/core/*` 的既有子系统 / `scripts/net/*`；按键映射只影响本机输入，不联网、不下发给其他玩家。
> **分支**：`agent/feature-uiboard2`（从当前基线拉出）。

## 1. 目标与非目标

**目标**

1. `ManualPanel` 新增第三页签「按键」，与手册/Tab、Stats/S 并列；默认用**新键 `K`** 打开/关闭。
2. 该页列出所有**可重绑的界面/展示类动作**及其当前绑定键与作用说明。
3. 点击某行的键 → 进入"按键捕获"→ 按下新键即更新（**待保存**）；与已占用键冲突时**自动交换**；命中**保留键**时拒绝并提示。
4. 页底部「保存」按钮：无改动时禁用；点击弹出**页内确认浮层**；确认后写入 `user://` 并即时生效。
5. 持久化**只对当前本机用户生效**（不联网、不进快照）；为将来"绑定账户"预留 `profile` 维度（按账户分文件）。
6. 手册/Stats/按键页打开时，**页签与可交互控件可点击**，**其余区域穿透到牌桌**（可继续操作卡牌）。
7. 关闭页签时**丢弃**未保存改动（不做未保存提醒）。

**非目标**

- 不改规则 / 协议 / 快照 / `scripts/core` 既有子系统 / `scripts/net/*`。
- 不改游戏关键操作键（空格 STOP、Enter/Esc 确认等）：它们列为**保留键，不可绑定**。
- 不纳入开发者键（F12 / T / O）与 3D 调参键。
- 不做原生 `Window` 弹窗（`ConfirmationDialog` 在 SubViewport 内渲染/点击不可靠），确认用**页内浮层**。
- 不做账户系统本身（仅在存储上预留 `profile` 键）。
- 不重绑 2D 界面的按键（本页签与捕获均**仅 3D 生效**，与现有 Tab/S 一致）。

## 2. 架构与组件

采用「纯函数模型 + 薄存储壳 + 独立页内容控件 + 显式可交互标记」的松耦合结构。

### 2.1 `scripts/core/keybind_model.gd`（新增，`class_name KeybindModel extends RefCounted`）

纯函数，headless 可测，不依赖节点/网络/`InputMap`。

```
# 有序动作表（供 UI 展示：id / 显示名 / 作用说明 / 默认键）
const ACTIONS := [
  {"id": "kb_manual",   "label": "手册",     "desc": "开/关 手册页",              "default": KEY_TAB},
  {"id": "kb_stats",    "label": "Stats",    "desc": "开/关 弃牌堆 Stats 页",     "default": KEY_S},
  {"id": "kb_keymap",   "label": "按键映射", "desc": "开/关 按键映射页",          "default": KEY_K},
  {"id": "kb_talk",     "label": "说话",     "desc": "按住/切换 说话（嘴开合）",   "default": KEY_M},
  {"id": "kb_zoom",     "label": "放大",     "desc": "按住 拉近视场（放大）",      "default": KEY_META},   # 同时接受 KEY_ALT
  {"id": "kb_toggle3d", "label": "切换 3D",  "desc": "在 2D 与 3D 桌面间切换",    "default": KEY_V},
]
# 保留键：不可被界面动作绑定（游戏操作 / 系统）
const RESERVED := [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE, KEY_F10]

static func defaults() -> Dictionary                 # {id: keycode}
static func action_ids() -> Array                    # 有序 id 列表（供 UI）
static func action_def(id) -> Dictionary             # 单个动作定义（label/desc/default）
static func resolve(map, keycode) -> String          # keycode → id；无匹配返回 ""
static func rebind(map, id, keycode) -> Dictionary
    # 返回 {ok, error, map, swapped}：
    #   - keycode in RESERVED  → {ok:false, error:"reserved"}
    #   - 未知 id              → {ok:false, error:"unknown_action"}
    #   - 该 key 已属其他动作 B → 自动交换：B 得到 id 的旧键；swapped = B
    #   - 成功                 → {ok:true, error:"", map:新map, swapped:""|B}
    #   map 为**新字典**（不就地修改入参）
static func to_dict(map) -> Dictionary               # {id: keycode(int)}，供存档
static func from_dict(d) -> Dictionary               # 校验：未知 id 丢弃、非法/保留值回退默认、缺项补默认
```

- 动作集**只含界面/展示类键**（见 §1 目标 2）。
- `kb_zoom` 默认含"左右修饰键"语义：实现层（main）对 `KEY_META` / `KEY_ALT` 都判定（沿用现状）。
- `resolve` 只映射**普通键码**（不做组合键）；本项目现有交互均是 plain keycode，够用。

### 2.2 `scripts/core/keybind_store.gd`（新增，`class_name KeybindStore extends RefCounted`）

薄壳：持有当前 map + `ConfigFile` 读写；**无节点依赖**，可在测试里直接构造。

```
const PATH := "user://keybinds.cfg"
const SECTION := "keybinds"
const VERSION := 1

var map: Dictionary = {}

func _init() -> void                 # map = defaults()（加载前的安全初值）
func load() -> void                  # 读文件；缺文件/解析失败/版本不符 → 回退默认
func save() -> void                  # 写 map + version（+ 预留 profile 键）
func key_of(id) -> int               # 当前绑定键
func action_for(keycode) -> String   # 等价 KeybindModel.resolve(map, keycode)
func apply(new_map) -> void          # 替换 map（**不落盘**；由调用方决定何时 save）
func reset_to_defaults() -> void     # 测试/未来"恢复默认"用（v1 不暴露 UI）
```

- 存档格式：`[keybinds]` 段，`<id> = <keycode:int>`；`version = 1`；预留 `profile = ""`（未来按账户写入 profile_id 或改用 `user://keybinds-<profile_id>.cfg`）。
- **只读本机当前用户**：`user://` 天然是"当前 OS 用户 + 当前应用数据目录"，不含任何网络下发。

### 2.3 `scripts/ui/keymap_board.gd`（新增，`class_name KeymapBoard extends Control`）

第三页内容控件（仿 `StatsBoard` 的独立 Control，由 `ManualPanel` 承载）。

```
signal save_requested(new_map: Dictionary)   # 点「保存」→ 弹确认（由面板处理）
signal rebind_requested(id: String)          # 点某行键 → 请求进入捕获

var _pending: Dictionary          # 待保存 map（打开时 = store.map 的副本）
var _capturing := ""              # 正在捕获的动作 id（"" = 无）
var _labels := {}                 # id -> 键 chip 的 Label

func setup(current_map: Dictionary, reserved: Array) -> void  # 建行：label+desc+键chip(meta 可交互)
func begin_capture(id: String) -> void        # 置 _capturing，chip 显示「按键中…」
func capture_key(keycode: int) -> void        # 调 KeybindModel.rebind；成功则刷新两行 chip；_capturing=""
func cancel_capture() -> void                 # Esc 取消捕获
func capturing() -> String
func pending_map() -> Dictionary
func has_changes() -> bool                    # _pending != store 原始
func set_save_enabled(on: bool) -> void
func refresh_chips() -> void
# 测试访问器：row_count() / chip_text(id) / capture_label(id)
```

- 每行：`标签(局部说明)` + `作用说明` + `键 chip`（`PanelContainer`，复用 `KeyHintPanel.make_chip` 视觉）。
- 可交互控件（键 chip、保存按钮、确认浮层的按钮）统一 `set_meta("board_interactive", true)`（见 §5）。
- 纯展示 + 本地状态；真正的落盘由 `ManualPanel`/`main` 驱动。

### 2.4 `scripts/ui/manual_panel.gd`（改）

- 加 `const TAB_KEYS := 2`；`_build_tabs()` 增加第三个页签按钮「按键」（同样 `focus_mode = NONE`）。
- `_build_keymap()`：实例化 `KeymapBoard`，加入 `VBox`，默认隐藏。
- `set_tab(index)`：支持 `0/1/2`；`_grid.visible = (tab==MANUAL)`、`_stats.visible=(tab==STATS)`、`_keymap.visible=(tab==KEYS)`；标题相应改为「按键映射」。
- 新增**保存确认浮层**：`_build_confirm()` 建一个覆盖 `Center/Panel` 的 `Control`（半透明遮罩 + 居中 `PanelContainer`：「确认保存当前按键映射？」+「确认」/「取消」），默认隐藏；两个按钮与遮罩 meta 可交互。
- 对外 API（供 main 与新测试）：
  ```
  func setup_keymap(current_map, reserved) -> void
  func keymap_board() -> KeymapBoard
  func open_confirm() -> void
  func confirm_visible() -> bool
  func on_confirm_save() -> void     # 发 save_confirmed(new_map)
  func on_confirm_cancel() -> void
  signal save_confirmed(new_map: Dictionary)
  ```
- 页签按钮全部打 `board_interactive` 标记（§5）。

### 2.5 `scripts/ui/board3d.gd`（改）

新增「该点是否落在可交互控件上」查询（用于部分穿透）：

```
## 该视口像素坐标是否位于某个带 meta("board_interactive") 的控件矩形内。
func interactive_at(coord: Vector2i) -> bool:
    _prune_panels()
    for panel in _panels:
        if _interactive_hit(panel, Vector2(coord)):
            return true
    return false

func _interactive_hit(node: Node, p: Vector2) -> bool:
    if node is Control:
        var c := node as Control
        if c.visible and bool(c.get_meta("board_interactive", false)) \
                and c.get_global_rect().has_point(p):
            return true
    for child in node.get_children():
        if _interactive_hit(child, p):
            return true
    return false
```

- 仅新增方法，不改现有挂载/显隐/拾取逻辑。

### 2.6 `scripts/ui/main.gd`（改）

- 新增字段 `var keybinds := KeybindStore.new()`；`_ready()`/初始化时 `keybinds.load()`。
- 把 `_input`（3D 分支）与 `_unhandled_input` 中**界面/展示类**硬编码 `KEY_*` 判定改为 `keybinds.action_for(event.keycode)`：
  - `KEY_TAB → "kb_manual"`、`KEY_S → "kb_stats"`、`KEY_K → "kb_keymap"`、`KEY_M → "kb_talk"`、`KEY_V → "kb_toggle3d"`、放大 `KEY_META/KEY_ALT → "kb_zoom"`。
  - **保留键**（空格 / Enter / Esc / F10）仍按原硬编码处理，不经 `keybinds`。
- `KEY_K`：3D 下 `_toggle_manual(ManualPanel.TAB_KEYS)`。
- **按键捕获**：`_input` 开头判断 `manual_panel.capturing()`；若非空则：
  - `Esc` → `cancel_capture()`；否则任意 keydown → `keymap_board.capture_key(keycode)`；一律 `set_input_as_handled()` 并 `return`（捕获期间不触发游戏/牌桌）。
- **保存确认**：`ManualPanel.save_confirmed(new_map)` 连接 → `keybinds.apply(new_map)` + `keybinds.save()` + toast「按键已保存」+ `keymap_board` 复位（`_pending` 重设、保存按钮禁用）。
- **部分穿透**（需求 2，见 §5）：改 `_board_hit()`：
  ```
  for host in [board3d, hint3d]:
      if host 可见:
          var c := host.hit_viewport_coord(cam)
          if c.x >= 0:
              # 手册页：仅可交互控件处接管，其余穿透到牌桌
              if host == board3d and _manual_transparent() and not board3d.interactive_at(c):
                  continue
              return {"host": host, "coord": c}
  ```
  `_board_has_panel()` / `_click_route()` 逻辑**不变**（手册挂载时 `_board_has_panel()` 仍为 false → 非交互处走 "table"）。
- `_process` 悬停：`_board_has_panel()` 为 false 时不再提前 `return`，使手册打开时**牌桌悬停照常**（现有分支已满足：`on_board` 为 true 才吞并，否则落到 `table3d.update_hover()`）。
- 打开手册时 `manual_panel.setup_keymap(keybinds.map, KeybindModel.RESERVED)`。

## 3. 按键捕获与自动交换行为

- 点某行 chip：`ManualPanel` → `KeymapBoard.begin_capture(id)`，该行显示「按键中…」（其余行不变）。
- main 捕获下一个 keydown → `capture_key(keycode)`：
  1. `KeybindModel.rebind(_pending, id, keycode)`。
  2. `ok == false`（`reserved`）→ 该行红字提示「保留键，不可绑定」，**留在捕获态**（可再按别的键或 Esc）。
  3. `ok == true`：更新 `_pending`；若 `swapped != ""`，**交换双方 chip 一并刷新**（视觉上"两个键对调"）；结束捕获；保存按钮按 `has_changes()` 启用。
- Esc 取消捕获：不改 `_pending`，chip 复原。
- 捕获**仅作用于待保存副本**，`keybinds.map` 直到确认保存才被替换。

## 4. 保存与确认浮层

- 「保存」按钮：`has_changes()` 为真才启用；点击 → `ManualPanel.open_confirm()` 显示页内浮层。
- 浮层：半透明遮罩（`board_interactive`）+ 居中 `PanelContainer`「确认保存当前按键映射？」+「确认 / 取消」。
  - 「取消」→ 关闭浮层，保留 `_pending`（可继续改或再保存）。
  - 「确认」→ `save_confirmed(_pending)` → main 落盘 + 生效 + toast；关闭浮层；`KeymapBoard` 重设基线（保存按钮禁用）。
- 关闭页签（Tab/S/K/Esc）→ `ManualPanel` 被 `_close_manual()` 释放 → `_pending` 随之丢弃（未保存改动不保留，符合决定）。
- 复用现有 toast：`main._show_toast("按键已保存")`。

## 5. 页签点击 + 部分穿透（需求 2）

**问题根因**：手册打开时 `main._manual_transparent()` 为真 → `_board_hit()` **整块跳过** `board3d` → 页签按钮收不到点击（表现为"点不了页签"）。

**方案（不做完全接管）**：

1. UI 侧给**可交互控件**打标记：`set_meta("board_interactive", true)`（页签按钮、键 chip、保存按钮、确认浮层按钮/遮罩）。标签、牌面、排版容器**不标**。
2. `Board3d.interactive_at(coord)`：命中任一标记控件的矩形 → true（§2.5）。
3. `_board_hit()`：手册页只在 `interactive_at(c)` 命中时返回 `board3d`；否则**穿透**（落回牌桌）。
4. `_board_has_panel()` / `_click_route()` 不变：
   - 手册挂载（`_manual_transparent()` 真）→ `_board_has_panel()` 为 false → 非交互处点击走 "table"；
   - 模态板（结算/商店/Joker）仍完全接管（`_board_has_panel()` 为 true）。
5. `_process` 悬停：
   - 手册页在交互控件上 → 板内 hover + 准星变色；
   - 手册页在非交互处 → **牌桌悬停照常**（可点卡牌）；
   - 模态板打开 → 仍 `clear_hover()` 吞并牌桌（现状不变）。

**效果**：可一边开着手册/Stats/按键页，一边用准星点牌桌卡牌；只有页签和按钮区域会"吃掉"点击。

## 6. 生命周期与接线

```
main 初始化: keybinds.load()
3D 激活:
  _ensure_board() → hint3d
  打开手册(Tab/S/K) → _toggle_manual(tab) → _open_manual(tab)
     └─ manual_panel.setup_keymap(keybinds.map, KeybindModel.RESERVED)   # 打开时快照
  点键行 → begin_capture → main._input 捕获 → capture_key → rebind(_pending)
  点保存 → open_confirm → 确认 → save_confirmed(map) → keybinds.apply+save+toast
  关闭页签/关手册 → _close_manual() → queue_free（_pending 丢弃）
切回 2D: _set_table3d(false) → _close_manual()（现状）
```

- `keybinds.map` 变更后**即时生效**：`_input` 每次都用 `action_for` 查表，无需重启。
- `KeybindStore.load()` 失败/缺文件 → 默认键，无副作用。

## 7. 测试与验收

**新增 `tests/verify_keybind.tscn` / `.gd`（headless）**

- `KeybindModel`：`defaults()` 含 6 个动作；`resolve` 正/反查（含无匹配返回 ""）；`rebind` 成功/自动交换（A↔B）/保留键拒绝（`error=="reserved"`）/未知 id 拒绝；`to_dict↔from_dict` 往返；`from_dict` 对未知 id、保留值、缺失项的回退。
- `KeybindStore`：缺文件 → 默认；`save()` 后重新 `load()` 读到同 map；`action_for`/`key_of` 正确；`apply` 不落盘（下次 load 不变）。
- `KeymapBoard`：建行数 = 动作数；`capture_key` 更新 chip 且 `swapping` 时两行联动；`has_changes` 正确；保存启用/禁用。
- `ManualPanel`：第三页签存在、`set_tab(2)` 显示 `KeymapBoard` 并隐藏 grid/stats；`open_confirm` 后 `confirm_visible()` 为真；`on_confirm_save` 发 `save_confirmed`；标签按钮与键 chip 带 `board_interactive` meta。

**扩展 `tests/verify_board3d.tscn` / `.gd`**

- `interactive_at`：命中带 meta 的控件矩形 → true；空白/无 meta 控件 → false。

**扩展 `tests/verify_manual.tscn` / `.gd`**

- 三页签存在与互斥显示；Tab/S/K 打开对应页（`_toggle_manual`）。

**回归**

- `verify_manual` / `verify_board3d` / `verify_hint_hud` / `verify_table3d_exchange` / `verify_table3d` / `verify_table3d_interaction` 全绿。
- `tools/run_all_tests.sh --quick` 与全量（网络注入可选）全绿。
- `git diff` 确认 `scripts/core` 既有子系统与 `scripts/net/*` 零改动；2D 相关文件（`game_view.gd` / `card_view.gd` / `card_animator.gd` / `reveal_controller.gd`）零改动。

**验收闸门**

1. 新增断言全绿；
2. 上述回归全绿；
3. 3D 内：点页签可切换；点键行可捕获；保存弹确认并落盘（重启后仍生效）；手册打开时仍能点牌桌卡牌。

## 8. 文件清单

| 文件 | 变更 |
| --- | --- |
| `scripts/core/keybind_model.gd` | 新增：纯函数动作表 / resolve / rebind（自动交换）/ to-from dict |
| `scripts/core/keybind_store.gd` | 新增：`user://keybinds.cfg` 读写薄壳（version + 预留 profile） |
| `scripts/ui/keymap_board.gd` | 新增：第三页内容（键行 + 捕获态 + 保存按钮） |
| `scripts/ui/manual_panel.gd` | 改：第三页签、`KeymapBoard`、保存确认浮层、`setup_keymap` 等 API |
| `scripts/ui/board3d.gd` | 改：新增 `interactive_at` / `_interactive_hit` |
| `scripts/ui/main.gd` | 改：`keybinds` 接线、界面键改走 `action_for`、K 打开按键页、捕获转发、保存落盘、`_board_hit` 部分穿透 |
| `tests/verify_keybind.tscn` / `.gd` | 新增 |
| `tests/verify_board3d.*` / `tests/verify_manual.*` | 扩展 |
| `docs/AI_AGENT_交接说明.md` / `docs/功能实现文档.md` | 补一句「按键映射页签 + 页签点击/部分穿透」 |

**不改**：`scripts/core/*` 既有子系统（`game_state.gd`/`hidden_info.gd`/`score_system.gd`/`slap_system.gd` 等）、`scripts/net/*`、`scenes/ui/table3d.tscn`、`game_view.gd`、`card_view.gd`、`card_animator.gd`、`reveal_controller.gd`、`key_hint_panel.gd`（键 chip 直接复用其静态 `make_chip`，无需改动）。

## 9. 边界与未来（账户绑定）

- **v1（本次）**：`user://keybinds.cfg`，仅本机当前用户；`profile` 键预留为空。
- **v2（未来）**：接入账户后，把存储路径改为 `user://keybinds-<profile_id>.cfg`（或把 `profile` 段写入值），
  - `KeybindStore` 只改"路径/profile 从哪来"，`KeybindModel` / UI / `main` 接线**零改动**；
  - 切换账户时重新 `load()` 即可。
- 不做：云同步、跨设备、服务器下发按键。

## 10. 参数（初值，可调）

| 常量 | 初值 | 说明 |
| --- | --- | --- |
| `TAB_MANUAL / TAB_STATS / TAB_KEYS` | `0 / 1 / 2` | 页签索引 |
| `kb_manual / kb_stats / kb_keymap` | Tab / S / K | 三页开关默认键 |
| `kb_talk / kb_zoom / kb_toggle3d` | M / Command·Alt / V | 说话 / 放大 / 切 3D |
| `RESERVED` | 空格·Enter·KP_Enter·Esc·F10 | 保留键（不可绑定） |
| `PATH / SECTION / VERSION` | `user://keybinds.cfg` / `keybinds` / `1` | 存储 |
| `CAPTURE_HINT_TEXT` | 「按键中…」 | 捕获态 chip 文案 |
| `RESERVED_ERROR_TEXT` | 「保留键，不可绑定」 | 拒绝提示 |
| `CONFIRM_TEXT` | 「确认保存当前按键映射？」 | 确认浮层文案 |
