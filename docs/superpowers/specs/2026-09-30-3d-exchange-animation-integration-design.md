# KONG 3D 换牌动画接入对局 设计 v1

> **前置**：沙盒原型 `CardFly`/`CardFlyMath`/`CardFlyConfig`（见 `2026-09-30-3d-exchange-animation-sandbox-design.md`）已完成。本设计把它**接入对局 3D 视图**：3D 模式下播放服务器 `card_exchange_animated` 的全部 6 种飞牌。**2D 游戏逻辑零改动**（`CardAnimator`/`game_view.gd`/`card_view.gd`/`reveal_controller.gd` 及 `main.gd` 的 2D 分支逐字不动）；不改规则/协议/快照。分支 `feature/card-animation`。

## 1. 目标与非目标

**目标**

1. 3D 模式下，`GameState.card_exchange_animated` 的 6 种 kind 播放与 2D 视觉对应的飞牌动画（`card_fly.gd`）。
2. 飞牌跨 `table3d_view.render()` 的全量重建保持：在途槽位隐藏、落地后用最新状态重渲染。
3. 隐私与 2D 一致：`slap_penalty`/`slap_gift` 事件不含牌面 → 显示背面；其余按事件牌面/来源视角显示。
4. 编排放 `table3d_view` 内（其拥有 `_card_blocks`、跨 render 状态 `_reveals`/`_hover_slot` 与渲染生命周期）。

**非目标**

- 不改 2D 逻辑：`animator.handle_exchange` 分支保持原样。
- 不改规则 / 协议 / 快照 / `scripts/core/*` / `scripts/net/*`。
- 不做 3D 商店/结算/遗物栏、不做 3D 菜单。
- 不新增 2D 侧能力（如 Q 交换动画——本就未做）。

## 2. 落点与职责

**`main.gd`（仅加 3D 分支，2D 分支逐字不动）**

```gdscript
GameState.card_exchange_animated.connect(func(data: Dictionary):
	if _table3d_active:
		if table3d != null and is_instance_valid(table3d):
			table3d.animate_exchange(data)
	else:
		animator.handle_exchange(data))
```

**`table3d_view.gd`（新增对局飞牌能力，复用 `CardFly`）**

新增状态（跨 `render()` 重建保持，模式同 `_reveals`）：

| 字段 | 含义 |
| --- | --- |
| `_anim_slots: Dictionary` | `"seat_slot" -> true`：在途动画槽位；`render()` 对这些槽**跳过建卡**（等价 2D `mark_anim_slot`） |
| `_flyers: Array` | 在途 `CardFly`（挂 `table3d` 根本节点，不在 `HandAnchor` 下，重建不受影响） |
| `_discard_hold: bool` | 飞向弃牌堆期间隐藏弃牌顶（等价 2D `_discard_anim_lock`），落地后显示 |
| `_last_state: Dictionary` | 最近一次 `render` 的 state（落地后重渲染用） |
| `_last_actionable: Callable` | 最近一次 `render` 的 actionable |
| `_seat_node_by_id: Dictionary` | `seat -> Node3D`（`render` 时登记；槽位未渲染时按布局算世界变换） |
| `_slot_cards: Dictionary` | `{seat: {slot: card}}`（`render` 时登记；供 `slap_gift` 自身视角取牌面） |
| `_deck_node` / `_discard_node` / `_pending_node` | `_bind()` 登记 `Center/Deck`/`DiscardTop`/`Pending` 节点 |

新增方法：

```gdscript
## 播放一条 card_exchange_animated 事件（3D 分支入口）。
func animate_exchange(data: Dictionary) -> void

## 世界变换/面/牌面查询（槽位未渲染时按 Table3dLayout 布局计算）。
func slot_xform(seat_id: int, slot: int) -> Transform3D
func center_xform(kind: String) -> Transform3D      # "deck" | "discard" | "pending"
func slot_face_up(seat_id: int, slot: int) -> bool  # 用 CardBlock.has_face_texture()
func slot_card(seat_id: int, slot: int) -> Dictionary
```

私有编排与生命周期：

```gdscript
func _spawn_fly(from: Transform3D, to: Transform3D, data: Dictionary,
		start_up: bool, end_up: bool, on_land := Callable()) -> CardFly
func _mark_anim_slot(seat: int, slot: int) -> void
func _unmark_anim_slot(seat: int, slot: int) -> void
func _has_anim_slot(seat: int, slot: int) -> bool
func _refresh() -> void        # 用 _last_state/_last_actionable 重渲染（若存在）
```

## 3. 渲染与生命周期

**`render(state, actionable)`** 改动（仅 3D 侧新增逻辑，不改变既有输出）：

- 开头记录 `_last_state = state`、`_last_actionable = actionable`。
- 遍历座位时登记 `_seat_node_by_id[seat] = node`、`_slot_cards[seat][i] = slot.get("card", {})`。
- `_render_seat` 对 `_has_anim_slot(seat, i)` 的槽**跳过建卡**（与"空槽不渲染"同位置）。
- 弃牌顶：`_discard_hold` 为真时 `_discard_block.visible = false` 且 `set_pick_enabled(false)`；否则按现状 `setup`/显示/可拾取。

**生命周期**：事件先于快照到达（服务器在 `_broadcast_state` 前广播）→ 用旧布局取源/目标变换；随后快照 `render` 重建，被标记槽位保持隐藏；`CardFly.finished` → 执行该次飞行的 `on_land`（更新标记/`_discard_hold`）→ `_refresh()` 用最新状态重渲染。

**多段飞行**（`replace` 两段 / `swap` 两段）：`on_land` 只更新**该段负责**的标记，`_refresh()` 每段落地都调用，未落地的段其槽位仍被标记 → 保持隐藏（与 2D 每段落位各自刷新一致，避免先落位段被拖住/闪回）。

**`set_active(false)`（切回 2D / 收起 3D）**：释放所有 `_flyers`、清 `_anim_slots`、`_discard_hold=false`（防残留隐藏槽）。

## 4. 6 种 kind 映射（`viewer = _viewer`）

| kind | 飞牌段（源 → 目标） | 起 → 终面 | 标记/锁 |
| --- | --- | --- | --- |
| `replace` | ① 旧槽 → 弃牌顶（`old_data`）<br>② 大牌(pending) → 旧槽（`big_data`） | ① 槽当前面 → 正面<br>② `(viewer==actor)` → 槽当前面 | 标记 `(actor,slot)` 至②落地；`_discard_hold` 至①落地 |
| `swap` | a槽 → b槽（`a_data`）、b槽 → a槽（`b_data`） | 各自槽当前面 → 对端槽当前面 | 标记 a/b 两槽，**两段全落地**后解除（计数） |
| `discard` | pending → 弃牌顶（`big_data`） | `(viewer==actor)` → 正面 | `_discard_hold` 至落地 |
| `slap_penalty` | 抽牌堆 → 目标槽（`{}` 无牌面） | 背 → 背 | 标记目标槽至落地 |
| `slap_resolved` | 目标槽 → 弃牌顶（`card`） | 正面 → 正面 | 标记目标槽；`_discard_hold` 至落地 |
| `slap_gift` | actor 的 own_slot → 对方 target_slot（`viewer==actor` 时带自身牌面，否则 `{}`） | 面向上 → 面向上（`viewer==actor` 为正面，否则背面） | 标记两槽至落地 |

- 起点面/终点面：`slot_face_up` 读源/目标槽当前显示面；大牌(deck/pending)来源的起点面用 `(viewer==actor)`（与 2D `big_start_face_up` 一致）。
- 隐私：`slap_penalty`/`slap_gift` 事件无牌面（协议 4.7）→ 传 `{}` → 背面；`slap_gift` 仅 `viewer==actor` 时从 `_slot_cards` 取自身牌面（与 2D 同策略）。
- `replace` 的②与 `discard` 起点在 pending；飞行开始时置 `_pending_block.visible=false`（避免与飞牌重叠；随后快照亦清空 pending）。

## 5. 边界与风险

- **槽位未渲染**（`slap_penalty` 的第 5+ 张、事件先于快照）：`slot_xform` 按 `Table3dLayout.slot_grid_pos` 计算，无需 pending 队列；标记保证快照到达后该槽仍隐藏，落地后解除。
- **飞行中再次快照**：`_last_state` 更新，`_flyers` 不受影响；落地后按最新状态重渲染。
- **飞行中切回 2D**：`set_active(false)` 释放飞牌与标记；再切回 3D 由状态重渲染。
- **无状态/未绑定**：`animate_exchange` 开头 `if not _bound or _last_state.is_empty(): return`。
- **GDScript 陷阱**：`smoothstep` 等内建同名函数需限定（`CardFlyMath.*`）。
- **性能**：单事件最多 2 张 `CardFly`，复用 `CardBlock`，无虞。

## 6. 测试与验收

新增 `tests/verify_table3d_exchange.gd` + `.tscn`（实例化真实 `scenes/ui/table3d.tscn`，`render(state)` 后驱使 `animate_exchange`，断言节点/标记/落地恢复；不启动 GUI）：

- **标记与跳过**：`render` 后调用某 kind，`_has_anim_slot` 为真且对应槽位在 `HandAnchor` 子节点中不存在（被跳过）；飞行结束后标记清除、槽位恢复。
- **飞牌生成**：`replace`/`swap` 生成 2 张 `CardFly`；`discard`/`slap_*` 生成 1 张；全部为 `CardFly` 且 `is_flying()`。
- **落地恢复**：等待超过"最快速度下最长可能时长"（`最长距离 / speed + 余量`，测试用固定 2.5s）后，`_flyers` 清空、`_discard_hold=false`、`_anim_slots` 空；`render` 恢复显示。
- **隐私**：`slap_penalty`/`slap_gift`（非 actor）飞牌的 `card_block().label_text()` 为空；`viewer==actor` 的 `slap_gift` 带牌面。
- **`slot_xform` 未渲染槽**：对 `slot=4`（不存在的槽）返回的 `origin` 满足布局公式（非 `IDENTITY`）。
- **`set_active(false)`**：清空飞牌与标记。
- **回归**：`verify_table3d`/`verify_table3d_interaction`/`verify_card_fly` 全绿；`tools/run_all_tests.sh` 全量全绿；2D 相关测试零改动。

**验收闸门**：新测试全绿；全量回归全绿；`main.gd` 2D 分支与 2D 卡牌文件零改动（`git diff` 确认）。

## 7. 文件清单

| 文件 | 变更 |
| --- | --- |
| `scripts/ui/table3d_view.gd` | 新增飞牌编排 + 跨 render 标记/查询方法 + `render` 登记与跳过逻辑 + `set_active` 清理 |
| `scripts/ui/main.gd` | `card_exchange_animated` 处理器加 3D 分支（2D 分支逐字不动） |
| `tests/verify_table3d_exchange.gd` + `.tscn`（新） | 接入测试 |
| `tools/run_all_tests.sh` | 纳入 `verify_table3d_exchange` |

**不改**：`card_animator.gd`、`game_view.gd`、`card_view.gd`、`reveal_controller.gd`、`card_block.gd`、`card_fly*.gd`、`scripts/core/*`、`scripts/net/*`、`scenes/ui/table3d.tscn`、2D 相关与现有测试。

## 8. 参数

沿用 `CardFlyConfig` 现有默认（`speed=3.0`、`duration_min=0.15`、`arc_height=0.35`、`flip_start=0.35`、`flip_end=0.65`）。接入后如手感需调，只改 `CardFlyConfig`。
