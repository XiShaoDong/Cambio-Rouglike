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
