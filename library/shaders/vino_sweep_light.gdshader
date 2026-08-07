shader_type canvas_item;

// 1. 定义混合模式枚举
// 在 Godot Shader 中，用 hint_enum 可以直接在面板中渲染成下拉菜单
uniform int blend_mode : hint_enum("Add (直接相加)", "Screen (滤色/叠加)", "Multiply (正片叠底)") = 1;

// 2. 基础控制
// 扫光进度
uniform float progress : hint_range(-0.5, 1.5) = -0.1;
//扫光倾斜角度
uniform float angle_degrees : hint_range(0.0, 360.0) = 30.0;

// 3. 扫光样式控制
uniform float shine_width : hint_range(0.01, 1.0) = 0.15; // 扫光带的宽度
uniform float shine_softness : hint_range(0.01, 1.0) = 0.1; // 边缘羽化（平滑）程度
uniform vec4 shine_color : source_color = vec4(1.0, 1.0, 1.0, 1.0); // 扫光的颜色
uniform float shine_intensity : hint_range(0.0, 5.0) = 1.0; // 扫光强度

void fragment() {
    // 获取底图颜色 (Base)
    vec4 tex_color = texture(TEXTURE, UV);
    vec3 base = tex_color.rgb;
    
    // 计算旋转后的 UV 坐标
    float angle_rad = radians(angle_degrees);
    vec2 shifted_uv = UV - vec2(0.5);
    vec2 rotated_uv;
    rotated_uv.x = shifted_uv.x * cos(angle_rad) - shifted_uv.y * sin(angle_rad);
    rotated_uv.y = shifted_uv.x * sin(angle_rad) + shifted_uv.y * cos(angle_rad);
    rotated_uv += vec2(0.5);

    // 计算扫光遮罩
    float half_width = shine_width * 0.5;
    float current_pos = rotated_uv.x - progress;
    
    float shine_mask = smoothstep(-half_width - shine_softness, -half_width, current_pos) 
                     - smoothstep(half_width, half_width + shine_softness, current_pos);
    shine_mask = clamp(shine_mask, 0.0, 1.0);

    // 计算扫光颜色 (Blend)
    vec3 blend = shine_color.rgb * shine_intensity * shine_mask;
    
    // 准备最终输出的 RGB
    vec3 final_rgb = base;

    // 4. 根据枚举选择对应的图层混合算法
    if (blend_mode == 0) {
        // ---- Add (直接相加) ----
        // 经典能量发光，亮部容易过曝，适合科技感、魔法卡牌
        final_rgb = base + blend;
    } 
    else if (blend_mode == 1) {
        // ---- Screen (滤色) ----
        // 剔除暗部，保留底图细节。最推荐的 UI 扫光模式，质感高档通透
        final_rgb = 1.0 - (1.0 - base) * (1.0 - blend);
    } 
    else if (blend_mode == 2) {
        // ---- Multiply (正片叠底) ----
        // 变暗混合。如果扫光颜色比底图暗，会产生类似“阴影掠过”或“暗金流动”的特殊质感
        final_rgb = base * (blend + (1.0 - shine_mask)); 
        // 注：正片叠底需要让没有扫光的地方保持原样(1.0)，所以这里对遮罩做了反向插值
    }

    // 输出最终颜色，保持原图透明度
    COLOR = vec4(final_rgb, tex_color.a);
}