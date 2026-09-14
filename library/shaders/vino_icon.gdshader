shader_type canvas_item;

// 0: 播放, 1: 暂停, 2: 停止, 3: 后退, 4: 前进, 5: 音量-, 6: 音量+, 7: 退出
uniform int icon_type : hint_range(0, 7) = 0;
uniform vec4 icon_color : source_color = vec4(1.0);

// ============================================================
// SDF 基础函数
// ============================================================

float cross2d(vec2 a, vec2 b) {
	return a.x * b.y - a.y * b.x;
}

float sd_box(vec2 p, vec2 size, float radius) {
	vec2 q = abs(p) - size + radius;
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
}

float sd_segment(vec2 p, vec2 a, vec2 b, float width) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h) - width;
}

float sd_triangle(vec2 p, vec2 a, vec2 b, vec2 c) {
	float d1 = sd_segment(p, a, b, 0.0);
	float d2 = sd_segment(p, b, c, 0.0);
	float d3 = sd_segment(p, c, a, 0.0);
	float d = min(d1, min(d2, d3));

	float c1 = cross2d(b - a, p - a);
	float c2 = cross2d(c - b, p - b);
	float c3 = cross2d(a - c, p - c);

	bool inside = (c1 >= 0.0 && c2 >= 0.0 && c3 >= 0.0) || (c1 <= 0.0 && c2 <= 0.0 && c3 <= 0.0);
	return inside ? -d : d;
}

// 梯形 SDF (用于绘制喇叭喇叭口)
float sd_trapezoid(vec2 p, float r1, float r2, float he) {
	vec2 k1 = vec2(r2, he);
	vec2 k2 = vec2(r2 - r1, 2.0 * he);
	p.x = abs(p.x);
	vec2 ca = vec2(p.x - min(p.x, (p.y < 0.0) ? r1 : r2), abs(p.y) - he);
	vec2 cb = p - k1 + k2 * clamp(dot(k1 - p, k2) / dot(k2, k2), 0.0, 1.0);
	float s = (cb.x < 0.0 && ca.y < 0.0) ? -1.0 : 1.0;
	return s * sqrt(min(dot(ca, ca), dot(cb, cb)));
}

// ============================================================
// 图标绘制
// ============================================================

// 0: 播放 ▶
float icon_play(vec2 p) {
	vec2 a = vec2(-0.25, -0.35);
	vec2 b = vec2(-0.25,  0.35);
	vec2 c = vec2( 0.35,  0.00);
	return sd_triangle(p, a, b, c);
}

// 1: 暂停 ⏸
float icon_pause(vec2 p) {
	float left = sd_box(p - vec2(-0.16, 0.0), vec2(0.09, 0.35), 0.03);
	float right = sd_box(p - vec2( 0.16, 0.0), vec2(0.09, 0.35), 0.03);
	return min(left, right);
}

// 2: 停止 ■
float icon_stop(vec2 p) {
	return sd_box(p, vec2(0.33), 0.04);
}

// 3: 后退 <<
float icon_back(vec2 p) {
	vec2 a1 = vec2(-0.02, -0.30);
	vec2 b1 = vec2(-0.02,  0.30);
	vec2 c1 = vec2(-0.35,  0.00);

	vec2 a2 = vec2(0.33, -0.30);
	vec2 b2 = vec2(0.33,  0.30);
	vec2 c2 = vec2(0.00,  0.00);

	return min(sd_triangle(p, a1, b1, c1), sd_triangle(p, a2, b2, c2));
}

// 4: 前进 >>
float icon_forward(vec2 p) {
	vec2 a1 = vec2(0.02, -0.30);
	vec2 b1 = vec2(0.02,  0.30);
	vec2 c1 = vec2(0.35,  0.00);

	vec2 a2 = vec2(-0.33, -0.30);
	vec2 b2 = vec2(-0.33,  0.30);
	vec2 c2 = vec2( 0.00,  0.00);

	return min(sd_triangle(p, a1, b1, c1), sd_triangle(p, a2, b2, c2));
}

// 喇叭主体 (左侧方块 + 右侧梯形扩音口)
float speaker_base(vec2 p) {
	// 左侧小矩形 (发声源)
	float body = sd_box(p - vec2(-0.28, 0.0), vec2(0.07, 0.12), 0.02);

	// 右侧梯形 (旋转 90 度作为喇叭扩音口)
	// 旋转坐标系: p.y 为梯形高, p.x 为梯形底
	vec2 tp = vec2(p.y, p.x + 0.10);
	float cone = sd_trapezoid(tp, 0.12, 0.28, 0.11);

	// 平滑融合或直接合并
	return min(body, cone);
}

// 5: 音量 -
float icon_volume_minus(vec2 p) {
	float speaker = speaker_base(p);
	float minus = sd_segment(p, vec2(0.12, 0.0), vec2(0.36, 0.0), 0.035);
	return min(speaker, minus);
}

// 6: 音量 +
float icon_volume_plus(vec2 p) {
	float speaker = speaker_base(p);
	float h = sd_segment(p, vec2(0.12, 0.0), vec2(0.36, 0.0), 0.035);
	float v = sd_segment(p, vec2(0.24, -0.12), vec2(0.24, 0.12), 0.035);
	return min(speaker, min(h, v));
}

// 7: 退出
float icon_exit(vec2 p) {
	float door = sd_box(p + vec2(0.18, 0.0), vec2(0.20, 0.36), 0.03);
	float door_inner = sd_box(p + vec2(-0.10, 0.0), vec2(0.14, 0.30), 0.2);
	door = max(door, -door_inner);

	float line = sd_segment(p, vec2(-0.10, 0.0), vec2(0.36, 0.0), 0.045);
	float arrow1 = sd_segment(p, vec2(0.36, 0.0), vec2(0.18, 0.18), 0.045);
	float arrow2 = sd_segment(p, vec2(0.36, 0.0), vec2(0.18, -0.18), 0.045);

	return min(door, min(line, min(arrow1, arrow2)));
}

// ============================================================
// 主函数
// ============================================================

void fragment() {
	vec2 p = UV - vec2(0.5);

	float aspect = TEXTURE_PIXEL_SIZE.y / TEXTURE_PIXEL_SIZE.x;
	if (aspect > 1.0) {
		p.y *= aspect;
	} else {
		p.x /= aspect;
	}

	float d = 1.0;

	if (icon_type == 0) {
		d = icon_play(p);
	} else if (icon_type == 1) {
		d = icon_pause(p);
	} else if (icon_type == 2) {
		d = icon_stop(p);
	} else if (icon_type == 3) {
		d = icon_back(p);
	} else if (icon_type == 4) {
		d = icon_forward(p);
	} else if (icon_type == 5) {
		d = icon_volume_minus(p);
	} else if (icon_type == 6) {
		d = icon_volume_plus(p);
	} else if (icon_type == 7) {
		d = icon_exit(p);
	}

	// 抗锯齿输出
	float aa = fwidth(d);
	float alpha = 1.0 - smoothstep(-aa, aa, d);

	COLOR = vec4(icon_color.rgb, alpha * icon_color.a);
}