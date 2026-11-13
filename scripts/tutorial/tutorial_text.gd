class_name TutorialText
extends RefCounted
## 教学文案集中处（便于审校/本地化）。一段话对应气泡里的一条台词。

const SPEAKER := "阿岚"

const TITLES := {
	"welcome": "欢迎来到 Kong",
	"rules_draw9": "抽一张牌",
	"rules_choices_hand": "选择：替换",
	"rules_choices_discard": "选择：弃牌",
	"rules_scoring": "点数就是分数",
	"rules_abilities": "卡牌能力",
	"rules_restart": "重新开始",
	"part2_peek": "正式开局",
	"part2_drawA": "抽牌",
	"part2_replace": "替换 10",
	"opponent_replace": "阿岚回合",
	"opponent_replace_explain": "阿岚换牌",
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
	"welcome": [
		"欢迎来到 Kong！靠记忆和策略减少卡牌点数或数量来获胜。\n规则很简单：开局可查看下方两张牌，记住它们，后面会考。点击任意位置翻开卡牌。",
	],
	"rules_draw9": [
		"每回合你会抽一张牌。点击高亮的抽牌堆，抽一张。",
	],
	"rules_choices_hand": [
		"抽到 9 后你有两个选择。第一：替换手牌，减少点数。",
	],
	"rules_choices_discard": [
		"第二：弃掉它，发挥它的能力。",
	],
	"rules_scoring": [
		"卡牌点数就是分数：A—Q 是 1—12 分，K 是 -1 分，Joker 是 0 分。按 Shift 可以开关牌序。",
	],
	"rules_abilities": [
		"卡牌能力可以按 Tab 打开手册，或瞄准卡牌查看。",
	],
	"rules_restart": [
		"好了，基本规则你都了解了。剩下的可以在对局中学习——让我们重新开始吧！",
	],
	"part2_peek": [
		"重新发牌，和刚才一样。点击翻开下方两张牌，记好再点 Ready。",
	],
	"part2_drawA": [
		"这次你先手。点击抽牌堆，抽一张。",
	],
	"part2_replace": [
		"抽到 A。你好像有一张 10 哦——点它，把 10 换成 A。",
	],
	"opponent_replace": [
		"我也换一张。",
	],
	"opponent_replace_explain": [
		"阿岚换了一张牌，把换下来的旧 Q 丢进了弃牌堆。",
		"现在轮到你抽牌。",
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
	"welcome": "点击翻开下方的两张牌（高亮）",
	"rules_draw9": "点击高亮的抽牌堆",
	"rules_choices_hand": "看：替换手牌",
	"rules_choices_discard": "看：弃牌堆",
	"rules_scoring": "按 Shift 查看牌序",
	"rules_abilities": "Tab 手册 / 瞄准卡牌",
	"rules_restart": "准备重新开始",
	"part2_peek": "点击翻开下方的两张牌（高亮）",
	"part2_drawA": "点击高亮的抽牌堆",
	"part2_replace": "点击你记得的那张 10",
	"opponent_replace": "阿岚的回合",
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
	"peek_need_flip": "先翻开下方的两张牌，再点 Ready！",
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
