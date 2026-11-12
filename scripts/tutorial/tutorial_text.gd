class_name TutorialText
extends RefCounted
## 教学文案集中处（便于审校/本地化）。一段话对应气泡里的一条台词。

const SPEAKER := "阿岚"

const TITLES := {
	"intro_1": "开局与记忆",
	"intro_2": "点数越小越好",
	"intro_3": "记住下排两张",
	"draw": "抽牌",
	"replace": "替换手牌",
	"opponent_replace": "对手回合",
	"opponent_replace_explain": "对手换牌结果",
	"draw2": "再抽一张",
	"discard": "弃牌",
	"opponent_discard": "对手弃牌",
	"slap_explain": "贴牌规则",
	"slap_race_intro": "贴牌比赛",
	"slap_prompt": "抢贴牌",
	"risk": "贴牌风险",
	"wrong_slap_demo": "阿岚贴错了",
	"slap_other_setup": "贴别人的牌",
	"slap_other_tell": "阿岚的提示",
	"slap_other_click": "贴阿岚的 Q",
	"slap_other_exchange": "交出一张牌",
	"slap_other_done": "交牌完成",
	"overflow": "手牌上限",
	"overflow_demo": "超过 6 张",
	"settle": "结算",
	"summary": "教程完成",
}

const LINES := {
	"intro_1": [
		"开局你会拿到 4 张牌，只有下排两张会翻开。点击任意位置翻开它们。",
		"移动鼠标可以环视；准星对准目标后按左键。记住下排两张的点数和位置。",
	],
	"intro_2": [
		"点数越小越好：A 是 1 分，K 是 -1 分，Joker 是 0 分。",
		"2 到 10 就是牌面点数，J 和 Q 都是 10 分。",
	],
	"intro_3": [
		"现在它们盖回去了，接下来只能靠你的记忆。",
	],
	"draw": [
		"轮到你了。点击高亮的抽牌堆，抽一张牌。",
	],
	"replace": [
		"抽到 7。你记得下排有一张 10，比 7 大。",
		"点击那张 10，把它替换掉。",
	],
	"opponent_replace": [
		"我也换一张。",
	],
	"opponent_replace_explain": [
		"阿岚把换下来的旧 Q 丢进弃牌堆，贴牌窗口打开了。",
		"你手里没有 Q，所以这次不贴。轮到你抽牌。",
	],
	"draw2": [
		"又轮到你了，再点抽牌堆抽一张。",
	],
	"discard": [
		"这张 9 你不想要。点击弃牌堆，把抽到的牌弃掉。",
	],
	"opponent_discard": [
		"对手也抽了一张……是一张 2，他不要，弃掉了。",
	],
	"slap_explain": [
		"看弃牌堆——现在是张 2。",
		"贴牌就是：当弃牌堆出现和你手里某张牌相同的点数，在窗口结束前点你那张牌，把它丢出去。",
		"只有最快的玩家才能贴中。先记住，现在还不开始计时。",
	],
	"slap_race_intro": [
		"我也有一张 2。看谁先贴上！",
	],
	"slap_prompt": [
		"快！点你手里的 2！",
	],
	"risk": [
		"不过贴牌也有风险：贴错了会公开这张手牌，还要被罚一张牌。",
	],
	"wrong_slap_demo": [
		"轮到我……我记得我也有一张 2 来着。",
	],
	"slap_other_setup": [
		"除了贴自己的牌，也可以贴别人的牌。",
		"我换一张 Q 出去……",
	],
	"slap_other_tell": [
		"我偷偷告诉你，我右下角还有一张 Q。点它试试。",
	],
	"slap_other_click": [
		"就是这张 Q，点它。",
	],
	"slap_other_exchange": [
		"不过由于你贴了别人的牌，你可以选一张自己的牌给我。",
	],
	"slap_other_done": [
		"这张牌归我了，谢谢！",
	],
	"overflow": [
		"当任何玩家手牌超过 6 张，本局立即结束。",
		"阿岚现在 6 张，再罚一张就会结束。",
	],
	"overflow_demo": [
		"6 张……7 张。超过上限，本局结束。",
	],
	"settle": [
		"结算时，手牌点数总和最小的玩家获胜，最大的玩家扣 1 点生命。",
	],
	"summary": [
		"记住：低分获胜、弃牌就开抢贴窗口、贴错要罚牌、超过 6 张直接结算。",
	],
}

const TASKS := {
	"intro_1": "记住下排两张牌",
	"intro_2": "目标：手牌点数总和尽量小",
	"intro_3": "目标：手牌点数总和尽量小",
	"draw": "点击高亮的抽牌堆",
	"replace": "点击你记得的那张 10",
	"opponent_replace": "对手的回合",
	"opponent_replace_explain": "看阿岚换牌的结果",
	"draw2": "点击高亮的抽牌堆",
	"discard": "点击弃牌堆弃掉 9",
	"opponent_discard": "对手的回合",
	"slap_explain": "贴牌窗口已开启（讲解中，不计时）",
	"slap_race_intro": "听阿岚说",
	"slap_prompt": "比阿岚快：点你手里的 2",
	"risk": "听讲解",
	"wrong_slap_demo": "看阿岚贴错",
	"slap_other_setup": "看阿岚换牌",
	"slap_other_tell": "听阿岚提示",
	"slap_other_click": "点阿岚右下角的 Q",
	"slap_other_exchange": "选一张自己的牌交给阿岚",
	"slap_other_done": "看结果",
	"overflow": "手牌超过 6 张立即结束",
	"overflow_demo": "手牌超过 6 张立即结束",
	"settle": "最小分获胜，最大分扣 1 生命",
	"summary": "",
}

const TOAST := {
	"draw_wrong": "请跟随提示：点高亮的抽牌堆。",
	"replace_wrong": "请跟随提示：点你记得的那张 10。",
	"discard_wrong": "请跟随提示：点弃牌堆。",
	"slap_wrong": "请跟随提示：点你手里那张 2。",
	"slap_other_hint": "请跟随提示：点阿岚右下角亮起的 Q。",
	"slap_gift_hint": "请跟随提示：选一张自己的牌交给阿岚。",
	"race_lost": "只有最快翻开牌的人才可以成功贴牌哦，再试一次！",
	"slap_timeout": "窗口结束了，再来一次！",
	"wait": "先完成当前这一步。",
}

const HINTS := {
	"initial_peek": "看下排两张，记住它们，之后不会再显示。",
	"first_turn": "点抽牌堆或弃牌堆顶。",
	"first_slap": "弃牌堆顶是 X，记得哪张是 X 就点它抢贴。",
	"first_shop": "货币可买遗物/道具卡；遗物只对持有者生效。",
	"first_settle": "低分获胜；垫底扣 1 生命。",
}

static func title(id: String) -> String:
	return str(TITLES.get(id, ""))


static func lines(id: String) -> Array:
	return (LINES.get(id, []) as Array).duplicate()


static func task(id: String) -> String:
	return str(TASKS.get(id, ""))


static func toast(id: String) -> String:
	return str(TOAST.get(id, ""))


static func hint(id: String) -> String:
	return str(HINTS.get(id, ""))
