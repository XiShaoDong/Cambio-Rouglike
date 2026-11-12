extends Node
## headless 单元测试：Sounds2 音效绑定 + AudioManager 事件 token。

var failures := 0
var checks := 0

func _ready() -> void:
	_test_resources()
	_test_events()
	print("=== AUDIO SFX RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _test_resources() -> void:
	_check("card-place 绑定", AudioManager.card_place_sfx != null)
	_check("card-slide 绑定", AudioManager.card_slide_sfx != null)
	_check("click 绑定", AudioManager.click_sfx != null)
	_check("countdown 绑定", AudioManager.countdown_sfx != null)
	_check("notification 绑定", AudioManager.notification_sfx != null)
	_check("slap-fail 绑定", AudioManager.slap_fail_sfx != null)
	_check("slap-success 绑定", AudioManager.slap_success_sfx != null)
	_check("deal 绑定", AudioManager.deal_sfx != null)
	_check("抽牌=card-slide-8", str(AudioManager.card_slide_sfx.resource_path).ends_with("card-slide-8.ogg"))
	_check("点击=tech-click", str(AudioManager.click_sfx.resource_path).ends_with("tech-click.wav"))
	_check("发牌=card-shuffle", str(AudioManager.deal_sfx.resource_path).ends_with("card-shuffle.ogg"))
	_check("deal 只播 1.8s", is_equal_approx(AudioManager.DEAL_PLAY_SECONDS, 1.8))
	_check("播放器池 >= 10", AudioManager.POOL_SIZE >= 10)
	_check("countdown 跳过开头 1s", is_equal_approx(AudioManager.COUNTDOWN_START_SEC, 1.0))
	_check("countdown 播 3s", is_equal_approx(AudioManager.COUNTDOWN_PLAY_SECONDS, 3.0))

func _test_events() -> void:
	AudioManager.play_draw()
	_check("draw token", AudioManager.last_event == "draw")
	AudioManager.play_discard()
	_check("discard token", AudioManager.last_event == "discard")
	AudioManager.play_slap_success()
	_check("slap_success token", AudioManager.last_event == "slap_success")
	AudioManager.play_slap_fail()
	_check("slap_fail token", AudioManager.last_event == "slap_fail")
	AudioManager.play_trigger()
	_check("trigger token", AudioManager.last_event == "trigger")
	AudioManager.play_countdown()
	_check("countdown token", AudioManager.last_event == "countdown")
	AudioManager.stop_countdown()
	_check("stop_countdown 不报错", true)
	AudioManager.play_select()
	_check("select token", AudioManager.last_event == "select")
	AudioManager.play_flip()
	_check("flip token", AudioManager.last_event == "flip")
	AudioManager.play_flip_quick()
	_check("flip_quick token", AudioManager.last_event == "flip_quick")
	AudioManager.play_fly()
	_check("fly token", AudioManager.last_event == "fly")
	AudioManager.play_deal_shuffle()
	_check("deal_shuffle token", AudioManager.last_event == "deal_shuffle")
	AudioManager.stop_deal_shuffle()
	_check("stop_deal_shuffle 不报错", true)
