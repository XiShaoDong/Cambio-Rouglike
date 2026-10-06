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

---

## B6：大牌被容器裁剪 / “看得见点不到”

**现象**：抽到的大牌（pending_card）放进容器内被裁剪显示不全；Use Power/弃牌按钮看得见但点不到。

**根因**：大牌挂在 `center_unit`（固定尺寸容器）内部的 `pending_overlay` 里，超出容器边界被裁剪；按钮被上层 Control 拦截点击事件。

**修复**：`main.pending_overlay = main.board`（大牌移到 GameBoard 顶层，不再受容器约束）；`GameBoard.mouse_filter = PASS`（放行下层点击）、大牌卡 `pending_card_button.mouse_filter = IGNORE`（不挡按钮）。

**诊断方法**：
1. 大牌/弹层被裁剪 → 检查是否挂在带尺寸约束的容器内，移到场景顶层
2. 元素可看不可点 → 检查上层控件 `mouse_filter` 是否 `STOP` 拦截；设 `PASS` 放行 / 目标元素设 `IGNORE`

---

## B7：贴牌揭示露出默认背面

**现象**：贴牌（slap）翻牌揭示期间，槽位底下原卡或默认背面可见，视觉露馅。

**根因**：揭示翻牌只在 overlay 播动画，底层槽位原卡未隐藏；render 重建时槽位仍渲染原卡。

**修复**：`_play_flip_at` 揭示期间 `anchor.visible = false` + `mark_anim_slot(target_id, slot)`（渲染为空占位），动画结束 `unmark_anim_slot` + `_render_game` + 恢复原卡可见。

**诊断方法**：
1. 翻牌揭示露底 → 检查是否隐藏了底层原卡并标记槽位为动画中
2. 揭示期间用 `mark_anim_slot` 让 render 重建时槽位显示空占位，动画后清除

---

## B8：比拼无人 STOP 崩溃（best=0 越界）

**现象**：贴牌比拼（SLAP_DUEL）全员未按 STOP，`duel_timeout` 结算时报 `Invalid access to property or key '0' on a base object of type 'Dictionary'`。

**根因**：`resolve_duel` 里 `var best := 0`，若没有候选人按 STOP，循环内 `best` 不被更新，随后 `duel.correct[best]`（即 `correct[0]`）访问不存在的键。

**修复**：结算循环后加 `if best == 0: best = int(duel.correct.keys()[0])`（兜底选第一个候选人，保证比拼总能解决）。

**诊断方法**：
1. 比拼结算报 `correct[0]` 越界 → 检查无人 STOP 时 `best` 是否仍为初值 0
2. 兜底选第一个候选人（或规定"无人 STOP 则全败/重赛"）

---

## B9：DuelBar 比拼弹窗不可见（根节点尺寸 0）

**现象**：比拼弹层添加到 overlay 后，全屏遮罩与居中窗口完全看不见（此前浮层版可见但不明显）。

**根因**：`DuelBar` 作为 `Control` 被 `add_child` 到 `overlay` 时，自身锚点默认左上、尺寸 0；内部 `set_anchors_and_offsets_preset(PRESET_FULL_RECT)` 的子节点（遮罩/居中容器）以父节点（0 尺寸）为基准 → 全部 0 尺寸不可见。

**修复**：`_build_ui` 开头 `set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)`，让 DuelBar 根节点铺满 overlay。

**诊断方法**：
1. 覆盖层子节点不可见 → 检查根 Control 是否铺满父级（锚点 FULL_RECT）
2. 加进普通 Control（非容器）的弹层都要先设锚点，否则内部相对布局全失效

---

## B10：贴牌贴错无红光 / 罚牌无飞牌（reveal 路由错误 + 槽位未渲染提前返回）

**现象**：贴错时被贴的牌只翻一下（无红色炫光）；罚牌从抽牌堆飞入的动画不播放（凭空出现）。

**根因**：
1. `_flip_at` 分发按 `correct` 值而不是"是否贴牌 reveal"判断：贴错（`correct=false`）被路由到看牌路径 `_play_flip_at`（无炫光）→ 改为按 target 是否带 `correct` 键（`is_slap`）分发。
2. `slap_penalty` 事件到达时第 5+ 张追加槽位尚未渲染，`_animate_slap_penalty` 提前 `return` → 加 `_pending_slap_penalties` 队列，`_render_game` 后补飞。

**诊断方法**：
1. reveal 无对错炫光 → 检查 `_flip_at` 是否按"是否贴牌"分发（不是按 correct 值）
2. 罚牌无 fly → 检查槽位是否在事件到达时已渲染；未渲染要挂起补飞

---

## B11：罚牌 fly 位置固定到右上卡 / 罚牌提前落位（异步定位缺口 + 标记顺序）

**现象**：罚牌 fly 飞到一个固定位置（右上网格卡附近）而不是新卡位置；且 fly 刚开始播放时罚牌已落位显示。

**根因**：
1. `ExtraLayer` 定位改为同步（按槽号固定绝对定位 `_extra_slot_pos`）之前，异步定位（等一帧）导致 `_render_game()` 重建后的附加卡落在默认位置 → fly/reveal 读到错误锚点。
2. `_animate_slap_penalty` 在**标记动画槽之前**就排队返回（第 5+ 张未渲染），状态渲染时槽位未标记 → 罚牌直接显示。

**修复**：附加卡按槽号同步固定定位；`_animate_slap_penalty` 开头先 `mark_anim_slot`（即使槽位未渲染），保证渲染显示占位、fly 落地后才出现卡。

**诊断方法**：
1. 动画目标错位 → 检查目标节点是否在渲染/布局稳定后取 rect
2. 动画开始前卡已落位 → 检查是否先标记动画槽位（`mark_anim_slot`）再允许渲染

---

## B12：罚牌附加卡位置随罚牌数变化（GridContainer 重排）

**现象**：第 3 张罚牌加入时，已有罚牌（如 slot4）整体上移/重排。

**根因**：`ExtraRow` 用 `GridContainer`，卡数从 1 行变 2 行时整组重排，已存在卡移动。

**修复**：改为 `ExtraLayer` + **按槽号固定绝对定位**（`_extra_slot_pos`：idx0/1 靠主网格行、idx2/3 更上一行，位置只由槽号决定），加新罚牌时已存在卡不移动；主网格列数固定按 `HAND_SIZE`。

**诊断方法**：
1. 附加卡数量变化导致已有卡位移 → 不要用容器自动布局，按槽号固定绝对定位
2. 主网格随卡数变列 → `columns` 固定按 `min(slots, HAND_SIZE)/2`

---

## B13：罚牌持久正面显示（revealed_slots 回退）

**现象**：罚牌在当前玩家视角一直正面显示（记忆机制要求短暂揭示后回背面）。

**根因**：曾用 `GameState.revealed_slots` 让罚牌槽对所有者持久正面 → 与"只能记住看过/抽过的牌"的记忆机制不符。

**修复**：回退 `revealed_slots`；罚牌直接以背面 fly 到槽位并保持背面（不做翻面揭示）。

**诊断方法**：若某槽位在快照中持久含 `card` 而该玩家未看过 → 检查是否误加了持久揭示槽位机制

---

## B14：debug_duel 下第一名贴牌后全员无法点击（收集窗被判定锁锁死）

**现象**：`debug_duel`（O 键）开启时，任意玩家贴一张牌（恒判对）后，所有玩家都无法进行任何点击（贴牌/抽牌堆/弃牌堆），比拼永不触发。

**根因**：正确贴牌 reveal 在客户端走 `_play_slap_flip` 的绿光 hold 分支，只 `_slap_reveal_begin()` 而不 `_slap_reveal_end()`，锁要等 `slap_resolved` 结算事件才释放。`game_interaction.on_card_pressed` 贴牌分支以 `if main._slap_reveal_lock: return` 拦截所有贴牌点击 → 收集窗（debug 下 30s）期间第二名玩家永远发不出 `request_slap` → 双贴比拼无法触发，全员冻结至收集窗超时。

**修复**：`game_interaction.on_card_pressed` 的贴牌分支**不再检查 `_slap_reveal_lock`**——收集窗内允许继续贴牌（这正是收集窗/ debug_duel 双贴比拼的目的）。判定锁继续保护抽牌堆/弃牌堆点击（`main._on_deck_pressed`/`_on_discard_pressed` 不变），避免揭示期间误取牌。

**诊断方法**：
1. 贴牌后全员点不动 → 检查贴牌分支是否被 `_slap_reveal_lock` 拦截
2. 判定锁只应挡抽牌堆/弃牌堆，**不应挡收集窗内的贴牌意图**
3. headless 测试（`verify_duel`）因直接调 `_server_slap` 绕过 UI，无法覆盖此客户端锁问题，需手动 GUI 复现

---

## B15：结算时手牌含空槽导致 calculate_ranking 崩溃

**现象**：对局结束时（`GAME_OVER` 结算）报 `calculate_ranking: Invalid access to property or key of type 'String' on a base object of type 'Dictionary'`（`score_system.gd:14`）。

**根因**：贴牌/交换后清空槽位 `players[x].cards[slot] = ""`（`slap_system.gd:170/178`、`exchange`），空串 `""` 残留在手牌数组。`calculate_ranking` 遍历时把空槽当有效卡 id：`cards[""]` 返回 null，对 `null.value` 访问即报错。玩家在贴过牌的局里结算必然触发。

**修复**：`score_system.gd:14` 遍历手牌时跳过空 id（`if str(card_id).is_empty(): continue`）。

**诊断方法**：
1. 结算崩溃 + 玩家曾贴牌/交换 → 检查是否把空槽 `""` 当卡 id 索引 `cards` 字典
2. 手牌数组遍历一律先判空串再取 `cards[card_id]`，与 `game_view`/`hidden_info` 一致

---

## B16：玩家退出中止后，房主重建房间无法进入对局（卡在大厅）

**现象**：对局中任一玩家退出 → 全员回大厅；之后房主再开局，其他玩家正常进入，**但房主/主机永远停在大厅页面**，无法进入对局。

**根因**：`_reset_match()` 把 `state_revision` 重置为 `0`，但**没有重置去重水位线 `last_seen_revision`**。房主本地 GameState 的 `last_seen_revision` 保留上一局最高值（如 13）。新一局 `state_revision` 从 1 重新计数，`_receive_state` 中 `revision <= last_seen_revision` 把新快照全部判为旧包丢弃 → `state_updated` 永不触发 → UI 停在大厅。（其他玩家多为新进程/新连接，水位线为 -1，故正常。）

**修复**：
1. `_reset_match()` 末尾加 `last_seen_revision = -1`（房主侧）。
2. `receive_match_aborted` RPC 处理开头加 `last_seen_revision = -1`（一直连着的客户端同样重置，否则也会丢新局快照）。

**诊断方法**：
1. 中止/重建后 host 收不到新快照 → 检查 `state_revision` 重置但 `last_seen_revision` 未重置
2. 用 headless 测试：第一局广播抬高水位线 → `_reset_match()` → 新一局开局，断言 `state_updated` 仍能触发（修复前 delta=0，修复后 delta>0）

---

## B17：客户端退出房间后重新"加入房间"进不去（房主对局进行中）

**现象**：客户端点"退出房间"后，房主仍在房间（对局进行中），客户端重新点"加入房间"→ 提示栏闪过"正在连接…"、"已加入房间"，但一直停留在大厅进不去。

**根因**：`request_register_player` 仅在 `LOBBY` 阶段有效；房主对局进行中（`phase != LOBBY`）注册被服务端**静默拒绝**（`request_register_player` 直接 `return` 不发拒绝）。且 `_leave_room` 之前**清空了 token**，客户端无法走 `request_reconnect` 认领原座位 → 连接成功但收不到对局状态。

**修复**：
1. `lobby_view._leave_room` 保留 token 与地址（不再清空 `_my_token`），供重新加入时凭 token 重连。
2. `main._on_joined_server_for_reconnect` 连接成功后若持有 token 即调用 `request_reconnect` 认领原座位；token 无效被拒不影响 LOBBY 阶段正常注册。

**诊断方法**：
1. 客户端"已加入房间"但停留大厅 → 检查是否被服务端注册静默拒绝（对局中 phase != LOBBY）
2. 退出房间时是否清空了 token → 保留 token 才能凭它重连
3. 连接成功后应尝试 `request_reconnect`（`_on_joined_server_for_reconnect`）

## B18：断线重连后所有手牌一直保持正面

**现象**：断线重连后，本人所有手牌一直正面朝上（卡面可见），违反"只能记住看过的牌"的暗牌记忆机制。

**根因**：服务器 `_send_resume_hand` 补回全部手牌面，客户端 `main._on_resume_hand` 填入 `_resume_hand_map`；`game_view._render_card_slot` 用它对每个本人槽位渲染正面，且 map 重连后永不清除 → 永久正面。

**修复**：`_render_card_slot` 移除 `_resume_hand_map` 渲染逻辑；`_on_resume_hand` 只隐藏重连面板并重渲染；删除无用变量 `_resume_hand`/`_resume_pending`/`_resume_hand_map`。

**诊断方法**：重连后检查本人手牌是否渲染为背面；`_resume_hand_map` 是否仍有数据。

## B19：replace（抽牌堆牌↔自己手牌）动画落位后闪烁

**现象**：当前玩家用抽牌堆的牌替换手牌时，其他玩家视角在 fly 动画结束、牌落位后闪烁（槽位牌消失片刻 / 弃牌顶闪回旧牌）。

**根因**：`animate_replace` 用计数器等**两张 fly 都完成**才清除槽位动画标记、解锁弃牌堆并重建；两张 fly 距离不同落位有先后，先落位的一段被清理后其目标（槽位/弃牌顶）在等待另一段落位期间短暂回到旧状态。

**修复**：改为每段 fly 落位各自处理自身并刷新（`_replace_landed`）：弃牌段落位立即解锁弃牌堆显示新弃牌；抽牌段落位立即清除槽位标记显示新牌，互不等待。

**诊断方法**：像素级捕获对比落位瞬间槽位空挡帧（旧代码约 6 帧 → 修复后 0）。

## B20：discard-replace 后所有玩家手牌两行出现 gap

**现象**：房主取弃牌堆牌替换手牌时（首次不出现、后续出现），房主屏幕上**所有玩家**手牌第一/第二行之间出现大空隙，下一玩家操作后恢复。

**根因（推断）**：`_clear_area` 用 `queue_free()` 延迟释放网格旧卡，同帧重建时 GridContainer 同时含旧卡+新卡 → 2 列网格临时多出行；replace 落位修复增加了同帧重建次数使其更易触发。

**修复**：`_clear_area` 先 `remove_child` 立即移出网格、再 `queue_free` 延迟释放（ExtraLayer 同理），杜绝旧卡+新卡累积。

**诊断方法**：用 `HandGrid.get_child_count()` 采样，重建期间应恒为 4；若为 8/12 说明旧卡未及时移出。

## B21：J 能力点击对方卡报 "Object is locked" + 卡牌增多

**现象**：将 `_clear_area` 改为 `free()` 后，用 J 能力点击对方牌（点击触发重建）报 "Object is locked and can't be freed"；即使不报错，选择对方牌时卡牌增多，交换结束复原。

**根因**：卡牌点击触发重建时，被点击的卡正被 `pressed` 信号锁定，直接 `free()` 非法；free 失败导致旧卡残留（卡牌增多）。

**修复**：`_clear_area` 改为先 `remove_child` 立即移出网格、再 `queue_free` 延迟释放，不触碰被信号锁定的对象。

**诊断方法**：模拟 J 能力点击流程，应无 locked 报错、网格子节点数恒为 4。

## B22：Kongbaya 不结算 + 可重复喊叫

**现象**：① Kongbaya 触发后不进入结算（GAME_OVER）；② 最终轮玩家可再次喊 Kongbaya，不符合"一场一次"规则。

**根因①**：`kong_caller` 用 **0** 作为"无喊叫者"哨兵，但房主座位恰为 0 → 房主喊叫时 `kong_caller=0`，`_advance_turn` 的 `if kong_caller != 0` 误判为"未喊叫"，最终轮被当作普通回合推进，永不结算。
**根因②**：`declare` 未拦截"已喊过"的情况，最终轮玩家（TURN_DRAW 且为当前玩家）可重置 `kong_caller`/`final_queue`。

**修复**：`kong_caller` 哨兵 **0 → -1**（game_state 声明/`_reset_match`/踢出重置、`_advance_turn` 判断与传参、`turn_system.decide` 判断）；`kongbaya_system.declare` 加 `kong_caller != -1` 拦截重复喊叫（返 `INVALID_PHASE`）。

**诊断方法**：新增 `verify_kongbaya`（15/15）覆盖正常最终轮结算、重复喊叫被拒、首/非首回合 `kong_called_first_turn` 标记。

## B27：出局玩家被算进分数排名（0 张 0 分恒排第一）

**现象**：有玩家出局（`health==0` 观战）后，结算排名把出局玩家也算进去；因出局者手牌为空，0 张 0 分在"低分胜"规则下**恒排第一名**。

**根因**（三个泄漏路径）：
1. `ScoreSystem.calculate_ranking` 遍历传入的 `turn_order`，**不跳过出局者**——依赖调用方传入"存活序"，容易漏。
2. `_finish_game_over_hand`（R-07 超限结算）的 `others` 用 `turn_order` 排除失败者，**未排除出局者**。
3. 客户端 `main._open_settlement` 用 `SettlementModel.build(latest_state.players)`，快照含全部座位（含出局者空手牌），结算页因此显示出局者行且 0 分置顶。

**修复**：
1. `ScoreSystem.calculate_ranking` 遍历时跳过 `health<=0` 玩家（`if int(players[peer_id].get("health", 1)) <= 0: continue`）——根治所有服务器侧路径。
2. `_finish_game_over_hand` 的 `others` 改走 `_alive_order()`（排除出局者）。
3. `main._open_settlement` 对 `latest_state.players` 先 `.filter(func(p): return not p.eliminated)` 再 `SettlementModel.build`。

**诊断方法**：出局后结算出现 0 分玩家置顶 → 检查排名/结算模型的输入是否含出局者；新增回归 `verify_series._test_over_hand_ranking` / `_test_settlement_model_excludes_eliminated`（36/36）。

## B23：结算页「再来一局」/「返回大厅」按钮点不到

**现象**：结算动画播完，footer 出现「再来一局」「返回大厅」按钮，但点击无任何反应（按钮显示了却收不到鼠标）。

**根因**：结算页根节点 `mouse_filter = IGNORE(2)` 且挂在 `overlay` 下。Godot 4.6 的 GUI picking 用 `get_mouse_filter_with_override()` 判定，IGNORE 祖先使整棵子树被判为不可点击（`settings_menu` 根节点为 STOP、直接挂 main 末尾则正常）。
**另**：同 root 内 picking 按**逆树顺序**递归（不按 z_index），`overlay` 在 `margin`（棋盘）之前，结算页若留在 overlay 内会被棋盘上重叠的 STOP 控件抢点击。

**修复**：`settlement_page.tscn` 根节点 `mouse_filter` 2→**0 (STOP)**；`main._open_settlement` 由 `overlay.add_child(page)` 改为 **`add_child(page)` 直挂 main 末尾 + `z_index=100`**（与已验证的 `settings_menu` 模式一致，末位子节点优先接收点击）。

**诊断方法**：headless 无法测真实鼠标；对比 `settings_menu`（STOP + 直挂 main）与结算页（IGNORE + overlay）的结构差异；真实游戏点击按钮看回调是否触发。

## B24：再来一局后新局快照引旧卡 id 报 public_card 错

**现象**：房主点「再来一局」后，新对局某处报 `public_card: Invalid access to property or key 'c_xxxxxx' on a base object of type 'Dictionary'`。

**根因**：`_deal_new_match()`（从 `_server_start_match` 抽取）只清了 `initial_confirmed`/`last_result`，没清 `discard_pile`/`pending_draw` 等按局状态。`_create_deck()` 重建了 `cards` 字典（新卡 id），但上一局弃牌堆还留着旧卡 id；新局快照构建弃牌顶时 `public_card` 用旧 id 查新字典即报错。此前从 LOBBY 开局没问题是因为 `_reset_match` 已清空；从 GAME_OVER 直接再来一局暴露。

**修复**：`_deal_new_match` 补齐清理 `discard_pile`/`pending_draw`/`q_context`/`final_queue`/`kong_caller`/`slap_rank`/`slap_open`/`slap_exchange`/`slap_collect`/`slap_duel`/两个定时器/`event_log`。

**诊断方法**：制造真实对局（含弃牌+残留待处理牌）→ 再来一局 → 断言新快照无旧卡泄漏（`verify_settlement._test_next_match_clears_stale`）。

## B25：再来一局后贴错牌报 "Trying to assign invalid previously freed instance"

**现象**：再来一局后，新局里贴错牌触发罚牌动画时报 `CardAnimator._animate_slap_penalty: Trying to assign invalid previously freed instance`（card_animator.gd:129）。

**根因**：`main._card_slots`（卡牌节点映射）从未在局间清空。上一局某玩家有罚牌超出手牌数（第 5/6 张槽位），这些槽位在新局不重渲染；新局贴错时 `_animate_slap_penalty` 读取 `_card_slots[seat][slot]` 命中残留的**已释放节点**（类型化赋值那一刻报错，`is_instance_valid` 检查来不及执行）。

**修复**：`main._render_game()` 开头 `_card_slots.clear()`（每次渲染全量重建）；`_open_settlement` 清 `_anim_slots`/`_pending_slap_penalties`/`_pending_flips` 并复位贴牌锁。

**诊断方法**：上一局造 5 张手牌 → 再来一局 → 断言 `_card_slots` 无已释放节点且仅含当前槽位（`verify_settlement._test_next_match_card_slots`）。

## B26：结算时被 peek 过的牌翻回背面

**现象**：结算算分动画逐张翻牌，被（别人）peek 过的牌翻到正面后会再翻转回背面，其他牌正常。

**根因**：结算开始时若仍有**在途看牌揭示**（`reveal_controller._play_flip_at`，~1.5s 后调用 `main._render_game()`），该延迟重渲染在结算动画期间把整个棋盘重绘回背面，把已翻开的牌翻回；同时该槽位在揭示期间被 `mark_anim_slot` 标记，GAME_OVER 首次渲染会变成透明占位而非真实卡。

**修复**：新增 `main._render_game_if_active()`（phase == GAME_OVER 时跳过重渲染），把 `reveal_controller`/`card_animator` 所有**动画完成回调**的 `_render_game()` 替换为它；`_on_state_updated` 进入 GAME_OVER 时先 `_clear_settlement_anim_state()`（清 `_anim_slots`/`_pending_*`/贴牌锁）再渲染；`apply_theme` 同步用守卫。

**诊断方法**：结算时触发一个在途 peek 揭示 → 跑完整结算动画 → 断言所有卡牌正面朝上（`verify_settlement._test_settlement_peek_card`）。

## B28：3D 环视无法移动（捕获态收不到 _unhandled_input 的 motion + 重复取景复位视角）

**现象**：F10 进 3D 后移动鼠标视角完全不动，但 F10/ESC 键正常能切进切出（渲染、快照都正常）。

**根因**：两个叠加 —— ① 鼠标 `MOUSE_MODE_CAPTURED` 下 `_unhandled_input` **收不到** `InputEventMouseMotion`（被 GUI 路径先消费），而键不受影响；② `Table3dCamera.frame_for_seat` 每次 `render`（状态广播）都重置 `yaw/pitch`。注意先别被"`Input.mouse_mode == CAPTURED` 判断失败"误导：实测进入 3D 时 `mouse_mode` 已是 2(CAPTURED)。

**修复**：环视改走 **`main._input`**（早于 GUI 路由，保证事件必达，不受任何 Control 的 `mouse_filter` 影响）；`frame_for_seat` 同座位重复取景**不再复位**视角；方向改为 `yaw - rel.x`（鼠标右移=右转）、灵敏度 `MOUSE_SENSITIVITY`（度/像素）。

**诊断方法**：`verify_table3d_mouse`（事件可达 / STOP 不吞 motion / 相机为当前 / 取景离开原点 / `look()` 改变朝向 / yaw 夹取）。排错时先看 `_input` 是否被更早的 `return` 拦掉，再确认视角是否被重复取景复位。

## B29：3D 卡背只显示一部分（BoxMesh 十字 UV）

**现象**：3D 卡面只显示卡背图的一部分（像被裁掉）。

**根因**：Godot `BoxMesh` 的 **UV 是「十字展开」而非每面 0–1**：实测顶面四角 `V` 恒为 0，只采样贴图最上面一条线。**不是模型太小，也不是素材问题**（`back07.png` 352×512，`Image.get_used_rect()` = 整张无透明留白，比例 0.6875≈卡面 0.7）。

**修复**：卡面改用 **`PlaneMesh(orientation=FACE_Y)`**（UV 完整 0–1）+ `cull_mode=CULL_DISABLED`；`Deck`（抽牌堆）也改用 `CardBlock`。点数标签用 billboard `Label3D` 悬于卡上方。

**诊断方法**：打印 `BoxMesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]` 看各面 UV（十字展开）；`PlaneMesh FACE_Y` 四角应为 (0,0)/(1,0)/(0,1)/(1,1)。

## B30：隐藏的 pending 卡仍被准星命中

**现象**：3D 中准星停在牌堆位置时命中 `pending`（而不是 `deck`）；无 pending 时牌堆点不到。

**根因**：`Node3D.visible=false` **不会**禁用 `CollisionObject3D`(Area3D) 的碰撞形状；隐藏的 `Pending` 与 `Deck` 同 XZ、`y` 略高，射线最近命中恒为 Pending。

**修复**：`CardBlock.set_pick_enabled(on)`（直接设 `CollisionShape3D.disabled`）；`Table3dView.render` 中 `pending`/`discard` 为空即禁用拾取。

**诊断方法**：`verify_table3d_interaction` 断言「默认准星指向牌堆」；隐藏 pending 后拾取不应命中它。

## B31：3D 默认视角准星指向桌外 → 什么都点不到

**现象**：3D 下点击完全没反应（看似"点不了任何东西"）。

**根因**：`EYE_HEIGHT=3.5` + 默认俯角 20° 时，**屏幕中心射线落在桌外空旷处**（实测 `pick_center()` 返回 `{}`）；需俯到 60° 才命中自己的手牌。crosshair 是固定屏幕中心，所以默认取景下没有可点目标。

**修复**：新增 `Table3dCamera.aim_pitch_deg(eye, horiz)`，`frame_for_seat` 默认俯角**对准桌心**（准星起始落在牌堆）；`Table3dLayout.PICK_HEIGHT=0.3` 加高拾取盒，薄卡斜角也易命中。

**诊断方法**：实测 `view.pick_center()`；`verify_table3d_interaction` 断言默认准星指向牌堆。以后调整 `EYE_HEIGHT/CAMERA_BACK` 会经 `aim_pitch_deg` 自动重新对准。

## B32：悬停对象被 render 释放 → 带类型 Object 形参报错并中断 clear_hover

**现象**：运行时错误 `Table3dView.update_hover: Invalid type in function '_apply_hover' in base 'Node3D (Table3dView)'. The Object-derived class of argument 1 (previously freed) is not a subclass of the expected argument class.`

**根因**：`_hover_collider` 指向的 `Area3D` 会在下一次 `render` 重建手牌时被释放；`_apply_hover(collider: Object, …)` 的**带类型形参在「传参处」就做类型检查**，函数体内的 `is_instance_valid` 根本来不及执行 → 报错并**中断 `clear_hover()`**（`_hover_collider` 未被清空，后续每帧继续报错）。

**修复**：`_apply_hover` 形参**不标注类型**（传参处不做类型检查，`is_instance_valid` 兜底）；`update_hover`/`clear_hover` 先用 `is_instance_valid` 过滤出有效对象再调用。

**诊断方法**：`verify_table3d_interaction` 新增「悬停对象释放后 clear_hover 安全」——把 `_hover_collider` 设为一个随即 `queue_free` 的节点，再 `clear_hover()`，断言 `_hover_collider == null`（旧代码会因报错中断导致断言失败）。

## B33：3D 座位/手牌与 2D 左右、前后相反（座位角度均分 + 座位节点旋转镜像）

**现象**：2D 棋盘左下是 A、右下是 J，切到 3D 后左边是 J、右边是 A；且自己手牌的槽位既向左又向后（靠近自己的一侧反而排在前四张的后两格），新加的牌向左手侧/上方走，与 2D 观感相反。

**根因**：两处叠加 —— ① `Table3dLayout.seat_angles` 把 viewer 之后的座位按圆**均分**递增角度（下一个对手 → `+X` = 屏幕右），而 2D `_render_players` 是「`others[0]`→左箱、`others[1]`→右箱、`others[2]`→上箱」，故左右相反；② `table3d_view._render_seat` 直接把 `slot_grid_pos` 的列/行当作本地 `+X/+Z`，而座位节点朝向为 `a+180°`（本地 `+Z`→桌心、本地 `+X`→持有者左侧），于是每个座位的手牌被**整体旋转 180°**：列向左、行朝向自己（与 2D 的行序相反）。

**修复**：纯 3D 展示层，不动 2D/服务器/协议。`seat_angles` 改为**按 2D 箱位对齐** `[0, 270, 90, 180]`（viewer 近侧 / 左 / 右 / 远，不再均分）；`slot_grid_pos` 改为**主牌 2×2 行优先（与 2D 同：0/1 上排、2/3 下排，故开局揭示的 2/3 落在下排）+ 罚牌向右追新列、每列先上（远）后下（近）**（`slot<4` → `(slot%2, slot/2)`；`slot>=4` → `(2+(slot-4)/2, (slot-4)%2)`）；`_render_seat` 取本地 `-列`×X、`(1-行)`×Z，从而列向持有者右手侧、行 0 远离/行 1 靠近，新槽位向右手侧追加（第三列 = 4 上 / 5 下）。座位节点旋转与头像位置不变。

**诊断方法**：`verify_table3d_layout` 断言 `seat_angles(4)==[0,270,90,180]`、主牌 `slot_grid_pos(0..3)==(0,0)/(1,0)/(0,1)/(1,1)`、罚牌 `slot_grid_pos(4)==(2,0)`/`(5)==(2,1)`（第三列先上后下）；`verify_table3d_interaction` 的 slot0 拾取改为**从正上方垂直下看**（避免侧向射线被同排其它卡遮挡）。

## B34：hover 卡牌边缘反复触发 hover/unhover（抖动）

**现象**：卡牌 hover 抬起/倾斜后，准星停在卡边缘会**反复 hover→unhover 抖动**；越靠近卡边缘越明显。

**根因**：hover 动画移动的是**卡牌本体**，而拾取 `Area3D` 是它的子节点 → 卡一抬起/倾斜，拾取盒随之移出准星射线 → 判定"未命中"→ 卡落回 → 又命中 → 抖动。倾斜时准星在边缘（`ray_local≈±1`）尤其容易把卡推出射线。

**修复**：**拾取判定固定在基准位、不随动画移动**。① 沙盒：`CardAnimation` 在自身（不动的根）上挂一个静态 `PickArea`，`CardBlock` 自带拾取禁用；② 3D 桌面：`CardBlock` 新增 `_visual` 视觉 pivot，`Mesh`/`Glow*`/`Label` 移入其下，**拾取 `Area3D` 留在根**，hover 只动 `_visual`；`table3d_view` 另记 `_hover_slot` 跨 `render()` 重建即时重放（避免每次快照弹一下）。

**诊断方法**：`verify_card_animation`「控制器基准拾取盒(不随动画)」「抬升时拾取盒不移动」；`verify_table3d_interaction`「own hover 抬起」「抬起时拾取盒不移动」。

## B35：翻牌途中离开卡牌 → 永久卡在 hover 抬起态

**现象**：卡牌揭示/翻牌动画进行中把准星移开，卡**一直保持抬起**不落回；再次 hover 才"重置"。

**根因**：`exit_hover()` 在 `PRESS/FLIP/LAND` 期间提前 `return`（不在翻牌中途强行落回），只把 `hovering=false`；但 `_on_land_done()` 只改 `state` 而**不回正 `hover_p`** → `hover_p` 停在 1，卡保持抬起。

**修复**：`_on_land_done()` 按当前 `hovering` 决定：仍悬停 → `HOVER` 并重新抬到 1；已离开 → `IDLE` 且把 `hover_p` 缓动回 0。`enter/exit_hover` 在 `PRESS/FLIP/LAND` 期间只记录 `hovering`。

**诊断方法**：`verify_card_animation`「翻牌途中离开 → 落定 IDLE / hover 归零」「可重新 hover 抬起」。

## B36：揭示翻牌比旧版快了一倍

**现象**：把揭示从 `scale.x` 压扁换成 3D 翻转后，翻牌动作明显变快。

**根因**：旧实现 `_flip_to` 是**两段**各 `FLIP_DURATION(0.25)`（合计 0.5s：压到 0 换面、再展开）；新实现 `_reveal_to` 只跑**一段** `FLIP_DURATION`（0.25s）→ 只有旧版一半时长。

**修复**：`FLIP_DURATION := 0.5`（重新定义为**整段翻转时长**），并同步测试等待（`_test_reveal_flip` 的结束等待由 `FLIP_DURATION*0.5` 改回 `FLIP_DURATION`；跨 render 用例的保持时长 1.0→2.0s 以容纳更长翻转）。

**诊断方法**：`verify_table3d_interaction`「揭示结束进度 1」「揭示跨 render 保持正面」按 `CardBlock.FLIP_DURATION` 等待。

## B37：3D 揭示翻完后又显示一次正面 + 重新打炫光（换牌飞牌接入后暴露）

**现象**：3D 下贴牌揭示（贴错=红色炫光）等翻牌完成后，卡牌会**再次**翻到正面并重新打上揭示色（"翻完又翻一次 + red 光晕"）；3D 换牌飞牌接入后尤其明显。

**根因**：`table3d_view.render()` 每次重建卡牌后都会对 `_reveals` 里仍登记的揭示调用 `_apply_reveal` → `CardBlock.reveal()`，而 `reveal()` 每次**无条件 `_reveal_to(1.0)`（从进度 0 重播 0.5s 翻转）**，不是"保持已翻开的正面"。揭示窗口 1.5s 内任何一次 `render()` 都会把重建为背面的目标牌**重新翻一次**并重新上色。接入的飞牌落地 `_refresh()`（新增）会在揭示窗口内触发一次延迟 `render()`（如罚牌 deck→手牌约 0.8s 落地），使这次重播**可见**——此前只有紧跟揭示的状态广播 render（与揭示几乎同时，看不出）。

**修复**：让重放**幂等/续播**。① `CardBlock.reveal(card, color, from_p := 0.0)` 新增可选起始进度；`from_p>0` 走 `_reveal_from(p)`：直接设 `_reveal_p` 并从该进度续播（`from_p>=1` 直接呈现正面、不再翻转）。② `table3d_view.reveal_slot` 记录 `start_ms`；`_apply_reveal` 按已过时间算 `p = clamp(elapsed / FLIP_DURATION, 0, 1)` 传入 → 重放时已完成则瞬现正面、进行中则续播。既有调用（默认 `from_p=0`）与沙盒不受影响。

**诊断方法**：`verify_table3d_exchange`「重放后仍为正面（进度不归零）」「重放后牌面保持」「重放后炫光保持」「进行中重放进度不回零」。

## B38：选中/悬停卡牌时，贴牌揭示炫光（红/绿）不显示（设计缺陷）

**现象**：鼠标选中/hover 一张牌时默认边缘光晕是**浅蓝**；此时若该牌发生贴牌揭示（贴错=红、贴对=绿），**炫光不显示**（仍是浅蓝），要移动光标（离开/重新 hover）才可能看到。

**根因**：`CardBlock._paint_glow()` 的优先级是 `flash > protected > actionable > hover`，**没有"揭示色"这一档**；`reveal(card, color)` 只是**直接** `_apply_glow_layers(color)` 设一次色，而 `set_hover`/`set_actionable`/`render` 重建后的重绘都会重新调用 `_paint_glow()`，把颜色覆盖回 actionable（金）/ hover（浅蓝）→ 揭示色被吞。

**修复**：把揭示色提升为**一等状态** `_reveal_color`：`reveal()` 设 `_reveal_color` 后统一走 `_paint_glow()`；`_paint_glow()` 优先级改为 **`flash > reveal > protected > hover > actionable`**；`setup()` 与 `restore()` 清空 `_reveal_color`。这样揭示炫光（绿/红/蓝）不会被选中/hover/重绘覆盖。

**后续调整（同优先级表）**：hover 提到 actionable **之上**——3D 可为抽牌堆/弃牌堆加金色"可点"高亮后，若不调整，金光会盖住准星悬停的浅蓝，玩家无法确认"是否对准了目标"。现顺序：不悬停时可点目标显**金色**，悬停时改显**浅蓝**（确认选中），揭示炫光仍最高。三档互不冲突（reveal > hover > actionable）。

**诊断方法**：`verify_table3d_exchange`「揭示炫光覆盖 hover 浅蓝」「hover 重绘不覆盖揭示炫光」「actionable 重绘不覆盖揭示炫光」「恢复后揭示炫光清除、回到 hover 浅蓝」。

## B39：常驻提示板吞掉牌桌点击（3D 卡牌完全点不了）

**现象**：3D 全息看板引入常驻提示板后，3D 模式下**卡牌/牌堆完全点击无反应**。

**根因**：`hint3d` 常驻可见（面板始终挂载 → `visible=true`），而 `main._table3d_click` 写成：
```
if _board_has_panel() or (hint3d != null and ... and hint3d.visible):
    var hit := _board_hit()
    if not hit.is_empty(): ...
    return      # ← 未命中看板也 return
```
该条件恒为真，且未命中看板时直接 `return`，导致点击永远走不到牌桌分发（`pick_center` → `slot/deck/discard/pending/hud`）。

**修复**：把点击判定改为显式路由 `_click_route(board_hit: bool)`：命中看板 → `"board"`；有模态面板 → `"blocked"`（不点穿）；否则 → `"table"`。`_table3d_click` 据此分发；常驻提示板可见不再等于"模态打开"。

**诊断方法**：`verify_board3d`「无模态时点击落到牌桌」「命中看板时点击给看板」「有模态时未命中看板则拦截（不点穿牌桌）」。

## B40：退出 3D 时看板对已释放模态面板崩溃

**现象**：3D 中打开过某模态（如 Joker 变换，随状态变化被自动关闭），随后按 F10/V 退出 3D 时抛错：
```
SCRIPT ERROR: Invalid type in function 'unmount_panel' ... argument 1 (previously freed)
at: Board3d.detach_all (board3d.gd) ← _set_table3d(false)
```

**根因**：模态面板被 `queue_free()` 后**仍留在 `Board3d._panels`**；退出 3D 时 `_set_table3d(false)` → `Board3d.detach_all()` 遍历 `_panels` 调用 `unmount_panel(control: Control)`，把已释放对象传给**类型化参数** → GDScript 参数类型检查在进入函数前即失败（"previously freed"）。触发点：`_on_joker_cancel`（Joker 面板随状态自动关闭）、以及任何 `queue_free` 但未从看板卸下的模态。

**修复**：① `Board3d` 增 `_prune_panels()`，在 `mount_panel`/`has_panel`/`detach_all` 前剔除 `is_instance_valid` 为假的条目（`detach_all` 只对存活面板调用 `unmount_panel`）；② `main` 增 `_unmount_modal(control)`，所有模态关闭点（结算/商店/Joker/比拼/重连）先卸下再 `queue_free`。

**诊断方法**：`verify_board3d`「已释放面板被清理：has_panel 为假」「detach_all 对已释放条目安全」。
