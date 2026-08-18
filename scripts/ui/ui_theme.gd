extends Node

## Central design-token store, CSS-style: scripts read colors/sizes via
## UITheme.color("...") instead of hard-coding them. Switch themes at runtime
## with UITheme.switch_theme("dark" | "light").

var current := "dark"

const TOKENS := {
	"dark": {
		# 背景层级
		"bg_table": Color("10151f"),
		"bg_surface": Color("22303f"),
		"bg_surface_alt": Color("2a3140"),
		"bg_elevated": Color("1c2633"),
		# 文字
		"text_primary": Color("e9effa"),
		"text_secondary": Color("aebbd0"),
		"text_muted": Color("8899aa"),
		"text_inverse": Color("10151f"),
		"text_on_card": Color("1a2230"),
		# 边框 / 分割线
		"border": Color("c9d1dc"),
		"border_strong": Color("8b96a8"),
		# 强调色（铃铛 / 高亮 / 牌背）
		"accent": Color("f6d77a"),
		"accent_soft": Color("f6d77a", 0.35),
		"accent_hover": Color("e6c45e"),
		"highlight_glow": Color("f6d77a"),
		# 语义色
		"success": Color("87d9a1"),
		"danger": Color("ff7b7b"),
		"warning": Color("f6d77a"),
		"info": Color("aebbd0"),
		# 玩家标识（当前玩家 / 其他玩家）
		"player_self_bg": Color("f6d77a", 0.35),
		"player_other_bg": Color("8899aa", 0.25),
		"player_self_text": Color("ffe9a8"),
		"player_other_text": Color("c9d4e0"),
		# 卡牌
		"card_face_bg": Color("f5f6f8"),
		"card_back_bg": Color("22303f"),
		"card_back_border": Color("ffffff"),
		"card_border": Color("c9d1dc"),
		"card_rank_red": Color("c0392b"),
		"card_rank_black": Color("1a2230"),
		"card_value": Color("4a5568"),
		"card_shadow": Color(0, 0, 0, 0.35),
	},
	"light": {
		# 背景层级（来自 docs/light_theme.css）
		"bg_table": Color("EDE6D6"),
		"bg_surface": Color("FFFDF8"),
		"bg_surface_alt": Color("F7F1E4"),
		"bg_elevated": Color("FFFFFF"),
		# 文字
		"text_primary": Color("3A362E"),
		"text_secondary": Color("8B8577"),
		"text_muted": Color("B5AF9E"),
		"text_inverse": Color("FFFDF8"),
		"text_on_card": Color("3A362E"),
		# 边框 / 分割线
		"border": Color("E3DBC8"),
		"border_strong": Color("CFC5AC"),
		# 强调色（陶土橙）
		"accent": Color("D9714F"),
		"accent_soft": Color("FBE3D8"),
		"accent_hover": Color("C4623F"),
		"highlight_glow": Color("D9714F"),
		# 语义色
		"success": Color("7A9B6E"),
		"danger": Color("C1604F"),
		"warning": Color("D9A441"),
		"info": Color("8B8577"),
		# 玩家标识
		"player_self_bg": Color("D9714F", 0.30),
		"player_other_bg": Color("8B8577", 0.20),
		"player_self_text": Color("3A362E"),
		"player_other_text": Color("6f6a5e"),
		# 卡牌
		"card_face_bg": Color("FFFDF8"),
		"card_back_bg": Color("D9714F"),
		"card_back_border": Color("C4623F"),
		"card_border": Color("E3DBC8"),
		"card_rank_red": Color("B04A36"),
		"card_rank_black": Color("3A362E"),
		"card_value": Color("8B8577"),
		"card_shadow": Color(0.227, 0.212, 0.18, 0.15),
	},
}

func color(key: String) -> Color:
	return TOKENS[current].get(key, Color.WHITE)

func switch_theme(theme_name: String) -> void:
	if TOKENS.has(theme_name):
		current = theme_name
