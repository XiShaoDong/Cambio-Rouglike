shader_type spatial;
render_mode cull_disabled;

// Kong 铃铛金属材质：单一网格按模型局部高度 Y 分段上色 —— 黑底座 / 金钟体 / 银顶钮。
// 各段独立 METALLIC/ROUGHNESS；amount 自发光基底用于补偿偏暗的环境（保留金属反光）。
uniform vec3 base_color : source_color = vec3(0.02, 0.02, 0.025);   // 黑底座
uniform vec3 dome_color : source_color = vec3(0.88, 0.62, 0.20);    // 金钟体
uniform vec3 knob_color : source_color = vec3(0.92, 0.93, 0.96);    // 银顶钮
uniform float base_top = 0.26;       // 模型局部 Y（未缩放）：底座与钟体的分界
uniform float knob_bottom = 1.10;    // 模型局部 Y：钟体与顶钮的分界
uniform float glow = 0.0;            // 可用性辉光强度（0/1）
uniform float ambient_lift = 0.30;   // 自发光提亮基底（补偿暗环境；0=纯 PBR 金属）
uniform float fresnel_lift = 0.22;   // 菲涅尔边缘提亮（均匀环境下也有光泽）

varying float v_y;

void vertex() {
	v_y = VERTEX.y;
}

void fragment() {
	if (v_y < base_top) {
		ALBEDO = base_color;
		METALLIC = 0.25;
		ROUGHNESS = 0.45;
	} else if (v_y > knob_bottom) {
		ALBEDO = knob_color;
		METALLIC = 0.85;
		ROUGHNESS = 0.14;
	} else {
		ALBEDO = dome_color;
		METALLIC = 0.80;
		ROUGHNESS = 0.20;
	}
	// 自发光基底 + 可用性金光 + 菲涅尔边缘，保证在偏暗/均匀环境下也明亮有光泽。
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	EMISSION = ALBEDO * ambient_lift + dome_color * glow + ALBEDO * fres * fresnel_lift;
}
