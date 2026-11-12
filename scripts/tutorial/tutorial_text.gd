class_name TutorialText
extends RefCounted
## 教学文案集中处（便于审校/本地化）。

const TITLES := {
	"intro": "开局与记忆",
	"memorize": "记住下排两张",
	"draw": "抽一张牌",
	"replace": "替换手牌",
	"opponent": "对手回合",
	"slap": "抢贴牌",
	"abilities": "特殊牌能力",
	"kongbaya": "喊 Kongbaya",
	"final": "最终轮",
	"settle": "结算",
	"summary": "要点回顾",
}

const BODIES := {
	"intro": "你的 4 张牌全程背面朝上，只能靠记忆。",
	"memorize": "记住下排两张。之后除了用能力，不会再给你看。",
	"draw": "轮到你。点抽牌堆拿一张牌。",
	"replace": "把这张牌换进手牌。点「替换」，再点高亮的牌位。",
	"opponent": "别人的回合你不能操作，但贴牌窗口里可以随时抢。",
	"slap": "弃牌堆顶是 5。你记得哪张背面牌是 5？点它！",
	"abilities": "7/8 看自己一张；9/10 看别人一张；J 盲换；Q 看了再决定。",
	"kongbaya": "觉得自己的分够低了？点铃铛喊 Kongbaya。",
	"final": "对手完成最后一次行动，随后进入结算贴牌窗口。",
	"settle": "低分获胜：第一 +40，中间 +10，垫底 0 且 −1 生命。",
	"summary": "记住：牌是背面的、低分获胜、弃牌就开抢贴窗口、想收手就喊 Kongbaya。",
}

const TOAST := {
	"draw_need_deck": "这次先点抽牌堆。弃牌顶也能拿，但只能用来替换。",
	"replace_need_arm": "先点「替换」，再选牌位。",
	"replace_need_target": "把这张牌换进高亮的那个位置。",
	"replace_wrong_action": "先学替换，弃牌和能力本章跳过。",
	"slap_wrong": "贴错罚抽 1 张，窗口继续，可以再试。",
	"slap_wrong_target": "看看弃牌堆顶是几，再点你记得的那张。",
	"kong_need_bell": "先别抽，试着喊 Kongbaya。",
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

static func body(id: String) -> String:
	return str(BODIES.get(id, ""))

static func toast(id: String) -> String:
	return str(TOAST.get(id, ""))

static func hint(id: String) -> String:
	return str(HINTS.get(id, ""))
