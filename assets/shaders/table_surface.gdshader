shader_type spatial;

// 牌桌表面：保留原有 PBR（台布/木头/黑边），叠加随相机注视方向滑动的柔和反光 +
// Fresnel 边缘光。让桌面也有"眼神光影"，与卡牌/铃铛/机器人同源。
uniform vec4 albedo_color : source_color = vec4(0.27, 0.41, 0.29, 1.0);
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.9;
uniform float sheen_strength : hint_range(0.0, 2.0) = 0.4;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.15;
uniform float grain_amount : hint_range(0.0, 0.2) = 0.04;
uniform vec3 light_dir_world = vec3(-0.4, 0.82, 0.41);
uniform vec4 sheen_tint : source_color = vec4(0.72, 0.84, 1.0, 1.0);

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	ALBEDO = albedo_color.rgb;
	METALLIC = metallic;
	ROUGHNESS = roughness;

	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	float fres = pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 3.0) * rim_strength;

	// 世界位置微噪点：磨砂表面的细颗粒（低频、极弱，避免闪光/洗白）。
	vec3 gaze = normalize(-INV_VIEW_MATRIX[2].xyz);
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float grain = hash21(floor(wp.xz * 90.0));
	ALBEDO *= 1.0 + (grain - 0.5) * grain_amount * 2.0;

	// 桌面很大：用世界位置的低频相位 + 相机 gaze，转头时一条非常淡的柔光带扫过。
	float phase = wp.x * 0.13 + wp.z * 0.10 + gaze.x * 1.0 + gaze.y * 0.7;
	float band = pow(0.5 + 0.5 * cos(phase * 6.2831853), 3.0);

	vec3 tint = mix(vec3(1.0), sheen_tint.rgb, 0.10);
	EMISSION = tint * (fres + band * sheen_strength * 0.22);
}
