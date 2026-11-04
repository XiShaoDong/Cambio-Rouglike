shader_type canvas_item;
render_mode blend_mix;

// 2D 伪 3D 卡牌：片元内逆单应映射（真透视）+ 固定光打光。
// GDScript（CardTiltMath）每帧算好「目标梯形 → 源 UV」的 3x3 逆矩阵，按行传入。
uniform vec3 inv_row0 = vec3(1.0, 0.0, 0.0);
uniform vec3 inv_row1 = vec3(0.0, 1.0, 0.0);
uniform vec3 inv_row2 = vec3(0.0, 0.0, 1.0);

uniform vec3 card_normal = vec3(0.0, 0.0, 1.0);
uniform vec3 light_dir = vec3(-0.45, -0.35, 0.82);
uniform vec3 tilt_deg = vec3(0.0);

uniform float spec_strength : hint_range(0.0, 2.0) = 0.55;
uniform float gloss_strength : hint_range(0.0, 2.0) = 0.35;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.30;
uniform float shadow_strength : hint_range(0.0, 1.0) = 0.35;
uniform vec2 shadow_offset = vec2(0.02, 0.018);
uniform float shadow_blur : hint_range(0.0, 0.05) = 0.012;
uniform float base_gain : hint_range(0.0, 2.0) = 1.0;
uniform vec4 gloss_tint : source_color = vec4(0.62, 0.78, 1.0, 1.0);

// 画布扩展：把绘制四边形放大 canvas_pad 倍（配合逆映射的 pad，卡面视觉尺寸不变），
// 让倾斜外扩/投影/反光不被节点矩形裁掉。CardTiltView 预留了画布，保持默认 1.0。
uniform vec2 rect_size = vec2(1.0);
uniform float canvas_pad = 1.0;

void vertex() {
	vec2 center = rect_size * 0.5;
	VERTEX = (VERTEX - center) * canvas_pad + center;
}

void fragment() {
	vec3 p = vec3(
		dot(inv_row0, vec3(UV, 1.0)),
		dot(inv_row1, vec3(UV, 1.0)),
		dot(inv_row2, vec3(UV, 1.0)));

	// p.z <= 0 表示该像素落在视平面之后（背面），直接丢弃。
	float front = step(0.0001, p.z);
	vec2 suv = p.xy / max(p.z, 0.0001);

	vec2 fw = max(fwidth(suv), vec2(0.00001));
	float inside_x = smoothstep(-fw.x, fw.x, suv.x) * (1.0 - smoothstep(1.0 - fw.x, 1.0 + fw.x, suv.x));
	float inside_y = smoothstep(-fw.y, fw.y, suv.y) * (1.0 - smoothstep(1.0 - fw.y, 1.0 + fw.y, suv.y));
	float inside = inside_x * inside_y * front;

	vec4 card = texture(TEXTURE, clamp(suv, vec2(0.0), vec2(1.0)));

	// 固定光源：Lambert 漫反射 + Blinn 镜面高光 + 宽柔光。
	vec3 n = normalize(card_normal);
	vec3 l = normalize(light_dir);
	vec3 v = vec3(0.0, 0.0, 1.0);
	vec3 h = normalize(l + v);
	float ndl = max(dot(n, l), 0.0);
	float ndh = max(dot(n, h), 0.0);
	float diffuse = 0.72 + 0.28 * ndl;
	float spec = pow(ndh, 48.0) * spec_strength;
	float sheen = pow(ndh, 6.0) * 0.16;

	// 倾斜时沿对角滑动的反光条（两段）。
	float band_phase = fract(suv.x * 0.9 + suv.y * 0.45 + tilt_deg.x * 0.014 + tilt_deg.y * 0.009);
	float band = 1.0 - smoothstep(0.0, 0.17, abs(band_phase - 0.5));
	float band2_phase = fract(band_phase + 0.35);
	float band2 = 1.0 - smoothstep(0.0, 0.10, abs(band2_phase - 0.5));
	float gloss = (band * 0.65 + band2 * 0.35) * gloss_strength;

	// 边缘轮廓光。
	float edge = min(min(suv.x, 1.0 - suv.x), min(suv.y, 1.0 - suv.y));
	float rim = (1.0 - smoothstep(0.0, 0.045, edge)) * rim_strength;

	vec3 lit = card.rgb * diffuse * base_gain;
	lit += vec3(spec + sheen);
	lit += gloss_tint.rgb * (gloss + rim);

	// 卡片外的投影：把源 UV 反向偏移后采样卡面 alpha，五抽平均做模糊。
	vec2 sshift = suv - shadow_offset;
	float sh_mask = step(0.0, sshift.x) * step(sshift.x, 1.0) * step(0.0, sshift.y) * step(sshift.y, 1.0) * front;
	vec2 s_uv = clamp(sshift, vec2(0.0), vec2(1.0));
	float sh = texture(TEXTURE, s_uv).a * 0.32;
	sh += texture(TEXTURE, clamp(sshift + vec2(shadow_blur, 0.0), vec2(0.0), vec2(1.0))).a * 0.17;
	sh += texture(TEXTURE, clamp(sshift - vec2(shadow_blur, 0.0), vec2(0.0), vec2(1.0))).a * 0.17;
	sh += texture(TEXTURE, clamp(sshift + vec2(0.0, shadow_blur), vec2(0.0), vec2(1.0))).a * 0.17;
	sh += texture(TEXTURE, clamp(sshift - vec2(0.0, shadow_blur), vec2(0.0), vec2(1.0))).a * 0.17;
	sh *= shadow_strength * sh_mask;

	vec4 card_col = vec4(lit, card.a * inside);
	vec4 shadow_col = vec4(0.0, 0.0, 0.0, sh * (1.0 - inside));
	COLOR = card_col + shadow_col;
}
