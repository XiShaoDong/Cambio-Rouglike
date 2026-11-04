shader_type spatial;

// 玩家机器人机体：保留原金属 PBR，再叠一层"眼神高光"——
// 固定世界光方向 + 当前视角的 Blinn 高光 + Fresnel 边缘光，随相机转动在肩/头上滑动。
uniform vec4 albedo_color : source_color = vec4(0.286, 0.416, 0.996, 1.0);
uniform float metallic : hint_range(0.0, 1.0) = 0.7;
uniform float roughness : hint_range(0.0, 1.0) = 0.35;
uniform vec3 light_dir_world = vec3(-0.4, 0.82, 0.41);
uniform float eye_spec : hint_range(0.0, 2.0) = 0.8;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.22;
uniform vec3 rim_color : source_color = vec3(0.72, 0.84, 1.0);

void fragment() {
	ALBEDO = albedo_color.rgb;
	METALLIC = metallic;
	ROUGHNESS = roughness;

	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	vec3 l = normalize((VIEW_MATRIX * vec4(light_dir_world, 0.0)).xyz);
	vec3 h = normalize(l + v);
	float spec = pow(max(dot(n, h), 0.0), 48.0) * eye_spec;
	float fres = pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 3.0);
	EMISSION = rim_color * (spec * 0.5 + fres * rim_strength);
}
