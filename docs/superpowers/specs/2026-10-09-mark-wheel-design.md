# KONG Mark v2（轮盘选标 · 多图标 · 鼻子/波纹指针）设计 v1

> **目的**：把现有"按 D 直接放波纹标记"升级为**按住 D 出四扇区轮盘**选标：**上=眼睛 / 右=问号 / 下=数字 / 左=感叹号**；拖到扇区松 D 在**准星落点**放置对应 mark，**单点 D（未拖入扇区）不产生标记**。mark 的**指针**按放置者设置取**鼻子**（设置开）或**波纹**（设置关），两者都在落点上方**悬浮同一个图标**；mark 同步给所有玩家、**3 秒自动消失**。
> **纯客户端展示层**：不改规则/状态机/快照/`HiddenInfo`/`scripts/net/*`；`game_state.gd` 仅表现层 RPC/信号。

## 1. 目标与非目标

**目标**
1. **轮盘交互**：3D 下**按住 D** → 冻结当下准星落点（准星射线∩桌面平面 `y=TABLE_HEIGHT`；不在桌面内则不出轮盘），**释放鼠标**并显示光标，在**落点处**（准星=屏幕中心）显示四扇区轮盘（**中心中空**）。
   - 光标拖入扇区 → 高亮；**松开 D** → 在落点放置该 mark；松在中空/未选 → 不放置。松手后恢复鼠标捕获。
   - 轮盘中心=落点：光标释放即落在中空 → 单点天然无标记。
2. **扇区/图标**：`eye`(上) / `question`(右) / `number`(下) / `exclaim`(左)。
   - 数字扇区文案 = 当前弃牌堆顶 **rank**（任意花色；空弃牌堆 → `"-1"`）。
3. **Mark 数据**：`{seat, pos, style, icon, text}`；`style∈{ripple,nose}`（放置者设置决定，随事件同步）、`icon∈{eye,question,number,exclaim}`、`text` 仅 number 用。寿命 **3s**。
4. **渲染**（颜色按玩家 `players[].color`）：
   - `ripple`：两层波纹 + "∧"箭头（现有）+ 中心上方 **icon**。
   - `nose`：放置者角色**鼻子伸向 pos**（复用现有鼻子；本机第一人称鼻亦伸向 pos）+ pos 上方 **icon**，不出波纹/箭头。
   - icon：`eye` 用程序化贴图 `Sprite3D`；`question`/`exclaim`/`number` 用 `Label3D`（文本）；均 billboard、玩家色。
5. **鼻子归并**：鼻子不再由 `look.nose` 单独触发；改为**由 nose 风格 mark 驱动**（`look.nose` 字段保留兼容但停用、不再上报）。D 统一走轮盘。
6. 2D 不再产出标记；2D 逻辑零改动。

**非目标**
- 不改规则/状态机/快照字段/`HiddenInfo`/`scripts/net/*`。
- 不改 `scenes/ui/table3d.tscn`、`Robot.blend`、2D 渲染文件。
- 不做轮盘的按键循环选择（只做光标拖拽）。

## 2. 架构与组件（纯客户端展示层）

### 2.1 `scripts/ui/mark3d_math.gd`（改，纯函数）
- 新增 `sector_for(offset: Vector2, inner: float, outer: float) -> String`：`offset = cursor - center`；`|offset| < inner` 或 `> outer` → `""`；否则按角度返回 `"eye"`(上) / `"question"`(右) / `"number"`(下) / `"exclaim"`(左)（屏幕坐标 y 向下，`atan2(offset.y, offset.x)`）。

### 2.2 `scripts/ui/mark_wheel.gd`（新增，`class_name MarkWheel extends Control`）
- 全屏 overlay（`PRESET_FULL_RECT`、`z_index=100`、`mouse_filter=IGNORE`，仅视觉）。
- `open(center: Vector2, number_text: String)` / `close()` / `update_cursor(pos: Vector2)` / `selected() -> String`。
- `_draw()`：画 4 个环形扇区（`INNER`/`OUTER` 半径，角度均分；高亮 hovered 扇区）+ 中空 + 图标（`eye` 画圆/眼形；`question`/`exclaim`/`number` 用 `draw_string` 画 `?`/`!`/文本）。半径/字号常量可调。
- 命中用 `Mark3dMath.sector_for`。

### 2.3 `scripts/ui/mark3d.gd`（改）
- `setup(owner_dir: Vector3, icon := "eye", text := "", show_pointer := true)`；`show_pointer=false` 时隐藏两层波纹与箭头（仅图标）。
- 图标：`_eye`（`Sprite3D`，`_eye_texture()`）用于 `eye`；`_label`（`Label3D`，billboard、`no_depth_test`）用于 `question`/`exclaim`/`number`（文本 `?`/`!`/`text`）。切换图标时显示其一。
- `set_color(c)` 同步波纹/箭头/图标颜色（`Label3D.modulate`、眼贴图）。
- 保留生命周期 `LIFETIME=3.0s` → 淡出 → `finished` + `queue_free`。

### 2.4 `scripts/ui/table3d_view.gd`（改）
- `show_mark(seat_id, pos, style := "ripple", icon := "eye", text := "")`：
  - 同席替换旧标记；
  - 颜色 = `_mark_color_for(seat)`；
  - `ripple`：生成 `Mark3D`（`show_pointer=true`），`setup(owner_dir, icon, text)`，`global_position=pos`；
  - `nose`：生成 `Mark3D`（`show_pointer=false`，仅图标）；并驱动该席鼻子 `set_nose_target_world(pos)`（本机席 → `set_local_nose_target_world(pos)`）；
  - `finished` → 从 `_marks` 移除；若 `nose` 再复位鼻子（远程 `set_nose_target_world(ZERO)` / 本机 `clear_local_nose()`）。
- `clear_marks()`：释放全部 + 复位所有鼻子（`clear_local_nose()`，远程各席 `set_nose_target_world(ZERO)`）。
- 「鼻子归并」：`update_noses`/`set_local_nose_target_world` 仍保留（供 nose-mark 与测试），但 `main` 不再每帧调用 `update_noses`。

### 2.5 `scripts/core/game_state.gd`（改，表现层事件）
- `signal mark_placed(seat: int, pos: Vector3, style: String, icon: String, text: String)`（替换旧 2 参签名）。
- `server_mark(pos: Vector3, style: String, icon: String, text: String)` → `_apply_mark(seat,pos,style,icon,text)`。
- `_apply_mark(...)`：`pos` 非有限忽略；`mark_placed.emit(...)`；转发 `receive_mark(seat,pos,style,icon,text)`。
- `receive_mark(...)`：`mark_placed.emit(...)`。不存状态、不入快照。

### 2.6 `scripts/ui/main.gd`（改）
- 轮盘状态：`_wheel_open := false` / `_wheel_pos := Vector3` / `_mark_wheel: MarkWheel`。
- `_input`（3D）：`KEY_D` **按下** → `_open_mark_wheel()`；**松开**（`event.pressed == false`）→ `_finish_mark_wheel()`。轮盘打开期间：鼠标 motion → `_mark_wheel.update_cursor(event.position)`（不转相机）；其它 3D 输入忽略。
- `_open_mark_wheel()`：`_settings_open`/看板 → 忽略；`pos = Table3dPicker.ray_plane_y(cam, center, TABLE_HEIGHT)`；`is_finite` 且 `Mark3dMath.on_table` 才开；`_wheel_pos=pos`；`Input.set_mouse_mode(VISIBLE)`；`_mark_wheel.open(落点屏幕坐标=屏幕中心, number_text)`；`_wheel_open=true`。
- `_finish_mark_wheel()`：`sel = _mark_wheel.selected()`；`_mark_wheel.close()`；`_sync_table3d_pointer()`；`_wheel_open=false`；若 `sel != ""` 且轮盘曾打开 → `style = "nose" if _nose_enabled() else "ripple"`，`text = number_text if sel=="number" else ""`，`_send_mark(_wheel_pos, style, sel, text)`。
- 数字文本：`_discard_number_text()`：`latest_state.discard.rank` 非空 → rank；否则 `"-1"`。
- `_send_mark(pos,style,icon,text)`：房主 `GameState._apply_mark(seat,...)`；否则 `GameState.server_mark.rpc_id(1,...)`。
- `_on_mark_placed(seat,pos,style,icon,text)` → `table3d.show_mark(seat,pos,style,icon,text)`。
- 移除旧 `_on_mark_click()` 与每帧 `update_noses(...)`/`_nose_target_world` 逻辑；`_nose_enabled()` 保留（决定 style）。`_update_look_send` 的 `nose` 恒为 `Vector3.ZERO`（兼容保留）。

### 2.7 设置
- `Settings.gameplay.nose_click`：`true`=nose 指针、`false`=ripple 指针（语义不变，仍是"风格"）。

## 3. 数据流
1. 波纹/鼻子风格玩家在 3D 按住 D → 冻结落点、释放鼠标、显示轮盘（数字扇区取弃牌堆顶 rank / -1）。
2. 拖到扇区松 D → `main._send_mark(pos, style, icon, text)` → 服务器 `_apply_mark`（本地 `mark_placed` + 转发 `receive_mark`）。
3. 各客户端 `_on_mark_placed` → `Table3dView.show_mark`：ripple→波纹+箭头+图标；nose→驱动该席鼻子到 pos + 仅图标。3s 后一起消失（nose 同时缩回）。

## 4. 依赖与边界
- 纯表现：2D 不产标记；轮盘仅 3D。
- 落点仅桌面内；桌外不出轮盘。
- 隐私：只同步桌面坐标 + 图标类型/数字文本（弃牌顶公开）；无牌面泄漏。
- 同席唯一：`_marks[seat]` 单条，替换即重置 3s。
- 退出 3D：`clear_marks()` + 复位鼠标；轮盘打开时退出需先关闭轮盘。
- 兼容：`show_mark` 新参数带默认值，旧 2 参调用仍可用；`GameState.mark_placed` 改 5 参（同步更新测试）。

## 5. 参数（初值，可调）
| 常量 | 初值 | 说明 |
| --- | --- | --- |
| `MarkWheel.INNER` / `OUTER` | `0.16` / `0.34`（×屏幕 min 边半长） | 中空内半径 / 扇区外半径 |
| `MarkWheel.ICON_FONT` | `28` | 扇区文字大小 |
| `Mark3D.LIFETIME` / `FADE_OUT` | `3.0` / `0.3` | 寿命 / 淡出 |
| `Mark3D.RING_OUTER/INNER` | `0.2333` / `0.20` | 波纹尺寸（不变） |
| `MARK_ICON_FONT_SIZE` | `64` | `Label3D` 图标字号 |

## 6. 测试与验收
扩展 `tests/verify_mark.gd`（headless）：
- `Mark3dMath.sector_for`：上/右/下/左/中空/超范围。
- `MarkWheel`：open/update_cursor/selected（各扇区）/close。
- `Mark3D`：`setup(..., icon, text, show_pointer)`——ripple 显示波纹、nose（`show_pointer=false`）隐藏波纹与箭头；icon=eye/question/number/exclaim 切换正确；`text` 文本正确。
- `Table3dView.show_mark`：ripple 生成带波纹的标记；nose 隐藏波纹且该席鼻子目标=pos；替换/清空；`finished` 后鼻子复位。
- `GameState`：`_apply_mark(seat,pos,style,icon,text)` 发 5 参信号；非有限忽略；`receive_mark` 发信号。
- 回归：`verify_nose`、`verify_table3d_interaction`、`verify_table3d_exchange`、`verify_protocol`、双实例 `verify_net` 全绿。

**验收闸门**：新增断言全绿；单进程全量全绿；`git diff` 确认 `scripts/net/*`、`table3d.tscn`、`Robot.blend`、2D 渲染文件零改动。

## 7. 文件清单
| 文件 | 变更 |
| --- | --- |
| `scripts/ui/mark_wheel.gd` | **新增**：四扇区轮盘 |
| `scripts/ui/mark3d_math.gd` | 新增 `sector_for` |
| `scripts/ui/mark3d.gd` | icon(眼/问/数/叹) + `show_pointer` |
| `scripts/ui/table3d_view.gd` | `show_mark` 扩展（style/icon/text + 驱动鼻子） |
| `scripts/core/game_state.gd` | `mark_placed`/`server_mark`/`_apply_mark`/`receive_mark` 增 style/icon/text |
| `scripts/ui/main.gd` | D 长按轮盘（开/拖/松）、数字文本、发送/显示；停用 look.nose 上报与每帧 update_noses |
| `tests/verify_mark.gd` | 上述断言 |
| docs × 4 | 记录 Mark v2 |

**不改**：`scripts/net/*`、`scenes/ui/table3d.tscn`、`assets/characters/source/Robot.blend`、`game_view.gd`、`card_view.gd`、`card_block.gd`、`card_animator.gd`、`reveal_controller.gd`、`card_fly*.gd`。
