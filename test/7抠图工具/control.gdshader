shader_type canvas_item;

// 动态参数：可通过 GDScript 或 UI 控件动态修改
uniform vec4 key_color : source_color = vec4(0.0, 1.0, 0.0, 1.0); // 默认绿色
uniform float threshold : hint_range(0.0, 1.0) = 0.4;             // 容差/相似度
uniform float smoothness : hint_range(0.0, 1.0) = 0.1;            // 边缘平滑度
uniform bool spill_reduction = true;                              // 绿溢出/蓝溢出抑制

void fragment() {
    vec4 tex_color = texture(TEXTURE, UV);
    
    // 计算当前像素颜色与抠图目标颜色的色差（基于距离）
    float chroma_dist = distance(tex_color.rgb, key_color.rgb);
    
    // 使用 smoothstep 计算 alpha 遮罩，实现软边缘过渡
    float alpha = smoothstep(threshold, threshold + smoothness, chroma_dist);
    
    // 简易绿/蓝溢出抑制（可选）：防止边缘泛绿或泛蓝
    if (spill_reduction && alpha < 1.0) {
        float max_other = max(tex_color.r, tex_color.b);
        if (tex_color.g > max_other && key_color.g > 0.5) {
            tex_color.g = max_other; // 抑制绿色溢出
        }
    }
    
    COLOR = vec4(tex_color.rgb, tex_color.a * alpha);
}