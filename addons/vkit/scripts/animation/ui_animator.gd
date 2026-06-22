## UIAnimator —— 批量 UI 入场/退场动画控制器
## 挂载到任意 Node，通过 targets 数组管理多个 Control 节点的位移/旋转/缩放/透明度动画
class_name UIAnimator
extends Node

# =========================
# 枚举
# =========================
enum StaggerMode {
	SEQUENCE,   ## 顺序交错（每个节点依次延迟）
	INSTANT,    ## 同时播放（无延迟）
	HALF,       ## 半速交错
	REVERSE,    ## 逆序交错（从末尾开始）
}

# =========================
# 信号
# =========================
signal anim_in_completed    ## 所有入场动画完成
signal anim_out_completed   ## 所有退场动画完成

# =========================
# Export
# =========================
@export_category("UIAnimator")

@export_group("动画目标")
@export var targets: Array[Control] = [] ## 动画目标节点列表，顺序对应下方所有数组

@export_group("起始偏移（相对最终位置）")
@export var start_offsets: Array[Vector2] = []    ## 各节点入场前的位置偏移（如 Vector2(0, 40) 表示从下方进入）
@export var start_rotations: Array[float] = []    ## 各节点入场前的旋转偏移（单位：度），正值顺时针
@export var start_scales: Array[Vector2] = []     ## 各节点入场前的缩放系数（相对最终缩放的乘数）

@export_group("动画曲线")
@export var trans_types: Array[Tween.TransitionType] = [] ## 各节点的 Tween 过渡曲线类型，数量不足时取最后一项或默认 SINE
@export var ease_types: Array[Tween.EaseType] = []        ## 各节点的 Tween 缓动方向，数量不足时取最后一项或默认 EASE_OUT

@export_group("动画属性")
@export var anim_time: float = 0.5   ## 单个节点动画持续时长（秒）
@export var stagger: float = 0.15    ## 交错模式下相邻节点的延迟间隔（秒）
@export var stagger_mode: StaggerMode = StaggerMode.SEQUENCE ## 交错播放模式

@export_subgroup("退场动画")
@export var out_offset: Vector2 = Vector2(0, 40)    ## 退场时的位置偏移量
@export var out_rotation: float = 8.0               ## 退场时的旋转偏移量（度），正值顺时针
@export var out_scale: float = 0.9                  ## 退场时的缩放系数
@export var out_time: float = 0.3                   ## 退场动画持续时长（秒）
@export var out_stagger: float = 0.08               ## 退场交错延迟间隔（秒），0 表示同时退场

# =========================
# 内部状态
# =========================
var _final_state := {}        ## 各节点的最终（静止）状态缓存
var _start_delays := {}       ## 各节点的入场延迟时间缓存
var _active_tweens: Array = [] ## 当前活跃的 Tween 列表，用于强制停止

# =========================
# 生命周期
# =========================
func _ready() -> void:
	_cache_final_states()
	_prepare_all_start_states()

# =========================
# 缓存最终状态
# =========================
func _cache_final_states() -> void:
	_final_state.clear()
	for node in targets:
		if not is_instance_valid(node):
			continue
		_final_state[node] = {
			"pos":   node.position,
			"rot":   node.rotation,
			"scale": node.scale,
		}

# =========================
# 初始化所有节点为起始状态
# =========================
func _prepare_all_start_states() -> void:
	_start_delays.clear()
	for i in range(targets.size()):
		var node := targets[i]
		if not is_instance_valid(node):
			continue
		_apply_start_state(node, i)
		_start_delays[node] = _calc_delay(i)

func _apply_start_state(node: Control, i: int) -> void:
	var f: Dictionary = _final_state[node]
	var offset: Vector2 = start_offsets[i]    if i < start_offsets.size()    else Vector2.ZERO
	var rot: float      = start_rotations[i]  if i < start_rotations.size()  else 0.0
	var scl: Vector2    = start_scales[i]     if i < start_scales.size()     else Vector2.ONE

	node.position = f["pos"] + offset
	node.rotation = f["rot"] + deg_to_rad(rot)
	node.scale    = Vector2(f["scale"].x * scl.x, f["scale"].y * scl.y)
	node.modulate.a = 0.0

# =========================
# 计算交错延迟
# =========================
func _calc_delay(i: int) -> float:
	match stagger_mode:
		StaggerMode.INSTANT:  return 0.0
		StaggerMode.HALF:     return i * stagger * 0.5
		StaggerMode.REVERSE:  return (targets.size() - 1 - i) * stagger
		_:                    return i * stagger  # SEQUENCE

# =========================
# 读取曲线（不足时回退）
# =========================
func _get_trans(i: int) -> Tween.TransitionType:
	if trans_types.is_empty():
		return Tween.TRANS_SINE
	return trans_types[mini(i, trans_types.size() - 1)]

func _get_ease(i: int) -> Tween.EaseType:
	if ease_types.is_empty():
		return Tween.EASE_OUT
	return ease_types[mini(i, ease_types.size() - 1)]

# =========================
# 强制停止所有 Tween
# =========================
func stop_all() -> void:
	for t in _active_tweens:
		if t is Tween:
			t.kill()
	_active_tweens.clear()

# =========================
# 入场动画 —— 全部并行播放，全部完成后发出信号
# =========================
func play_in_all() -> void:
	stop_all()
	_prepare_all_start_states()
	var tweens: Array[Tween] = []

	for i in range(targets.size()):
		var node := targets[i]
		if not is_instance_valid(node):
			continue
		var t := _build_in_tween(node, i)
		tweens.append(t)
		_active_tweens.append(t)

	# 等待所有 tween 真正并行完成
	for t in tweens:
		await t.finished

	_active_tweens.clear()
	anim_in_completed.emit()

# =========================
# 单节点入场
# =========================
func play_in_one(node: Control) -> void:
	var i := targets.find(node)
	if i == -1 or not is_instance_valid(node):
		return
	_apply_start_state(node, i)
	var t := _build_in_tween(node, i, 0.0)  # 单节点不加 stagger 延迟
	_active_tweens.append(t)
	await t.finished
	_active_tweens.erase(t)

func _build_in_tween(node: Control, i: int, delay_override: float = -1.0) -> Tween:
	var f: Dictionary = _final_state[node]
	var delay: float   = delay_override if delay_override >= 0.0 else _start_delays.get(node, 0.0)
	var t := create_tween()
	t.tween_interval(delay)
	t.set_trans(_get_trans(i))
	t.set_ease(_get_ease(i))
	t.tween_property(node, "position",   f["pos"],   anim_time)
	t.parallel().tween_property(node, "rotation",   f["rot"],   anim_time)
	t.parallel().tween_property(node, "scale",      f["scale"], anim_time)
	t.parallel().tween_property(node, "modulate:a", 1.0,        anim_time)
	return t

# =========================
# 退场动画 —— 全部并行播放，全部完成后发出信号
# =========================
func play_out_all() -> void:
	stop_all()
	var tweens: Array[Tween] = []

	for i in range(targets.size()):
		var node := targets[i]
		if not is_instance_valid(node):
			continue
		var t := _build_out_tween(node, i)
		tweens.append(t)
		_active_tweens.append(t)

	for t in tweens:
		await t.finished

	_active_tweens.clear()
	anim_out_completed.emit()

# =========================
# 单节点退场
# =========================
func play_out_one(node: Control) -> void:
	var i := targets.find(node)
	if i == -1 or not is_instance_valid(node):
		return
	var t := _build_out_tween(node, i, 0.0)
	_active_tweens.append(t)
	await t.finished
	_active_tweens.erase(t)

func _build_out_tween(node: Control, i: int, delay_override: float = -1.0) -> Tween:
	var delay: float = delay_override if delay_override >= 0.0 else i * out_stagger
	var t := create_tween()
	if delay > 0.0:
		t.tween_interval(delay)
	t.set_trans(Tween.TRANS_QUAD)
	t.set_ease(Tween.EASE_IN)
	t.tween_property(node, "position", node.position + out_offset, out_time)
	t.parallel().tween_property(node, "rotation",   node.rotation + deg_to_rad(out_rotation), out_time)
	t.parallel().tween_property(node, "scale",      node.scale * out_scale,                   out_time)
	t.parallel().tween_property(node, "modulate:a", 0.0,                                      out_time)
	return t

# =========================
# 重置所有节点到起始状态（不播放动画）
# =========================
func reset() -> void:
	stop_all()
	_cache_final_states()
	_prepare_all_start_states()
