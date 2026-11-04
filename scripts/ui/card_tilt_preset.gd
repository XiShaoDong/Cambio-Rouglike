class_name CardTiltPreset
extends RefCounted
## 2D 伪 3D 卡牌调参存档：沙盒保存、游戏内 CardView 读取同一份 cfg。
## 项目内路径优先；res:// 只读（导出包）时回退 user://。

const PROJECT_PATH := "res://assets/config/card_tilt_preset.cfg"
const USER_PATH := "user://card_tilt_preset.cfg"

const DEFAULTS := {
	"card_aspect": 1.4,
	"pad": 1.8,
	"max_tilt_deg": 14.0,
	"cam_dist": 3.0,
	"response": 9.0,
	"spec_strength": 0.55,
	"gloss_strength": 0.35,
	"rim_strength": 0.30,
	"shadow_strength": 0.35,
	"base_gain": 1.0,
	"gloss_tint": Color(0.62, 0.78, 1.0, 1.0),
	"light_dir": Vector3(-0.45, -0.35, 0.82),
}


## 读取存档并合并默认值；没有任何存档时返回空字典。
static func load_params(path: String = "") -> Dictionary:
	var cf := ConfigFile.new()
	for target in candidates(path):
		if cf.load(target) == OK:
			var out: Dictionary = DEFAULTS.duplicate(true)
			for key in DEFAULTS:
				out[key] = cf.get_value("card_tilt", key, DEFAULTS[key])
			return out
	return {}


## 保存参数；返回实际写入路径，失败返回空串。
static func save_params(values: Dictionary, path: String = "") -> String:
	var cf := ConfigFile.new()
	for key in DEFAULTS:
		cf.set_value("card_tilt", key, values.get(key, DEFAULTS[key]))
	for target in candidates(path):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target.get_base_dir()))
		if cf.save(target) == OK:
			return target
		push_warning("card_tilt: save preset to %s failed" % target)
	return ""


static func candidates(path: String) -> Array[String]:
	var out: Array[String] = []
	if not path.is_empty():
		out.append(path)
	else:
		out.append(PROJECT_PATH)
		out.append(USER_PATH)
	return out
