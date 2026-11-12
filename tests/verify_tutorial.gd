extends Node
## headless 单元测试：教程进度 / 固定牌序快照 / 步骤机 / 教学场景。

var failures := 0
var checks := 0


func _ready() -> void:
	await _run()
	print("=== TUTORIAL RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)


func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)


func _run() -> void:
	_test_progress()
	_test_steps()
	_test_controller()
	await _test_view()
	await _test_camera_ownership()
	await _test_main_integration()


func _test_progress() -> void:
	var p := "user://test_tutorial.cfg"
	DirAccess.remove_absolute(p)
	var store := TutorialProgress.new(p)
	store.load()
	_check("缺文件→未看", not store.seen and not store.completed)
	_check("5 条首局提示默认未看", TutorialProgress.HINTS.size() == 5 and not store.hint_done("first_slap"))
	_check("提示 id 齐全", TutorialProgress.HINTS == ["initial_peek", "first_turn", "first_slap", "first_shop", "first_settle"])
	store.mark_seen()
	store.mark_hint("first_slap")
	store.mark_completed()
	var store2 := TutorialProgress.new(p)
	store2.load()
	_check("seen 持久化", store2.seen)
	_check("completed 持久化", store2.completed)
	_check("hint 持久化", store2.hint_done("first_slap"))
	_check("其他 hint 仍未看", not store2.hint_done("first_shop"))
	store2.reset()
	var store3 := TutorialProgress.new(p)
	store3.load()
	_check("reset 清空", not store3.seen and not store3.completed and not store3.hint_done("first_slap"))
	DirAccess.remove_absolute(p)


func _test_steps() -> void:
	var initial: Dictionary = TutorialSteps.state_initial()
	_check("viewer=玩家", int(initial.viewer_id) == 0)
	_check("2 人桌", (initial.players as Array).size() == 2)
	_check("玩家上排 K/K 不可见", not initial.players[0].slots[0].has("card")
		and not initial.players[0].slots[1].has("card"))
	_check("玩家下排可见 2", str(initial.players[0].slots[2].card.rank) == "2")
	_check("玩家下排可见 10", str(initial.players[0].slots[3].card.rank) == "10")
	_check("对手 4 张 Q", (initial.players[1].slots as Array).size() == 4
		and str(initial.players[1].slots[0].card_id) == "o0"
		and not initial.players[1].slots[0].has("card"))

	var dealt: Dictionary = TutorialSteps.state_dealt()
	_check("发牌后全部背面", not dealt.players[0].slots[2].has("card")
		and not dealt.players[0].slots[3].has("card"))
	var memorized: Dictionary = TutorialSteps.state_memorized()
	_check("记忆后下排盖回", not memorized.players[0].slots[2].has("card")
		and not memorized.players[0].slots[3].has("card"))

	var ready: Dictionary = TutorialSteps.state_ready_draw()
	_check("抽牌前无大牌", (ready.pending as Dictionary).is_empty())
	var drawn: Dictionary = TutorialSteps.state_drawn_7()
	_check("抽牌大牌=7", str(drawn.pending.rank) == "7")
	_check("抽牌后进入决策阶段", int(drawn.phase) == GameState.Phase.TURN_DECISION)
	_check("抽牌后牌堆-1", int(drawn.draw_count) == 45)

	var replaced: Dictionary = TutorialSteps.state_player_replaced()
	_check("替换后槽3=7", str(replaced.players[0].slots[3].card_id) == "p4")
	_check("弃牌顶=10", str(replaced.discard.rank) == "10")
	_check("弃牌后轮到对手", int(replaced.current_player) == 1)
	_check("替换开贴牌窗口", bool(replaced.slap_open))

	var opp: Dictionary = TutorialSteps.state_opponent_replaced()
	_check("对手换牌后仍是 4 张 Q", int(opp.players[1].count) == 4
		and str(opp.players[1].slots[3].card_id) == "o4")
	_check("对手弃 Q → 弃牌顶=Q", str(opp.discard.rank) == "Q")
	_check("换牌后回到玩家", int(opp.current_player) == 0)

	var drawn9: Dictionary = TutorialSteps.state_drawn_9()
	_check("第二抽大牌=9", str(drawn9.pending.rank) == "9")
	var discarded9: Dictionary = TutorialSteps.state_player_discarded_9()
	_check("弃 9 后弃牌顶=9", str(discarded9.discard.rank) == "9")
	_check("弃牌开贴牌窗口", bool(discarded9.slap_open))

	var drew2: Dictionary = TutorialSteps.state_opponent_drew_2()
	_check("对手抽到 2 时只有 card_id", not drew2.pending.has("rank")
		and str(drew2.pending.card_id) == "o5")
	var opp2: Dictionary = TutorialSteps.state_opponent_discarded_2()
	_check("对手弃 2 → 弃牌顶=2", str(opp2.discard.rank) == "2")
	_check("贴牌窗口仍开启", bool(opp2.slap_open))

	var slapped: Dictionary = TutorialSteps.state_slap_success()
	_check("贴掉后玩家 3 张", int(slapped.players[0].count) == 3)
	_check("槽2 清空", str(slapped.players[0].slots[2].card_id).is_empty())
	_check("贴牌后窗口关闭", not bool(slapped.slap_open))

	_check("贴牌比赛前对手手里有 2（5 张）", int(opp2.players[1].count) == 5
		and str(opp2.players[1].slots[4].card_id) == "o10")
	var lost: Dictionary = TutorialSteps.state_race_lost()
	_check("阿岚先贴中（比赛失败态）", int(lost.players[1].count) == 4
		and not bool(lost.slap_open))

	var p1: Dictionary = TutorialSteps.state_opponent_penalty_1()
	_check("阿岚贴错罚 1 张→6 张", int(p1.players[1].count) == 6)
	var other: Dictionary = TutorialSteps.state_slap_other_window()
	_check("贴别人窗口：对手 6 张、弃牌顶 Q", int(other.players[1].count) == 6
		and str(other.discard.rank) == "Q" and bool(other.slap_open))
	_check("右下角 Q 在 slot3", str(other.players[1].slots[3].card_id) == "o3")
	var exch: Dictionary = TutorialSteps.state_slap_other_exchange()
	_check("贴中别人的 Q→交牌阶段", int(exch.phase) == GameState.Phase.SLAP_EXCHANGE
		and str(exch.players[1].slots[3].card_id).is_empty())
	var gift0: Dictionary = TutorialSteps.state_after_gift(0)
	_check("交牌后玩家 2 张、对手 6 张", int(gift0.players[0].count) == 2
		and int(gift0.players[1].count) == 6)
	_check("交出的牌进入对手 slot3", str(gift0.players[1].slots[3].card_id) == "p0")
	var over: Dictionary = TutorialSteps.state_game_over(0)
	_check("第 7 张→超限结算", int(over.players[1].count) == 7
		and int(over.phase) == GameState.Phase.GAME_OVER)
	_check("结算公开全部牌", over.players[0].slots[1].has("card")
		and over.players[1].slots[6].has("card"))

	var model: Dictionary = TutorialSteps.result_model(0)
	var last: Dictionary = model.rounds[model.rounds.size() - 1]
	_check("玩家总分 6", int(last.ranking[0].score) == 6)
	_check("玩家排名第一", int(last.ranking[0].id) == 0)
	_check("对手总分 44", int(last.ranking[1].score) == 44)
	_check("对手垫底", int(last.ranking[1].id) == 1)

	_check("state_by_id 路由", str(TutorialSteps.state_by_id("drawn_9").pending.rank) == "9")
	_check("固定牌序可复现", str(TutorialSteps.state_game_over(0).players[1].slots[1].card.rank) == "Q")


func _test_controller() -> void:
	var c := TutorialController.new()
	_check("初始步骤 intro_1", c.step_id() == "intro_1" and c.is_talk())
	c.advance()
	_check("intro_1→intro_2", c.step_id() == "intro_2")
	c.advance()
	_check("intro_2→intro_3", c.step_id() == "intro_3")
	c.advance()
	_check("intro_3→draw", c.step_id() == "draw" and c.is_interact())
	var r_bad: Dictionary = c.pick({"kind": "discard"})
	_check("抽牌点弃牌堆被纠正", not bool(r_bad.ok) and c.step_id() == "draw")
	var r_draw: Dictionary = c.pick({"kind": "deck"})
	_check("抽牌点抽牌堆通过", bool(r_draw.ok) and str(r_draw.effect) == "draw")
	_check("抽牌→replace", c.step_id() == "replace")
	_check("替换点错槽位被纠正", not bool(c.pick({"kind": "slot", "seat": 0, "slot": 0}).ok))
	var r_slot: Dictionary = c.pick({"kind": "slot", "seat": 0, "slot": 3})
	_check("替换正确→对手回合", bool(r_slot.ok) and str(r_slot.effect) == "replace"
		and c.step_id() == "opponent_replace")
	_check("自动步骤→换牌结果讲解", c.advance() and c.step_id() == "opponent_replace_explain")
	c.advance()
	_check("换牌讲解→draw2", c.step_id() == "draw2")
	c.pick({"kind": "deck"})
	_check("第二次抽牌→discard", c.step_id() == "discard")
	_check("弃牌点牌位被纠正", not bool(c.pick({"kind": "slot", "seat": 0, "slot": 2}).ok))
	var r_discard: Dictionary = c.pick({"kind": "discard"})
	_check("弃牌通过", bool(r_discard.ok) and str(r_discard.effect) == "discard")
	_check("弃牌→对手自动弃牌", c.step_id() == "opponent_discard")
	c.advance()
	_check("自动→贴牌讲解", c.step_id() == "slap_explain" and c.slap_mode() == "explain")
	c.advance()
	_check("讲解→贴牌比赛介绍", c.step_id() == "slap_race_intro" and c.is_talk())
	c.advance()
	_check("介绍→贴牌比赛", c.step_id() == "slap_prompt" and c.slap_mode() == "race")
	_check("贴错牌被纠正", not bool(c.pick({"kind": "slot", "seat": 0, "slot": 1}).ok))
	var r_slap: Dictionary = c.pick({"kind": "slot", "seat": 0, "slot": 2})
	_check("贴对→风险讲解", bool(r_slap.ok) and str(r_slap.effect) == "slap"
		and c.step_id() == "risk")
	c.advance()
	_check("风险→阿岚自己贴错演示", c.step_id() == "wrong_slap_demo"
		and c.end_state_id() == "opponent_penalty_1")
	c.advance()
	_check("贴错→贴别人牌准备", c.step_id() == "slap_other_setup"
		and c.end_state_id() == "slap_other_window")
	c.advance()
	_check("准备→阿岚提示", c.step_id() == "slap_other_tell")
	c.advance()
	_check("提示→贴阿岚的 Q", c.step_id() == "slap_other_click")
	_check("点自己牌被纠正", not bool(c.pick({"kind": "slot", "seat": 0, "slot": 0}).ok))
	var r_other: Dictionary = c.pick({"kind": "slot", "seat": 1, "slot": 3})
	_check("贴中阿岚的 Q→交牌", bool(r_other.ok) and str(r_other.effect) == "slap_other"
		and c.step_id() == "slap_other_exchange")
	var r_gift: Dictionary = c.pick({"kind": "slot", "seat": 0, "slot": 0})
	_check("选自己的牌交给阿岚", bool(r_gift.ok) and str(r_gift.effect) == "slap_gift"
		and c.gift_slot == 0 and c.step_id() == "slap_other_done")
	_check("交牌后玩家/对手张数", int(c.state().players[0].count) == 2
		and int(c.state().players[1].count) == 6)
	c.advance()
	_check("交牌→手牌上限", c.step_id() == "overflow")
	c.advance()
	_check("上限→超限演示", c.step_id() == "overflow_demo")
	_check("演示结束状态=game_over_gift", c.end_state_id() == "game_over_gift")
	c.advance()
	_check("超限→结算讲解", c.step_id() == "settle")
	c.advance()
	_check("结算→完成", c.step_id() == "summary" and c.is_summary())
	_check("summary 为终点，不可再推进", not c.advance() and c.step_id() == "summary")

	var c2 := TutorialController.new()
	c2.skip_step()
	_check("skip_step 前进一格", c2.step_id() == "intro_2")
	c2.restart()
	_check("restart 回开头", c2.step_id() == "intro_1" and not c2.is_done())
	_check("相机焦点字段", c2.focus() == "" and TutorialController.STEPS[3].get("focus", "") == "deck")
	_check("文本非空", TutorialText.title("draw") != "" and TutorialText.lines("draw").size() > 0)
	_check("台词覆盖关键规则", str(TutorialText.lines("slap_explain")[1]).contains("窗口"))


func _test_view() -> void:
	var view = load("res://scenes/tutorial/tutorial_3d.tscn").instantiate()
	view.instant_auto = true
	var completed := [false]
	var closed := [false]
	view.completed.connect(func(): completed[0] = true)
	view.closed.connect(func(): closed[0] = true)
	add_child(view)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("教学场景有 3D 桌", view.get_node_or_null("Table3D") != null)
	_check("教学场景有引导层", view.get_node_or_null("Overlay") != null)
	_check("教学场景有准星", view.get_node_or_null("Crosshair") != null)
	_check("教程手牌 hover 幅度已降 80%", is_equal_approx(float(view._table3d.hover_amp), 0.2))
	_check("初始步骤 intro_1", view.controller.step_id() == "intro_1")
	_check("开局先看到背面", not view._table3d.has_held_reveal(0, 2)
		and not view._table3d.has_held_reveal(0, 3))
	view.handle_continue()
	_check("点击后翻开下排且仍在 intro_1", view._table3d.has_held_reveal(0, 2)
		and view._table3d.has_held_reveal(0, 3) and view.controller.step_id() == "intro_1")
	view.handle_continue()
	_check("再点进入 intro_2", view.controller.step_id() == "intro_2")
	for i in 2:
		view.handle_continue()
	_check("记忆讲解→intro_3", view.controller.step_id() == "intro_3")
	_check("讲解后下排翻回背面", not view._table3d.has_held_reveal(0, 2)
		and not view._table3d.has_held_reveal(0, 3))
	for i in 1:
		view.handle_continue()
	_check("讲解结束→draw", view.controller.step_id() == "draw")
	await get_tree().create_timer(0.6).timeout
	_aim_focus(view)
	var deck_pick: Dictionary = view._table3d.pick_center()
	_check("中心准星可命中抽牌堆", str(deck_pick.get("kind", "")) == "deck")
	view.handle_pick({"kind": "deck"})
	_check("点抽牌堆→replace", view.controller.step_id() == "replace")
	var pend_xf: Transform3D = view._table3d.center_xform("pending")
	_check("大牌竖立而非平躺", absf(pend_xf.basis.z.y) > 0.9 and absf(pend_xf.basis.y.y) < 0.2)
	await get_tree().create_timer(0.6).timeout
	_aim_focus(view)
	var replace_pick: Dictionary = view._table3d.pick_center()
	_check("准星可命中要替换的手牌", str(replace_pick.get("kind", "")) == "slot"
		and int(replace_pick.get("seat", -1)) == 0 and int(replace_pick.get("slot", -1)) == 3)
	view.handle_pick({"kind": "slot", "seat": 0, "slot": 3})
	_check("替换→换牌结果讲解（自动步骤瞬时完成）", view.controller.step_id() == "opponent_replace_explain")
	for i in 2:
		view.handle_continue()
	_check("换牌讲解→draw2", view.controller.step_id() == "draw2")
	view.handle_pick({"kind": "deck"})
	_check("再抽→discard", view.controller.step_id() == "discard")
	await get_tree().create_timer(0.6).timeout
	_aim_focus(view)
	var discard_pick: Dictionary = view._table3d.pick_center()
	_check("准星可命中弃牌堆", str(discard_pick.get("kind", "")) == "discard")
	view.handle_pick({"kind": "discard"})
	_check("弃牌→slap_explain", view.controller.step_id() == "slap_explain")
	for i in 4:
		view.handle_continue()
	_check("讲解/比赛介绍结束→slap_prompt", view.controller.step_id() == "slap_prompt")
	_check("贴牌比赛已启动", view._slap_running and view._race_mode)
	await get_tree().create_timer(1.8).timeout
	_check("阿岚 1.5s 先贴中", view._race_locked)
	await get_tree().create_timer(2.4).timeout
	_check("比赛自动重试且仍在本步", view.controller.step_id() == "slap_prompt"
		and not view._race_locked)
	_aim_focus(view)
	var slap_pick: Dictionary = view._table3d.pick_center()
	_check("准星可命中要贴的 2", str(slap_pick.get("kind", "")) == "slot"
		and int(slap_pick.get("seat", -1)) == 0 and int(slap_pick.get("slot", -1)) == 2)
	view.handle_pick({"kind": "slot", "seat": 0, "slot": 2})
	_check("比阿岚快→risk", view.controller.step_id() == "risk")
	for i in 1:
		view.handle_continue()
	_check("risk→贴别人牌提示（两个自动步骤瞬时完成）",
		view.controller.step_id() == "slap_other_tell")
	_check("阿岚贴错后 6 张", int(view.controller.state().players[1].count) == 6)
	for i in 1:
		view.handle_continue()
	_check("提示→贴阿岚的 Q", view.controller.step_id() == "slap_other_click")
	_aim_focus(view)
	var opp_pick: Dictionary = view._table3d.pick_center()
	_check("准星可命中阿岚右下角的 Q", str(opp_pick.get("kind", "")) == "slot"
		and int(opp_pick.get("seat", -1)) == 1 and int(opp_pick.get("slot", -1)) == 3)
	view.handle_pick({"kind": "slot", "seat": 1, "slot": 3})
	_check("贴中阿岚的 Q→交牌", view.controller.step_id() == "slap_other_exchange")
	view.handle_pick({"kind": "slot", "seat": 0, "slot": 0})
	_check("交牌完成→slap_other_done", view.controller.step_id() == "slap_other_done")
	_check("交牌后玩家/对手张数", int(view.controller.state().players[0].count) == 2
		and int(view.controller.state().players[1].count) == 6)
	for i in 1:
		view.handle_continue()
	_check("交牌后→overflow", view.controller.step_id() == "overflow")
	for i in 2:
		view.handle_continue()
	_check("overflow→settle", view.controller.step_id() == "settle")
	view.handle_continue()
	_check("settle→summary", view.controller.step_id() == "summary")
	_check("summary 发 completed", completed[0])
	await get_tree().process_frame
	_check("结算页已挂载", view.get_node_or_null("TutorialSettlement") != null)
	view.finish_skip()
	_check("finish_skip 发 closed", closed[0] and view.skip_requested)
	view.queue_free()


func _test_camera_ownership() -> void:
	# 复现：先有一个"上一局"的 Table3D（相机留在场景里），再开教程。
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var old = load("res://scenes/ui/table3d.tscn").instantiate()
	old.name = "OldTable3D"
	main.add_child(old)
	await get_tree().process_frame
	var view = load("res://scenes/tutorial/tutorial_3d.tscn").instantiate()
	view.instant_auto = true
	add_child(view)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("教程相机接管当前视口", view.get_viewport().get_camera_3d()
		== view._table3d.camera.camera_node())
	view.queue_free()
	old.queue_free()
	main.queue_free()
	await get_tree().process_frame


func _aim_focus(view) -> void:
	var kind: String = view.controller.focus()
	if kind.is_empty():
		return
	view._table3d.camera.aim_at(view._focus_point(kind))


func _test_main_integration() -> void:
	var tp := "user://test_tutorial_main.cfg"
	DirAccess.remove_absolute(tp)
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.tutorial_progress = TutorialProgress.new(tp)
	main.tutorial_progress.load()
	main.tutorial_progress.reset()
	main._open_tutorial()
	await get_tree().process_frame
	_check("教程已打开", main.tutorial_active)
	_check("教程场景挂载", main.get_node_or_null("Tutorial3D") != null)
	_check("大厅隐藏", not main.lobby_root.visible)
	_check("mark_seen 已写", main.tutorial_progress.seen)
	_check("首局提示弹出", main._maybe_first_hint("first_slap"))
	_check("提示 HUD 可见", main._tip_hud != null and main._tip_hud.visible)
	_check("首局提示只弹一次", not main._maybe_first_hint("first_slap"))
	main._close_tutorial()
	await get_tree().process_frame
	_check("教程关闭", not main.tutorial_active and main.get_node_or_null("Tutorial3D") == null)
	_check("大厅恢复", main.lobby_root.visible)
	DirAccess.remove_absolute(tp)
	main.queue_free()
