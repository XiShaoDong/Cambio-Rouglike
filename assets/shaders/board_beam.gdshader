shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

// 3D 看板下方光锥：一片梯形网格 + 两侧淡出 + 顶部亮、底部透明。
// 两片交叉摆放即可在任意环视角度下近似体积光锥。
uniform vec3 beam_color : source_color = vec3(0.435, 0.827, 1.0);
uniform float beam_alpha : hint_range(0.0, 1.0) = 0.16;
uniform float side_softness : hint_range(0.05, 0.5) = 0.28;

void fragment() {
	float side = smoothstep(0.0, side_softness, UV.x) * smoothstep(1.0, 1.0 - side_softness, UV.x);
	float vert = pow(clamp(UV.y, 0.0, 1.0), 2.0);
	ALBEDO = beam_color;
	ALPHA = beam_alpha * side * vert;
}
