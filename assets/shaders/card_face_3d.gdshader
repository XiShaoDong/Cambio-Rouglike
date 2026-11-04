shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha;

// 3D 卡面：与 2D card_tilt.gdshader 同源的打光（常亮漫反射 +
// 柔和的斜向反光 + 源 UV 边缘轮廓光）。unshaded 自算光照，
// 反光条随相机注视方向（玩家"眼神"）滑动，而不是固定贴图或跟着 hover。

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform vec2 uv_scale = vec2(-1.0, -1.0);
uniform vec2 uv_offset = vec2(1.0, 1.0);

// 世界空间光源方向（指向光）。与 table3d 的 KeyLight 大致一致：左上前上方。
uniform vec3 light_dir_world = vec3(-0.4, 0.82, 0.41);

uniform float gloss_strength : hint_range(0.0, 2.0) = 0.35;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.30;
uniform float base_gain : hint_range(0.0, 2.0) = 1.0;
uniform vec4 gloss_tint : source_color = vec4(0.62, 0.78, 1.0, 1.0);

void fragment() {
	vec2 uv = UV * uv_scale + uv_offset;
	vec4 tex = texture(albedo_tex, uv);
	vec3 n = normalize(NORMAL);
	vec3 l = normalize((VIEW_MATRIX * vec4(light_dir_world, 0.0)).xyz);

	float ndl = max(dot(n, l), 0.0);
	// 平放卡法线一致：镜面高光是整张均匀提亮，看不出形状，只靠反光条/轮廓光表现。
	float diffuse = 0.72 + 0.20 * ndl;

	// 反光相位跟相机注视方向（gaze）走：转头/抬低头时高光在卡面滑动。
	// 用 INV_VIEW_MATRIX 取相机世界前向（相机看向 -Z）。
	vec3 gaze = normalize(-INV_VIEW_MATRIX[2].xyz);
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// 加一点世界位置偏移：同桌每张牌的反光相位略有差别，不像同一张贴图铺上去。
	float band_phase = uv.x * 0.8 + uv.y * 0.45 + gaze.x * 1.25 + gaze.y * 0.85
		+ world_pos.x * 0.55 + world_pos.z * 0.4;
	float band = 1.0 - smoothstep(0.0, 0.22, abs(fract(band_phase) - 0.5));
	float band2_phase = fract(band_phase + 0.4);
	float band2 = 1.0 - smoothstep(0.0, 0.12, abs(band2_phase - 0.5));
	float gloss = (band * 0.8 + band2 * 0.2) * gloss_strength * 0.9;

	// 边缘轮廓光：按源 UV 离边距离，柔和描边，不整张提亮。
	float edge = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
	float rim = (1.0 - smoothstep(0.0, 0.10, edge)) * rim_strength * 0.7;

	// unshaded 模式下 EMISSION 不参与最终输出，高光/反光/轮廓必须并进 ALBEDO。
	ALBEDO = tex.rgb * albedo_color.rgb * diffuse * base_gain;
	// 反光用乘法提亮，避免加法把红色花色冲成粉色；轮廓光仍用 tint 加法描边。
	ALBEDO *= 1.0 + gloss;
	ALBEDO += gloss_tint.rgb * rim;
	ALPHA = tex.a * albedo_color.a;
}
