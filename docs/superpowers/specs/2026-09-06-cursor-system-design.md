# 光标系统设计（方案 A 混合式 · 修正版）

> 日期：2026-09-06 · 状态：已批准（修正版：无原生箭头，默认=open_hand）
> **合并状态：未合并到 main**（代码与文档均在 `feature/cursor` 分支，main 不含本系统；后续如需合入请走 PR）
> 说明：本设计只覆盖「静态态 + 通用 hover + flip 触发钩子」。flip 的 AnimatedSprite2D 动画（SpriteFrames/素材）由开发者自行处理。

## 总开关（Settings.cursor.enabled，默认关闭）

- 光标系统**默认关闭**：此时用原生 OS 箭头，不注册任何自定义光标、不运行状态机、不播放 flip。
- 开关在设置菜单（`settings_menu.gd` 的 CheckButton「自定义光标」），读写 `Settings.setting_changed`，
  cursor.gd 监听即时启停。ARROW shape 从不注册自定义纹理，关闭时 `set_default_cursor_shape(ARROW)` 即回原生。

## 目标与状态语义

| 状态 | 触发 | 渲染方式 |
| --- | --- | --- |
| `pointer`（默认，无原生箭头） | 全局默认光标 | OS 光标 `POINTING_HAND` shape + `cursor_open_hand_64px.png` |
| `peek` | 处于 peek 能力（`action_mode` ∈ `peek_own/peek_other/queen_target`）且悬停可点牌、未按下 | OS 光标 `CROSS` shape + `cursor_peek_64px.png` |
| `flip` | ① `peek` 状态下按住鼠标左键（hold） ② 贴牌窗口（`slap_open` && TURN_DRAW）悬停**任意卡牌**（自己或他人） | 场景内 AnimatedSprite2D（唯一动画态，`MOUSE_MODE_HIDDEN`） |

## 架构

```
scenes/ui/cursor.tscn            # 新：挂 main.tscn 根，CanvasLayer layer=100（高于所有 z）
  └─ AnimatedSprite2D            # 只承载 flip 动画；开发者配置 SpriteFrames，默认隐藏
scripts/ui/cursor.gd             # 新：哑渲染 + 通用 hover；不判断游戏规则
```

- cursor.gd 持有 `set_card_resolver(callable)` 钩子，卡牌语义由 game 层提供（game_view），
  实现与 GameState/main 零耦合。
- `_register_os_cursors`：open_hand 挂 `POINTING_HAND`、peek 挂 `CROSS`。ARROW 保持原生（关闭时切回）。
- `_ready` 断言初始状态（`_apply`）停掉 AnimatedSprite2D 的 `autoplay`——修复"启动即播放 flip 动画" bug。
- `_process` 每帧：`gui_get_hovered_control()` → 解析状态 → 应用。flip 期间每帧更新跟随位置。
- `_apply` 仅在状态切换时执行：进入 flip 隐藏 OS 光标（`MOUSE_MODE_HIDDEN`）并 `play("flip")`，
  退出恢复 `VISIBLE` + `stop()`。

### 状态解析（纯函数，headless 可测）

```
resolve_card_state(state, action_mode, actionable):
    slap_open && phase==TURN_DRAW → "flip"        # 任意卡牌（自己/他人）
    action_mode ∈ {peek_own,peek_other,queen_target} && actionable → "peek"
    else → "pointer"                              # 默认 open_hand

resolve_state(is_card_hovered, card_state):
    is_card_hovered → card_state
    else → "pointer"

apply_hold(state, mouse_down):
    state=="peek" && mouse_down → "flip"
    else → state
```

## 触发接线

- `main.tscn`：instance `cursor.tscn`（节点名 `Cursor`）。
- `main._ready`：`$Cursor.set_card_resolver(game_view.card_cursor_state)`。
- `game_view.gd` 新增 `card_cursor_state(card)`：经 `main._card_slots` 反查 `player_id/slot`，
  读 `main.latest_state`/`interaction.action_mode`/`_card_actionable`，调用 `CursorScript.resolve_card_state`。

## 热点（OS 光标 hotspot，可在编辑器调）

- `open_hand_hotspot` 默认 `(27, 32)`（掌心）
- `peek_hotspot` 默认 `(29, 32)`（眼睛中心）
- flip 位置 = 鼠标 + `flip_offset`（导出，默认 0；也可调 AnimatedSprite2D 自身 `offset`）

## 边界

- 无原生箭头状态（启用时）；`pointer`(open_hand) 是唯一默认。
- 关闭时回原生箭头（总开关默认关闭）。
- **不能 `set_custom_mouse_cursor(null, ...)` 清纹理**——macOS DisplayServer 报 `Parameter "imgrep" is null`。
  回原生箭头只需 `set_default_cursor_shape(ARROW)`（ARROW 从不注册自定义纹理）+ `warp_mouse` 强制刷新。
- flip 激活时光标移出窗口会冻结在边缘（`get_global_mouse_position` 钳制），可接受。
- 结算页/设置菜单覆盖层上：卡牌非可点 → pointer；按钮 → pointer（resolver 已注册但卡牌状态回落）。

## 测试

`tests/verify_cursor.tscn` + `.gd`：直接调用三个静态纯函数断言
（card 组合 / 按钮 / 空白 / hold 升级 / 任意卡牌贴牌 flip / 无原生箭头）。headless，不依赖 viewport。