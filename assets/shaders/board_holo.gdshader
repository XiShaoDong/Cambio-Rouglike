shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, depth_test_disabled;

// 3D 投影看板：细分曲面 + 圆角 SDF 发光边 + 外发光 + 屏幕空间扫描线 + 轻微色差。
uniform sampler2D board_tex : source_color, filter_linear, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 0.96);
uniform vec3 holo_color : source_color = vec3(0.435, 0.827, 1.0);
uniform float edge_glow : hint_range(0.0, 1.0) = 0.14;
uniform float chroma : hint_range(0.0, 0.002) = 0.00035;
uniform float curve : hint_range(0.0, 0.08) = 0.020;
uniform float scanline : hint_range(0.0, 0.12) = 0.028;
uniform float sweep : hint_range(0.0, 0.2) = 0.045;

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

	// 圆角矩形 SDF：贴边发光 + 外侧一层更柔的辉光。
	vec2 q = abs(UV - 0.5) * 2.0;
	float rad = 0.08;
	vec2 d = q - vec2(1.0 - rad);
	float sdf = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - rad;
	float ring = smoothstep(-0.06, 0.0, sdf) * (1.0 - smoothstep(0.0, 0.02, sdf));
	float outer = smoothstep(0.0, 0.03, sdf) * (1.0 - smoothstep(0.03, 0.09, sdf));

	// 扫描线用屏幕像素坐标：转动视角时不会跟着面板歪斜/断线。
	float content = step(0.002, a);
	float line = 0.5 + 0.5 * sin(FRAGCOORD.y * 1.5708);
	float scan = content * scanline * line;
	float band = content * smoothstep(0.10, 0.0, abs(fract(uv.y - TIME * 0.075) - 0.5)) * sweep;

	ALBEDO = (vec3(r, g, b) + holo_color * (ring + outer * 0.7) * edge_glow * 1.2) * tint.rgb
		+ holo_color * scan * 0.5 + holo_color * band * 0.35;
	ALPHA = clamp(a * tint.a + (ring * 1.6 + outer * 0.9) * edge_glow + scan * 0.6 + band, 0.0, 1.0);
}
