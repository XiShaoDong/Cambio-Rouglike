shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, depth_test_disabled;

// 3D 投影看板：细分曲面 + 圆角 SDF 发光边 + 轻微色差。无扫描线。
uniform sampler2D board_tex : source_color, filter_linear, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 0.94);
uniform vec3 holo_color : source_color = vec3(0.435, 0.827, 1.0);
uniform float edge_glow : hint_range(0.0, 1.0) = 0.14;
uniform float chroma : hint_range(0.0, 0.002) = 0.0003;
uniform float curve : hint_range(0.0, 0.08) = 0.020;

void vertex() {
	vec2 c = UV - 0.5;
	VERTEX.z -= curve * (c.x * c.x + 0.35 * c.y * c.y);
}

void fragment() {
	vec2 uv = UV;
	float r = texture(board_tex, uv + vec2(chroma, 0.0)).r;
	float g = texture(board_tex, uv).g;
	float b = texture(board_tex, uv - vec2(chroma, 0.0)).b;
	float a = texture(board_tex, uv).a;

	// 圆角矩形 SDF：只在边缘附近发光，不画直线边框。
	vec2 q = abs(UV - 0.5) * 2.0;
	float rad = 0.08;
	vec2 d = q - vec2(1.0 - rad);
	float sdf = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - rad;
	float ring = smoothstep(-0.10, 0.0, sdf) * (1.0 - smoothstep(0.0, 0.03, sdf));

	ALBEDO = (vec3(r, g, b) + holo_color * ring * edge_glow) * tint.rgb;
	ALPHA = clamp(a * tint.a + ring * edge_glow * 1.6, 0.0, 1.0);
}
