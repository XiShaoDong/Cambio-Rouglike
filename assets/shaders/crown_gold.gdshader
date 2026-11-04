shader_type spatial;
render_mode unshaded, cull_back;

// 冠军皇冠：保留铜质贴图，叠加随视角移动的金属高光 + 金色边缘光。
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform vec3 light_dir_world = vec3(-0.45, 0.82, 0.36);
uniform float spec_strength : hint_range(0.0, 2.0) = 1.1;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.35;
uniform vec3 tint : source_color = vec3(1.0, 0.84, 0.42);

void fragment() {
	vec3 base = texture(albedo_tex, UV).rgb * albedo_color.rgb;
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	vec3 l = normalize((VIEW_MATRIX * vec4(light_dir_world, 0.0)).xyz);
	vec3 h = normalize(l + v);
	float ndl = max(dot(n, l), 0.0);
	float spec = pow(max(dot(n, h), 0.0), 36.0) * spec_strength;
	float fres = pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 2.0) * rim_strength;
	ALBEDO = base * (0.7 + 0.3 * ndl) + tint * (spec + fres);
}
