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
	_check("玩家下排可见 5", str(initial.players[0].slots[2].card.rank) == "5")
	_check("玩家下排可见 K", str(initial.players[0].slots[3].card.rank) == "K")
	_check("上排不可见", not initial.players[0].slots[0].has("card"))
	_check("对手牌不可见", not initial.players[1].slots[0].has("card"))

	var memorized: Dictionary = TutorialSteps.state_memorized()
	_check("记忆后下排盖回", not memorized.players[0].slots[2].has("card") and not memorized.players[0].slots[3].has("card"))

	var ready: Dictionary = TutorialSteps.state_ready_draw()
	_check("抽牌前无大牌", (ready.pending as Dictionary).is_empty())
	var drawn: Dictionary = TutorialSteps.state_drawn()
	_check("抽牌大牌=7", str(drawn.pending.rank) == "7")
	_check("抽牌后牌堆-1", int(drawn.draw_count) == int(initial.draw_count) - 1)

	var replaced: Dictionary = TutorialSteps.state_replaced()
	_check("替换后槽1有牌", not str(replaced.players[0].slots[1].card_id).is_empty())
	_check("弃牌顶=2", str(replaced.discard.rank) == "2")
	_check("弃牌后轮到对手", int(replaced.current_player) == 1)
	_check("替换开贴牌窗口", bool(replaced.slap_open))

	var opp: Dictionary = TutorialSteps.state_opponent_discard()
	_check("对手弃 5 → 弃牌顶=5", str(opp.discard.rank) == "5")
	_check("窗口跨到玩家回合", int(opp.current_player) == 0 and bool(opp.slap_open))

	var slapped: Dictionary = TutorialSteps.state_after_slap()
	_check("贴掉后玩家 3 张", int(slapped.players[0].count) == 3)
	_check("槽2 清空", str(slapped.players[0].slots[2].card_id).is_empty())
	_check("贴牌后窗口关闭", not bool(slapped.slap_open))

	var kong: Dictionary = TutorialSteps.state_kongbaya()
	_check("喊话者=玩家", int(kong.kong_caller) == 0)
	_check("喊话后轮到对手", int(kong.current_player) == 1)

	var over: Dictionary = TutorialSteps.state_game_over()
	_check("结算公开全部牌", over.players[0].slots[0].has("card") and over.players[1].slots[3].has("card"))
	var model: Dictionary = TutorialSteps.result_model()
	var last: Dictionary = model.rounds[model.rounds.size() - 1]
	_check("玩家总分 15", int(last.ranking[0].score) == 15)
	_check("玩家排名第一", int(last.ranking[0].id) == 0)
	_check("对手总分 26", int(last.ranking[1].score) == 26)

	_check("state_by_id 路由", str(TutorialSteps.state_by_id("drawn").pending.rank) == "7")

func _test_controller() -> void:
	var c := TutorialController.new()
	_check("初始步骤 intro", c.step_id() == "intro" and not c.is_interact())
	c.advance()
	_check("intro→memorize", c.step_id() == "memorize")
	c.advance()
	_check("memorize→draw", c.step_id() == "draw" and c.is_interact())
	var r_bad: Dictionary = c.pick({"kind": "discard"})
	_check("抽牌点弃牌堆被纠正", not bool(r_bad.ok) and c.step_id() == "draw")
	var r_draw: Dictionary = c.pick({"kind": "deck"})
	_check("抽牌点抽牌堆通过", bool(r_draw.ok) and c.step_id() == "replace")
	var r_no_arm: Dictionary = c.pick({"kind": "slot", "seat": 0, "slot": 1})
	_check("未点替换先点牌位被纠正", not bool(r_no_arm.ok) and c.step_id() == "replace")
	_check("点弃掉被纠正", not bool(c.action("discard").ok))
	var r_arm: Dictionary = c.action("replace")
	_check("点替换进入选牌", bool(r_arm.ok))
	_check("点错槽位被纠正", not bool(c.pick({"kind": "slot", "seat": 0, "slot": 0}).ok))
	var r_slot: Dictionary = c.pick({"kind": "slot", "seat": 0, "slot": 1})
	_check("替换成功→对手回合", bool(r_slot.ok) and c.step_id() == "opponent")
	c.advance()
	_check("对手→贴牌", c.step_id() == "slap")
	_check("贴错牌被纠正", not bool(c.pick({"kind": "slot", "seat": 0, "slot": 1}).ok))
	var r_slap: Dictionary = c.pick({"kind": "slot", "seat": 0, "slot": 2})
	_check("贴对→能力", bool(r_slap.ok) and c.step_id() == "abilities")
	c.advance()
	_check("能力→kongbaya", c.step_id() == "kongbaya")
	_check("先抽牌被纠正", not bool(c.pick({"kind": "deck"}).ok))
	var r_kong: Dictionary = c.pick({"kind": "hud", "action": "kongbaya"})
	_check("点铃铛通过→final", bool(r_kong.ok) and c.step_id() == "final")
	c.advance()
	_check("final→settle", c.step_id() == "settle")
	c.advance()
	_check("settle→summary", c.step_id() == "summary")
	c.advance()
	_check("summary 后完成", c.is_done())

	var c2 := TutorialController.new()
	c2.skip_step()
	_check("skip_step 前进一格", c2.step_id() == "memorize")
	c2.restart()
	_check("restart 回 intro", c2.step_id() == "intro" and not c2.is_done())
	_check("文本非空", TutorialText.title("draw") != "" and TutorialText.body("draw").contains("抽牌堆"))

func _test_view() -> void:
	var view = load("res://scenes/tutorial/tutorial_3d.tscn").instantiate()
	var completed := [false]
	view.completed.connect(func(): completed[0] = true)
	add_child(view)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("教学场景有 3D 桌", view.get_node_or_null("Table3D") != null)
	_check("教学场景有引导层", view.get_node_or_null("Overlay") != null)
	_check("初始步骤 intro", view.controller.step_id() == "intro")
	view.handle_continue()
	await get_tree().process_frame
	_check("继续→memorize", view.controller.step_id() == "memorize")
	view.handle_continue()
	_check("继续→draw", view.controller.step_id() == "draw")
	view.handle_pick({"kind": "deck"})
	_check("点抽牌堆→replace", view.controller.step_id() == "replace")
	view.handle_action("replace")
	view.handle_pick({"kind": "slot", "seat": 0, "slot": 1})
	_check("替换→opponent", view.controller.step_id() == "opponent")
	view.handle_continue()
	_check("opponent→slap", view.controller.step_id() == "slap")
	view.handle_pick({"kind": "slot", "seat": 0, "slot": 2})
	_check("贴牌→abilities", view.controller.step_id() == "abilities")
	view.handle_continue()
	_check("abilities→kongbaya", view.controller.step_id() == "kongbaya")
	view.handle_pick({"kind": "hud", "action": "kongbaya"})
	_check("hud→final", view.controller.step_id() == "final")
	view.handle_continue()
	view.handle_continue()
	_check("进入 summary", view.controller.step_id() == "summary")
	_check("summary 发 completed", completed[0])
	view.finish_skip()
	_check("finish_skip 发 closed", view.skip_requested)
	view.queue_free()

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
