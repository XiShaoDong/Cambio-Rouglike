shader_type spatial;
render_mode unshaded, cull_back;

// 道具手牌弹层的 3D 手臂/手：无光照环境也能有立体感（自算朝向光 + 边缘光）。
uniform vec4 albedo_color : source_color = vec4(0.24, 0.30, 0.44, 1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform bool use_texture = false;
uniform vec3 light_dir_world = vec3(-0.45, 0.82, 0.36);
uniform float rim_strength : hint_range(0.0, 2.0) = 0.25;

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	vec3 l = normalize((VIEW_MATRIX * vec4(light_dir_world, 0.0)).xyz);
	float ndl = max(dot(n, l), 0.0);
	float fres = pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 2.0);
	vec3 rim = vec3(0.35, 0.45, 0.62) * fres * rim_strength;
	vec3 base = albedo_color.rgb;
	if (use_texture) {
		base = texture(albedo_tex, UV).rgb * albedo_color.rgb;
	}
	ALBEDO = base * (0.62 + 0.38 * ndl) + rim;
}
