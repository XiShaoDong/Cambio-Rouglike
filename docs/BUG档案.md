# KONG BUG 档案（已解决 Bug + 诊断方法）

> **本文档职责**：记录**已解决且容易复发**的 bug 及其根因、修复、诊断方法。供开发者与 AI Agent 在相关需求导致 bug 复现时，按诊断方法快速定位并修复。未决/歧义问题请登记到 `docs/问题档案.md`，不含此档。

---

## B1：『大牌位移』（重要，需牢记）

**现象**：弃牌/Use Power 后大牌位移。第一次不位移，第二次之后所有抽牌堆/大牌都位移；抽牌动画终点正确，但大牌后续位置漂移。

**根因**：`pending_card_box` 用 `scale = 1.5` + `pivot_offset` + `global_position` 组合定位大牌。Godot 中 `Control.global_position`（布局坐标）在 scale/pivot 存在时不稳定——设 `(100,100)` 实际视觉为 `(83,73.25)`，重置后变 `(100,100)`，导致每次操作后视觉位置漂移（"第二次之后"正是 scale/pivot 状态积累所致）。

**修复**：移除 `pending_card_box` 的 scale，大牌直接用 **1.5 倍实际尺寸（102×160）**，`global_position = mid - 大尺寸/2` 直接对应视觉左上角。

**诊断方法（复现时套用）**：
1. 检查是否用 `Control.scale` + `global_position`/`pivot_offset` 组合定位卡牌（大牌/卡牌放大场景）
2. 用 headless 单元测试验证多次设 `global_position` 后 `get_global_rect()` 是否稳定
3. 若 scale+pivot 导致 `global_position` 读取值与设定值不一致 → 改用实际尺寸定位，不用 scale

---

## B2：交换/替换后槽位永久虚线空缺（卡牌消失）

**现象**：Q/J 交换、replace（大牌交换）后，玩家卡牌槽位变成虚线占位，卡牌永不出现且无法点击选中。

**根因**：动画 `mark_anim_slot()` 后**从不清除标记**。旧实现用 `func(): remaining -= 1` 闭包捕获 int 计数器——**GDScript lambda 捕获 int 局部变量的修改未正确累积**，两次 on_finish 都 `remaining=1`，`remaining<=0` 永不成立 → `unmark_anim_slot` 不执行 → 槽位永远渲染为虚线占位（无法点击）。

**修复**：改用**字典计数器** `{"remaining": n}` + `_swap_done.bind(counter, ...)` / `_replace_done.bind(...)`。字典按引用传递，两次 on_finish 正确累积到 0，清除标记并重建。动态统计实际执行的动画数（防止某分支缺失时计数错误）。

**诊断方法**：
1. 检查动画完成回调是否用**闭包捕获 int 计数器**
2. 用 headless 测试（`tests/verify_swap.tscn`）验证动画后 `is_anim_slot()` 已清除
3. 闭包计数器 → 改用字典 + `bind`

---

## B3：hint 不显示（RichTextLabel 渲染异常）

**现象**：center_hint 改用 RichTextLabel 后，只显示几个黄色像素点，文本不渲染。

**根因**：RichTextLabel 在该布局下文本渲染异常（可能 bbcode/fit_content/字号组合问题）。

**修复**：center_hint 回退为 **Label** + `max_lines_visible = 3`（三行），移除 `[b]` bbcode 标签（Label 不支持部分加粗）。

**诊断方法**：
1. 若 hint 改用 RichTextLabel 后不显示 → 回退 Label
2. 若需名字加粗 → 用两个 Label 并排（普通文本 + 加粗名字），不用 RichTextLabel

---

## B4：hint 每字一行（Label 宽度塌缩）

**现象**：hint 只显示三个字各占一行。

**根因**：隐藏 `game_header` 后 `top_unit`（VBox）宽度塌缩，`center_hint`（Label）宽度极窄，`autowrap` 使每个词/字单独一行。

**修复**：`center_hint` 设 `custom_minimum_size = Vector2(400, 0)` + `SIZE_SHRINK_CENTER`，保证足够宽度。

**诊断方法**：
1. 若 Label 每字一行 → 检查所在容器宽度是否塌缩（隐藏了占宽度的兄弟节点）
2. 给 Label 设固定最小宽度

---

## B5：翻面动画中断（Can't append to a Tween that has started）

**现象**：抽牌/看牌翻面后仍显示背面，动画停在 scale.x≈0（薄片）。

**根因**：`flip_to_face`/`_create_flip` 在 `tween_callback` 内再 `tween_property` 追加步骤——**tween 已 started 不能再追加**，动画中断。

**修复**：改为**独立 tween**——收缩 tween 完成后通过 `_finish_flip(from, to, dur)` 回调切换面并**新建 tween** 展开。

**诊断方法**：
1. 若翻面动画中途失败 → 检查是否在已启动 tween 内追加步骤
2. 改用独立 tween 或回调方法
