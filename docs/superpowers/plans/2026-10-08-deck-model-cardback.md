# 抽牌堆模型卡背拟合（沙盒）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用一个纯 Godot 着色器把 `DeckCardPile.glb` 渲染成"一摞 back07 卡背"的真实堆叠观感，先在独立沙盒里可调。

**Architecture:** `DeckBackConfig`（参数）+ `DeckBackMath`（可测纯函数）+ `deck_back_projection.gdshader`（GLSL 镜像）+ `deck_model_sandbox`（加载模型/套材质/环视/调参面板）。着色器按**模型局部坐标**做 XZ 平面投影（绕过模型那套乱 UV），逐层 hash 偏移 + 侧面/边框 + 层高 AO 得到堆叠观感。

**Tech Stack:** Godot 4.6.2（`.eshader`/GDScript）；headless 单测；Blender 5.2 CLI（仅后续减面用，本计划不用）。

## Global Constraints

- 引擎：Godot `4.6.2`。测试运行：`/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_deck_back.tscn`。
- **零改动**：`scripts/core/*`、`scripts/net/*`、`main.gd`、`scripts/ui/table3d_view.gd`、`scripts/ui/card_block.gd`、`scenes/ui/table3d.tscn`、2D 卡牌相关、现有测试与现有沙盒。
- GDScript **没有 `fract()`** 全局函数：需要取小数用 `fposmod(x, 1.0)`（着色器里 GLSL 可用 `fract()`）。
- 所有新文件放 `res://` 下；沿用仓库 `Config（KEYS/to_dict/validate）+ Math（纯函数）+ Sandbox + verify 测试` 惯例。
- 测试脚本结构沿用 `tests/verify_card_fly.gd`（`_check(name, ok)` + 末尾打印 `=== ... RESULT: n/n passed ===` + `quit(1 if failures else 0)`）。
- **提交需用户明确同意**（本仓库规则）：本计划每个 Task 末尾的 commit 步骤仅在同一会话用户已授权提交时执行；否则跳过提交、保留改动。

---

### Task 1: `DeckBackConfig` 参数类

**Files:**
- Create: `scripts/ui/deck_back_config.gd`
- Create: `tests/verify_deck_back.gd`
- Create: `tests/verify_deck_back.tscn`

**Interfaces:**
- Produces: `class_name DeckBackConfig extends RefCounted`
  - 字段（默认见 spec §7）：`project_card_size: Vector2(1.86,1.90)`、`rotation_deg: float=0.0`、`layer_height: float=0.01`、`layer_offset: Vector2(0.03,0.02)`、`layer_shuffle: float=1.0`、`layer_ao: float=0.25`、`edge_darken: float=0.35`、`edge_softness: float=0.40`、`model_height: float=0.25`、`tint: Color=Color.WHITE`、`tile: bool=false`
  - `const KEYS: Array`（含上述 11 个键，顺序同 spec）
  - `func to_dict() -> Dictionary`
  - `func validate() -> Array`（返回非法字段名）

- [ ] **Step 1: 写失败测试** — 创建 `tests/verify_deck_back.gd`

```gdscript
extends Node
## headless 单元测试：抽牌堆模型卡背投影（配置 / 纯数学 / 着色器 / 沙盒）。

var failures := 0
var checks := 0

func _ready() -> void:
	await _run()
	print("=== DECK BACK RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _run() -> void:
	_test_config()

func _test_config() -> void:
	var c := DeckBackConfig.new()
	_check("config 默认值合法", c.validate().is_empty())
	_check("config to_dict 键数", c.to_dict().size() == DeckBackConfig.KEYS.size())
	_check("config 默认 project_card_size", (c.project_card_size as Vector2).is_equal_approx(Vector2(1.86, 1.90)))
	_check("config 默认 layer_height", is_equal_approx(c.layer_height, 0.01))
	var bad := DeckBackConfig.new()
	bad.project_card_size = Vector2(-1.0, 1.0)
	_check("负尺寸被抓", bad.validate().has("project_card_size"))
	var bad2 := DeckBackConfig.new()
	bad2.layer_ao = 1.5
	_check("AO>1 被抓", bad2.validate().has("layer_ao"))
	var bad3 := DeckBackConfig.new()
	bad3.layer_height = 0.0
	_check("layer_height=0 被抓", bad3.validate().has("layer_height"))
```

- [ ] **Step 2: 写测试场景** — 创建 `tests/verify_deck_back.tscn`

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tests/verify_deck_back.gd" id="1_test"]

[node name="VerifyDeckBack" type="Node"]
script = ExtResource("1_test")
```

- [ ] **Step 3: 运行，确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_deck_back.tscn`
Expected: 解析错误 / `DeckBackConfig` 未定义（FAIL 或编译失败）。

- [ ] **Step 4: 实现** — 创建 `scripts/ui/deck_back_config.gd`

```gdscript
class_name DeckBackConfig
extends RefCounted
## 抽牌堆模型卡背投影参数（集中配置；代码不出现散落魔法数）。
## 与 assets/shaders/deck_back_projection.gdshader 的 uniform 同名一一对应。

var project_card_size := Vector2(1.86, 1.90)  # 一张卡背在世界 XZ 的投影尺寸
var rotation_deg := 0.0                       # 卡背绕 Y 旋转
var layer_height := 0.01                      # 每层堆叠厚度（≈模型 Y 步进）
var layer_offset := Vector2(0.03, 0.02)       # 逐层 XZ 偏移幅度
var layer_shuffle := 1.0                      # 逐层偏移随机种子
var layer_ao := 0.25                          # 最底层相对顶层压暗比例 [0,1]
var edge_darken := 0.35                       # 卡边相对边框色压暗 [0,1]
var edge_softness := 0.40                     # 顶面↔侧面法线过渡带
var model_height := 0.25                      # 模型高度（AO 归一化基准）
var tint := Color.WHITE                       # 整体染色
var tile := false                             # 是否平铺（备用观感）

const KEYS := [
	"project_card_size", "rotation_deg", "layer_height", "layer_offset",
	"layer_shuffle", "layer_ao", "edge_darken", "edge_softness",
	"model_height", "tint", "tile",
]

func to_dict() -> Dictionary:
	var d := {}
	for k in KEYS:
		d[k] = get(k)
	return d

## 返回非法字段名数组。
func validate() -> Array:
	var bad: Array = []
	var size := project_card_size as Vector2
	if not (is_finite(size.x) and is_finite(size.y)) or size.x <= 0.0 or size.y <= 0.0:
		bad.append("project_card_size")
	if not is_finite(layer_height) or layer_height <= 0.0:
		bad.append("layer_height")
	if not is_finite(model_height) or model_height <= 0.0:
		bad.append("model_height")
	if not is_finite(rotation_deg):
		bad.append("rotation_deg")
	var off := layer_offset as Vector2
	if not (is_finite(off.x) and is_finite(off.y)):
		bad.append("layer_offset")
	if not is_finite(layer_shuffle):
		bad.append("layer_shuffle")
	for k in ["layer_ao", "edge_darken", "edge_softness"]:
		var v := float(get(k))
		if not is_finite(v) or v < 0.0 or v > 1.0:
			bad.append(k)
	return bad
```

- [ ] **Step 5: 运行，确认通过**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_deck_back.tscn`
Expected: `=== DECK BACK RESULT: 7/7 passed ===`

- [ ] **Step 6: 提交**（仅在用户已授权提交时）

```bash
git add scripts/ui/deck_back_config.gd tests/verify_deck_back.gd tests/verify_deck_back.tscn
git commit -m "feat(deck): add DeckBackConfig for deck model cardback"
```

---

### Task 2: `DeckBackMath` 分层核心（hash22 / layer_index / layer_offset）

**Files:**
- Create: `scripts/ui/deck_back_math.gd`
- Modify: `tests/verify_deck_back.gd`

**Interfaces:**
- Produces: `class_name DeckBackMath extends RefCounted`
  - `static func hash22(v: Vector2) -> Vector2`（确定性，分量 ∈ [0,1)）
  - `static func layer_index(y: float, layer_height: float) -> float`（`floor`，`layer_height<=0` 返回 0）
  - `static func layer_offset(layer_index: float, layer_offset: Vector2, shuffle: float) -> Vector2`（∈ `[-layer_offset, layer_offset]`）

- [ ] **Step 1: 追加失败测试** — 在 `_run()` 加 `_test_layering()`，并追加函数：

```gdscript
func _run() -> void:
	_test_config()
	_test_layering()

func _test_layering() -> void:
	var h1 := DeckBackMath.hash22(Vector2(3.0, 1.0))
	var h2 := DeckBackMath.hash22(Vector2(3.0, 1.0))
	_check("hash22 确定性", h1.is_equal_approx(h2))
	_check("hash22 范围 [0,1)", h1.x >= 0.0 and h1.x < 1.0 and h1.y >= 0.0 and h1.y < 1.0)
	_check("hash22 换种子变值", not DeckBackMath.hash22(Vector2(3.0, 2.0)).is_equal_approx(h1))
	_check("layer_index y=0", is_equal_approx(DeckBackMath.layer_index(0.0, 0.01), 0.0))
	_check("layer_index y=0.011", is_equal_approx(DeckBackMath.layer_index(0.011, 0.01), 1.0))
	_check("layer_index layer_height=0 兜底", is_equal_approx(DeckBackMath.layer_index(0.5, 0.0), 0.0))
	var o := Vector2(0.03, 0.02)
	var a := DeckBackMath.layer_offset(2.0, o, 1.0)
	var b := DeckBackMath.layer_offset(2.0, o, 1.0)
	_check("layer_offset 同层同值", a.is_equal_approx(b))
	_check("layer_offset 不同层不同值", not DeckBackMath.layer_offset(2.0, o, 1.0).is_equal_approx(DeckBackMath.layer_offset(5.0, o, 1.0)))
	_check("layer_offset 幅度受限", absf(a.x) <= o.x + 0.0001 and absf(a.y) <= o.y + 0.0001)
	_check("layer_offset 零幅度为零", DeckBackMath.layer_offset(4.0, Vector2.ZERO, 1.0).is_equal_approx(Vector2.ZERO))
```

- [ ] **Step 2: 运行，确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_deck_back.tscn`
Expected: `DeckBackMath` 未定义 → 编译失败。

- [ ] **Step 3: 实现** — 创建 `scripts/ui/deck_back_math.gd`

```gdscript
class_name DeckBackMath
extends RefCounted
## 抽牌堆卡背投影纯函数（着色器 GLSL 逻辑的可测镜像）。
## 注意：GDScript 无 fract()，用 fposmod(x, 1.0)。着色器同名函数用 GLSL fract()。

## 确定性 2D hash，输出分量 ∈ [0,1)。与 deck_back_projection.gdshader 的 hash22 同式。
static func hash22(v: Vector2) -> Vector2:
	return Vector2(
		fposmod(sin(v.x * 127.1 + v.y * 311.7) * 43758.5453, 1.0),
		fposmod(sin(v.x * 269.5 + v.y * 183.3) * 28001.8384, 1.0))

## 层索引：y / layer_height 向下取整；layer_height<=0 兜底为 0。
static func layer_index(y: float, layer_height: float) -> float:
	if layer_height <= 0.0:
		return 0.0
	return floor(y / layer_height)

## 逐层确定性偏移：同层同值、不同层不同，幅度受 layer_offset 缩放，落在 [-layer_offset, +layer_offset]。
static func layer_offset(layer_index_value: float, layer_offset: Vector2, shuffle: float) -> Vector2:
	var h := hash22(Vector2(layer_index_value, shuffle))
	return (h * 2.0 - Vector2.ONE) * layer_offset
```

- [ ] **Step 4: 运行，确认通过**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_deck_back.tscn`
Expected: `=== DECK BACK RESULT: 18/18 passed ===`

- [ ] **Step 5: 提交**（仅用户已授权时）

```bash
git add scripts/ui/deck_back_math.gd tests/verify_deck_back.gd
git commit -m "feat(deck): add DeckBackMath layering (hash/index/offset)"
```

---

### Task 3: `DeckBackMath` 投影与明暗（project_uv / side_blend / layer_ao_factor / compose）

**Files:**
- Modify: `scripts/ui/deck_back_math.gd`
- Modify: `tests/verify_deck_back.gd`

**Interfaces:**
- Produces（追加到 `DeckBackMath`）：
  - `static func project_uv(local: Vector3, card_size: Vector2, rotation_deg: float) -> Vector2`（含 +0.5 居中；中心→(0.5,0.5)）
  - `static func side_blend(normal_y: float, edge_softness: float) -> float`（∈[0,1]，`normal_y=1`→1）
  - `static func layer_ao_factor(y: float, model_height: float, layer_ao: float) -> float`（`y=model_height`→1，`y=0`→`1-layer_ao`）
  - `static func compose(local: Vector3, normal: Vector3, cfg: Dictionary) -> Dictionary` → `{uv, tile_uv, side, ao}`

- [ ] **Step 1: 追加失败测试** — 加 `_test_projection()` 到 `_run()`：

```gdscript
func _run() -> void:
	_test_config()
	_test_layering()
	_test_projection()

func _test_projection() -> void:
	var size := Vector2(1.86, 1.90)
	var uv0 := DeckBackMath.project_uv(Vector3(0.0, 0.0, 0.0), size, 0.0)
	_check("project_uv 中心→0.5", uv0.is_equal_approx(Vector2(0.5, 0.5)))
	var uvx := DeckBackMath.project_uv(Vector3(size.x, 0.0, 0.0), size, 0.0)
	_check("project_uv x=size → u=1.5", is_equal_approx(uvx.x, 1.5))
	var uv90 := DeckBackMath.project_uv(Vector3(1.0, 0.0, 0.0), size, 90.0)
	_check("project_uv 90° 把 +X 转到 +Z", is_equal_approx(uv90.y, 0.5 + 1.0 / size.y) and absf(uv90.x - 0.5) < 0.0001)
	_check("side_blend 朝上=1", is_equal_approx(DeckBackMath.side_blend(1.0, 0.4), 1.0))
	_check("side_blend 竖直=0", is_equal_approx(DeckBackMath.side_blend(0.0, 0.4), 0.0))
	_check("side_blend 单调", DeckBackMath.side_blend(0.1, 0.4) < DeckBackMath.side_blend(0.3, 0.4))
	_check("ao 顶部=1", is_equal_approx(DeckBackMath.layer_ao_factor(0.25, 0.25, 0.25), 1.0))
	_check("ao 底部=1-ao", is_equal_approx(DeckBackMath.layer_ao_factor(0.0, 0.25, 0.25), 0.75))
	_check("ao 单调", DeckBackMath.layer_ao_factor(0.05, 0.25, 0.25) < DeckBackMath.layer_ao_factor(0.2, 0.25, 0.25))
	var cfg := DeckBackConfig.new().to_dict()
	var c := DeckBackMath.compose(Vector3(0.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), cfg)
	_check("compose 顶部中心 uv≈0.5", absf((c["uv"] as Vector2).x - 0.5) < 0.2)
	_check("compose 朝上 side=1", is_equal_approx(c["side"] as float, 1.0))
	_check("compose 底部 ao=1-layer_ao", absf((c["ao"] as float) - 0.75) < 0.001)
	var off_cfg := DeckBackConfig.new().to_dict()
	off_cfg["tile"] = true
	var ct := DeckBackMath.compose(Vector3(1.5, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), off_cfg)
	_check("compose tile 后 uv∈[0,1)", (ct["tile_uv"] as Vector2).x >= 0.0 and (ct["tile_uv"] as Vector2).x < 1.0)
```

- [ ] **Step 2: 运行，确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_deck_back.tscn`
Expected: `project_uv` 等未定义 → 编译失败/F AIL。

- [ ] **Step 3: 实现** — 追加到 `scripts/ui/deck_back_math.gd`

```gdscript
## XZ 平面投影：绕 Y 旋转 rotation_deg 后按 card_size 归一化并居中（+0.5）。
static func project_uv(local: Vector3, card_size: Vector2, rotation_deg: float) -> Vector2:
	var a := deg_to_rad(rotation_deg)
	var c := cos(a)
	var s := sin(a)
	var x := local.x * c - local.z * s
	var z := local.x * s + local.z * c
	return Vector2(x / maxf(card_size.x, 0.0001) + 0.5, z / maxf(card_size.y, 0.0001) + 0.5)

## 顶面↔侧面混合权重：法线越朝上越接近 1。
static func side_blend(normal_y: float, edge_softness: float) -> float:
	var e := maxf(edge_softness, 0.0001)
	return smoothstep(0.0, e, clampf(normal_y, 0.0, 1.0))

## 层高 AO：y=model_height→1（顶层不压暗），y=0→1-layer_ao。
static func layer_ao_factor(y: float, model_height: float, layer_ao: float) -> float:
	var depth := 1.0 - clampf(y / maxf(model_height, 0.0001), 0.0, 1.0)
	return 1.0 - layer_ao * depth

## 端到端：返回 {uv, tile_uv, side, ao}。
static func compose(local: Vector3, normal: Vector3, cfg: Dictionary) -> Dictionary:
	var size := cfg["project_card_size"] as Vector2
	var li := layer_index(local.y, cfg["layer_height"])
	var off := layer_offset(li, cfg["layer_offset"], cfg["layer_shuffle"])
	var uv := project_uv(local, size, cfg["rotation_deg"]) + off
	var tile_uv := Vector2(fposmod(uv.x, 1.0), fposmod(uv.y, 1.0)) if bool(cfg["tile"]) else uv
	return {
		"uv": uv,
		"tile_uv": tile_uv,
		"side": side_blend(normal.y, cfg["edge_softness"]),
		"ao": layer_ao_factor(local.y, cfg["model_height"], cfg["layer_ao"]),
	}
```

- [ ] **Step 4: 运行，确认通过**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_deck_back.tscn`
Expected: `=== DECK BACK RESULT: 30/30 passed ===`（数量以实际为准，须全绿）

- [ ] **Step 5: 提交**（仅用户已授权时）

```bash
git add scripts/ui/deck_back_math.gd tests/verify_deck_back.gd
git commit -m "feat(deck): add DeckBackMath projection/shading/compose"
```

---

### Task 4: 着色器 `deck_back_projection.gdshader`

**Files:**
- Create: `assets/shaders/deck_back_projection.gdshader`
- Modify: `tests/verify_deck_back.gd`

**Interfaces:**
- Consumes: `DeckBackConfig.KEYS`（uniform 名一致）
- Produces: `res://assets/shaders/deck_back_projection.gdshader`（`shader_type spatial; render_mode cull_disabled;`）
  - uniforms：`back_tex`、`project_card_size`、`rotation_deg`、`layer_height`、`layer_offset`、`layer_shuffle`、`layer_ao`、`edge_darken`、`edge_softness`、`model_height`、`tint`、`tile`

- [ ] **Step 1: 追加失败测试** — 加 `_test_shader()` 到 `_run()`：

```gdscript
func _test_shader() -> void:
	var sh := load("res://assets/shaders/deck_back_projection.gdshader") as Shader
	_check("shader 可加载", sh != null)
	if sh == null:
		return
	var names := {}
	for u in sh.get_shader_uniform_list():
		names[u["name"]] = true
	for k in DeckBackConfig.KEYS:
		_check("shader uniform %s" % k, names.has(k))
```

- [ ] **Step 2: 运行，确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_deck_back.tscn`
Expected: `shader 可加载` FAIL。

- [ ] **Step 3: 实现** — 创建 `assets/shaders/deck_back_projection.gdshader`

```glsl
shader_type spatial;
render_mode cull_disabled;

// 抽牌堆卡背投影：按模型局部坐标做 XZ 平面投影（绕过模型自带乱 UV），
// 逐层 hash 偏移 + 侧面/边框 + 层高 AO → 真实堆叠观感。纯展示，无游戏逻辑。
uniform sampler2D back_tex : source_color;
uniform vec2 project_card_size = vec2(1.86, 1.90);
uniform float rotation_deg = 0.0;
uniform float layer_height = 0.01;
uniform vec2 layer_offset = vec2(0.03, 0.02);
uniform float layer_shuffle = 1.0;
uniform float layer_ao = 0.25;
uniform float edge_darken = 0.35;
uniform float edge_softness = 0.40;
uniform float model_height = 0.25;
uniform vec4 tint : source_color = vec4(1.0);
uniform bool tile = false;

varying vec3 v_local;
varying vec3 v_norm;

vec2 hash22(vec2 v) {
	return fract(vec2(sin(v.x * 127.1 + v.y * 311.7) * 43758.5453,
					  sin(v.x * 269.5 + v.y * 183.3) * 28001.8384));
}

void vertex() {
	v_local = VERTEX;   // vertex() 内 VERTEX 为模型局部坐标
	v_norm = NORMAL;
}

void fragment() {
	float li = floor(v_local.y / max(layer_height, 1e-5));
	vec2 off = (hash22(vec2(li, layer_shuffle)) * 2.0 - 1.0) * layer_offset;

	float a = radians(rotation_deg);
	float c = cos(a);
	float s = sin(a);
	vec2 xz = vec2(v_local.x * c - v_local.z * s, v_local.x * s + v_local.z * c);
	vec2 uv = xz / project_card_size + 0.5 + off;
	if (tile) {
		uv = fract(uv);
	}

	vec4 back = texture(back_tex, uv);
	vec3 border = texture(back_tex, vec2(0.5, 0.02)).rgb;
	vec3 edge = border * (1.0 - edge_darken);

	vec3 top = mix(edge, back.rgb, back.a);     // 圆角透明处回退到卡边色（保持不透明）
	float up = clamp(v_norm.y, 0.0, 1.0);
	vec3 col = mix(edge, top, smoothstep(0.0, max(edge_softness, 1e-4), up));

	float depth = 1.0 - clamp(v_local.y / max(model_height, 1e-5), 0.0, 1.0);
	col *= 1.0 - layer_ao * depth;

	ALBEDO = col * tint.rgb;
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_deck_back.tscn`
Expected: 全绿（含 12 个 uniform 断言）。

- [ ] **Step 5: 提交**（仅用户已授权时）

```bash
git add assets/shaders/deck_back_projection.gdshader tests/verify_deck_back.gd
git commit -m "feat(deck): add deck_back_projection shader"
```

---

### Task 5: 沙盒场景与脚本

**Files:**
- Create: `scenes/ui/deck_model_sandbox.tscn`
- Create: `scripts/ui/deck_model_sandbox.gd`
- Modify: `tests/verify_deck_back.gd`

**Interfaces:**
- Consumes: `DeckBackConfig`、`DeckBackMath`（Task 1–3）、着色器（Task 4）
- Produces: `class_name DeckModelSandbox extends Node3D`
  - `func apply_config(cfg: DeckBackConfig) -> void`（写全部 uniform）
  - `func set_param(name: String, value) -> void`（改单项并写 uniform）
  - `func model_node() -> Node3D`
  - `func material() -> ShaderMaterial`
  - 沙盒字段：`var camera: Table3dCamera`、`var model_scale := 0.376`

- [ ] **Step 1: 追加失败测试** — 加 `_test_sandbox()`（`_run()` 变 `async` 调用）：

```gdscript
func _run() -> void:
	_test_config()
	_test_layering()
	_test_projection()
	_test_shader()
	await _test_sandbox()

func _test_sandbox() -> void:
	var sb = load("res://scenes/ui/deck_model_sandbox.tscn").instantiate()
	add_child(sb)
	await get_tree().process_frame
	_check("沙盒实例化", sb != null and sb.get_node_or_null("CameraRig") != null)
	_check("模型节点存在", sb.model_node() != null)
	_check("材质为 ShaderMaterial", sb.material() is ShaderMaterial)
	var cfg := DeckBackConfig.new()
	cfg.layer_ao = 0.5
	cfg.rotation_deg = 33.0
	sb.apply_config(cfg)
	_check("apply_config 写 layer_ao", is_equal_approx(float(sb.material().get_shader_parameter("layer_ao")), 0.5))
	_check("apply_config 写 rotation_deg", is_equal_approx(float(sb.material().get_shader_parameter("rotation_deg")), 33.0))
	sb.set_param("layer_offset", Vector2(0.1, 0.1))
	_check("set_param 写 layer_offset", (sb.material().get_shader_parameter("layer_offset") as Vector2).is_equal_approx(Vector2(0.1, 0.1)))
	sb.queue_free()
```

> 注：`_run()` 现已含 `await`（调用方 `_ready` 已 `await _run()`）。

- [ ] **Step 2: 运行，确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_deck_back.tscn`
Expected: 加载沙盒场景失败 / 脚本未定义。

- [ ] **Step 3: 写沙盒场景** — 创建 `scenes/ui/deck_model_sandbox.tscn`（沿用 `card_fly_sandbox.tscn` 骨架）

```
[gd_scene load_steps=6 format=3]

[ext_resource type="Script" path="res://scripts/ui/deck_model_sandbox.gd" id="1_sandbox"]
[ext_resource type="Script" path="res://scripts/ui/table3d_camera.gd" id="2_cam"]

[sub_resource type="Environment" id="Environment_1"]
background_mode = 1
background_color = Color(0.07, 0.08, 0.1, 1)
ambient_light_source = 2
ambient_light_color = Color(1, 1, 1, 1)
ambient_light_energy = 1.2

[sub_resource type="StandardMaterial3D" id="TableMat"]
albedo_color = Color(0.16, 0.18, 0.22, 1)

[sub_resource type="BoxMesh" id="TableMesh"]
size = Vector3(7, 0.08, 7)

[node name="DeckModelSandbox" type="Node3D"]
script = ExtResource("1_sandbox")

[node name="WorldEnvironment" type="WorldEnvironment" parent="."]
environment = SubResource("Environment_1")

[node name="CameraRig" type="Node3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 3.5, 3.9)
script = ExtResource("2_cam")
EYE_HEIGHT = 3.5
CAMERA_BACK = 1.5
MOUSE_SENSITIVITY = 0.35

[node name="PitchPivot" type="Node3D" parent="CameraRig"]

[node name="Camera3D" type="Camera3D" parent="CameraRig/PitchPivot"]

[node name="Table" type="MeshInstance3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -0.04, 0)
material_override = SubResource("TableMat")
mesh = SubResource("TableMesh")
```

- [ ] **Step 4: 实现沙盒脚本** — 创建 `scripts/ui/deck_model_sandbox.gd`

```gdscript
class_name DeckModelSandbox
extends Node3D
## 抽牌堆模型卡背投影沙盒：加载 DeckCardPile.glb + 套 deck_back_projection 着色器，
## 环视相机 + 实时调参面板（与 CardBlock 单卡背参照对比）。纯展示原型。

const MODEL_PATH := "res://assets/3Dmodels/DeckCardPile.glb"
const SHADER_PATH := "res://assets/shaders/deck_back_projection.gdshader"
const BACK_TEX_PATH := "res://assets/Cards/back07.png"

var camera: Table3dCamera
var model_scale := 0.376  # ≈ Table3dLayout.BLOCK_SIZE.x / 1.86，使牌堆≈一张卡宽
var _config := DeckBackConfig.new()
var _model: Node3D
var _mat: ShaderMaterial
var _ref_card: MeshInstance3D
var _hud: Label

func _ready() -> void:
	_build()
	set_process(true)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _build() -> void:
	if _model != null:
		return
	camera = get_node_or_null("CameraRig")
	if camera != null:
		camera.frame_for_seat(0.0)
	var scene := load(MODEL_PATH) as PackedScene
	_model = scene.instantiate()
	_model.name = "DeckModel"
	add_child(_model)
	_model.position = Vector3(0.0, Table3dLayout.TABLE_HEIGHT, 0.0)
	_model.scale = Vector3.ONE * model_scale
	_mat = ShaderMaterial.new()
	_mat.shader = load(SHADER_PATH)
	_mat.set_shader_parameter("back_tex", load(BACK_TEX_PATH))
	for mi in _mesh_instances(_model):
		mi.material_override = _mat
	_build_ref_card()
	apply_config(_config)
	_build_ui()

func _mesh_instances(root: Node) -> Array:
	var out: Array = []
	if root is MeshInstance3D:
		out.append(root)
	for c in root.get_children():
		out.append_array(_mesh_instances(c))
	return out

func _build_ref_card() -> void:
	_ref_card = MeshInstance3D.new()
	_ref_card.name = "RefCard"
	var plane := PlaneMesh.new()
	plane.orientation = PlaneMesh.FACE_Y
	plane.size = Vector2(Table3dLayout.BLOCK_SIZE.x, Table3dLayout.BLOCK_SIZE.z)
	_ref_card.mesh = plane
	var ref_mat := StandardMaterial3D.new()
	ref_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ref_mat.albedo_texture = load(BACK_TEX_PATH)
	_ref_card.material_override = ref_mat
	_ref_card.position = Vector3(Table3dLayout.BLOCK_SIZE.x + 0.4, Table3dLayout.TABLE_HEIGHT + 0.002, 0.0)
	add_child(_ref_card)

## 写整份 config 到着色器 uniform。
func apply_config(cfg: DeckBackConfig) -> void:
	_config = cfg
	var d := cfg.to_dict()
	for k in DeckBackConfig.KEYS:
		_mat.set_shader_parameter(k, d[k])

## 改单项参数（配置 + uniform 同步）。
func set_param(name: String, value) -> void:
	var d := _config.to_dict()
	d[name] = value
	var next := DeckBackConfig.new()
	for k in DeckBackConfig.KEYS:
		next.set(k, d[k])
	_config = next
	_mat.set_shader_parameter(name, value)

func model_node() -> Node3D:
	return _model

func material() -> ShaderMaterial:
	return _mat

func _process(_delta: float) -> void:
	if _hud == null:
		return
	_hud.text = "scale=%.3f  rotation=%.0f°  ao=%.2f  edge=%.2f" % [
		model_scale, _config.rotation_deg, _config.layer_ao, _config.edge_darken]

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and camera != null:
		camera.look(event.relative)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)
	var panel := PanelContainer.new()
	panel.name = "Tuner"
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-320.0, 8.0)
	panel.custom_minimum_size = Vector2(300.0, 0.0)
	layer.add_child(panel)
	var vb := VBoxContainer.new()
	panel.add_child(vb)
	_add_slider(vb, "project_card_size.x", 0.2, 3.0, _config.project_card_size.x)
	_add_slider(vb, "project_card_size.y", 0.2, 3.0, _config.project_card_size.y)
	_add_slider(vb, "rotation_deg", -180.0, 180.0, _config.rotation_deg)
	_add_slider(vb, "layer_height", 0.002, 0.05, _config.layer_height)
	_add_slider(vb, "layer_offset.x", 0.0, 0.2, _config.layer_offset.x)
	_add_slider(vb, "layer_offset.y", 0.0, 0.2, _config.layer_offset.y)
	_add_slider(vb, "layer_shuffle", 0.0, 5.0, _config.layer_shuffle)
	_add_slider(vb, "layer_ao", 0.0, 1.0, _config.layer_ao)
	_add_slider(vb, "edge_darken", 0.0, 1.0, _config.edge_darken)
	_add_slider(vb, "edge_softness", 0.0, 1.0, _config.edge_softness)
	_add_slider(vb, "model_height", 0.05, 0.6, _config.model_height)
	var row := HBoxContainer.new()
	vb.add_child(row)
	var color := ColorPickerButton.new()
	color.color = _config.tint
	color.custom_minimum_size = Vector2(80.0, 0.0)
	color.color_changed.connect(func(cc): set_param("tint", cc))
	row.add_child(color)
	var tile_cb := CheckBox.new()
	tile_cb.text = "tile"
	tile_cb.button_pressed = _config.tile
	tile_cb.toggled.connect(func(on): set_param("tile", on))
	row.add_child(tile_cb)
	var reset := Button.new()
	reset.text = "Reset"
	reset.pressed.connect(func(): _rebuild_defaults())
	row.add_child(reset)
	_hud = Label.new()
	_hud.name = "Hud"
	_hud.position = Vector2(12.0, 8.0)
	_hud.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	layer.add_child(_hud)

func _add_slider(parent: Control, param: String, lo: float, hi: float, value: float) -> void:
	var lbl := Label.new()
	lbl.text = "%s = %.3f" % [param, value]
	parent.add_child(lbl)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = (hi - lo) / 200.0
	s.value = value
	s.value_changed.connect(func(v):
		lbl.text = "%s = %.3f" % [param, v]
		_apply_nested(param, v))
	parent.add_child(s)

func _apply_nested(param: String, value: float) -> void:
	if param.ends_with(".x") or param.ends_with(".y"):
		var base := param.substr(0, param.length() - 2)
		var vec := _config.get(base) as Vector2
		if param.ends_with(".x"):
			vec.x = value
		else:
			vec.y = value
		set_param(base, vec)
	else:
		set_param(param, value)

func _rebuild_defaults() -> void:
	apply_config(DeckBackConfig.new())
```

- [ ] **Step 5: 运行，确认通过**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_deck_back.tscn`
Expected: 全绿（含沙盒 6 项）。首次加载 33MB 模型可能耗时数秒。

- [ ] **Step 6: 提交**（仅用户已授权时）

```bash
git add scenes/ui/deck_model_sandbox.tscn scripts/ui/deck_model_sandbox.gd tests/verify_deck_back.gd
git commit -m "feat(deck): add deck model cardback sandbox"
```

---

### Task 6: 全量回归与验收

**Files:**
- 无新增（只跑测试）。

- [ ] **Step 1: 编译检查**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit-after 5`
Expected: 无 `SCRIPT ERROR` / 解析错误。

- [ ] **Step 2: 新测试**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_deck_back.tscn`
Expected: `=== DECK BACK RESULT: n/n passed ===`（全绿）。

- [ ] **Step 3: 全量回归（确认零破坏）**

Run: `tools/run_all_tests.sh --quick`
Expected: 既有测试全绿（本改动只新增文件，不应影响任何既有用例）。

- [ ] **Step 4: 人工目视（需 GUI，可选）**

在编辑器打开 `res://scenes/ui/deck_model_sandbox.tscn` 运行，用调参面板把观感调到"真实堆叠"，把最终参数 `to_dict()` 记录到 spec §7 或下一步接入时固化。**不要**把 `model_scale`/临时参数写死进对局（接入是下一步）。

- [ ] **Step 5: 提交**（仅用户已授权时）

```bash
git add -A
git commit -m "test(deck): verify deck cardback projection & sandbox"
```

---

## Self-Review

**Spec coverage**
- §3 架构（Config/Math/Shader/Sandbox/Test）→ Task 1/2/3/4/5 ✅
- §4 着色器算法（分层/偏移/投影/卡边/AO/tile）→ Task 4 逐条实现 ✅
- §5 纯函数签名 → Task 2/3（`hash22`/`layer_index`/`layer_offset`/`project_uv`/`side_blend`/`layer_ao_factor`/`compose`）✅
- §6 沙盒（场景/相机/RefCard/调参面板/`apply_config`/`set_param`）→ Task 5 ✅
- §7 默认值 → Task 1 常量 ✅
- §8 测试（纯函数 + 节点）→ Task 2/3/4/5 测试 ✅
- §9 文件清单 → 全部覆盖 ✅
- §10 非目标（不给对局接入 / 不碰 Blender / 不碰 call-bell）→ Global Constraints 明示 ✅

**Placeholder scan**：无 TODO/TBD；每个代码步骤均为完整代码。

**Type consistency**：`DeckBackConfig.KEYS` 与 shader uniform 名逐字一致（Task 1 ↔ Task 4）；`DeckBackMath` 函数签名在 Task 2/3 定义并在 Task 5 测试中使用一致；`apply_config`/`set_param`/`model_node`/`material` 在 Task 5 定义并在 Task 5 测试调用一致。
