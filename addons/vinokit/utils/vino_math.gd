class_name VinoMath
extends RefCounted
## 数值相关的静态工具函数。全部无状态，直接 VinoMath.xxx() 调用即可。

## 把 value 从 [in_min, in_max] 区间线性映射到 [out_min, out_max] 区间；超出输入区间时会外插，不做截断。
static func remap(value: float, in_min: float, in_max: float, out_min: float, out_max: float) -> float:
	if is_equal_approx(in_min, in_max):
		return out_min # 避免除零，输入区间退化时直接返回下限
	return (value - in_min) / (in_max - in_min) * (out_max - out_min) + out_min

## remap 的截断版：结果会被夹在 [out_min, out_max] 之间，适合做进度条/透明度这类不能越界的值。
static func remap_clamped(value: float, in_min: float, in_max: float, out_min: float, out_max: float) -> float:
	return clampf(remap(value, in_min, in_max, out_min, out_max), min(out_min, out_max), max(out_min, out_max))

## 判断 value 是否落在 [a, b] 之间（不要求 a <= b）。
static func in_range(value: float, a: float, b: float) -> bool:
	return value >= min(a, b) and value <= max(a, b)

## 带死区的方向输入处理：|value| < deadzone 时返回 0，否则按剩余量重新映射到 [0,1]（保留符号）。
## 常用于摇杆/滑块输入过滤。
static func apply_deadzone(value: float, deadzone: float) -> float:
	var abs_value := absf(value)
	if abs_value < deadzone:
		return 0.0
	var sign_value := signf(value)
	return sign_value * remap(abs_value, deadzone, 1.0, 0.0, 1.0)

## 平滑逼近目标值（比 lerp 更适合"每帧调用"的场景，效果不受帧率影响）。
## smooth_time 越大跟随越慢；delta 传 _process(delta) 的 delta。
static func smooth_damp(current: float, target: float, smooth_time: float, delta: float) -> float:
	if smooth_time <= 0.0:
		return target
	var t := 1.0 - exp(-delta / smooth_time)
	return lerpf(current, target, t)

## 把角度差规整到 [-180, 180] 区间，避免朝向插值时绕远路（例如从 350° 转到 10°）。
static func shortest_angle_diff(from_deg: float, to_deg: float) -> float:
	var diff := fmod(to_deg - from_deg, 360.0)
	if diff > 180.0:
		diff -= 360.0
	elif diff < -180.0:
		diff += 360.0
	return diff
