@tool
class_name VinoShaderConverter
extends Node

const FRAG := VisualShader.TYPE_FRAGMENT
const UNIFORM_RX := "(?<!global )(?<!instance )uniform\\s+(?:(?:lowp|mediump|highp)\\s+)?(\\w+)\\s+(\\w+)\\s*(?::\\s*([^=;]+))?(?:=\\s*([^;]+))?;" # 匹配 uniform：类型/名称/hint/默认值
const OUT_TYPES := { # spatial 可自动连线的输出变量 -> 端口类型（主输出节点引脚按名字运行时查找）
	"ALBEDO": VisualShaderNode.PORT_TYPE_VECTOR_3D,
	"ALPHA": VisualShaderNode.PORT_TYPE_SCALAR,
	"METALLIC": VisualShaderNode.PORT_TYPE_SCALAR,
	"ROUGHNESS": VisualShaderNode.PORT_TYPE_SCALAR,
	"SPECULAR": VisualShaderNode.PORT_TYPE_SCALAR,
	"EMISSION": VisualShaderNode.PORT_TYPE_VECTOR_3D,
}

## 要转换的单个 .gdshader 文件路径
@export_file("*.gdshader") var source_file: String = ""

## 要批量转换的文件夹路径（自动扫描内部所有 .gdshader）
@export_dir var source_folder: String = ""

## 勾选此项执行转换（执行完毕后自动恢复为 false）
@export var trigger_convert: bool = false:
	set(v):
		if v:
			_run_conversion()
			trigger_convert = false


## 核心分发逻辑：检查面板中配置的文件或文件夹路径并执行
func _run_conversion() -> void:
	if not source_file.is_empty():
		_convert_single_file(source_file)
	if not source_folder.is_empty():
		_convert_folder(source_folder)


## 遍历目标文件夹并提取所有的 .gdshader 进行批量转换
func _convert_folder(folder_path: String) -> void:
	var dir := DirAccess.open(folder_path)
	if dir == null:
		push_error("VinoShaderConverter: 打开文件夹失败: " + folder_path)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.get_extension() == "gdshader":
			_convert_single_file(folder_path.path_join(file_name))
		file_name = dir.get_next()
	dir.list_dir_end()


## 将单个 .gdshader 代码文件转换为 .tres 格式的 VisualShader 资源
func _convert_single_file(gdshader_path: String) -> void:
	var real_path := gdshader_path
	if real_path.begins_with("uid://"):
		var res_id: int = ResourceUID.text_to_id(real_path)
		real_path = ResourceUID.get_id_path(res_id)
	if not FileAccess.file_exists(real_path):
		push_error("VinoShaderConverter: 未找到源文件: " + real_path)
		return
	var file := FileAccess.open(real_path, FileAccess.READ)
	if not file:
		push_error("VinoShaderConverter: 打开文件失败: " + real_path)
		return
	var code_text := file.get_as_text()
	file.close()

	var visual_shader := VisualShader.new()
	var tm := _rx("shader_type\\s+(\\w+)\\s*;").search(code_text)
	match tm.get_string(1) if tm else "":
		"spatial": visual_shader.mode = Shader.MODE_SPATIAL
		"particles": visual_shader.mode = Shader.MODE_PARTICLES
		"sky": visual_shader.mode = Shader.MODE_SKY
		_: visual_shader.mode = Shader.MODE_CANVAS_ITEM

	_build_graph(code_text, visual_shader)

	var output_tres_path := real_path.get_base_dir().path_join(real_path.get_file().get_basename() + "_visual.tres")
	var err := ResourceSaver.save(visual_shader, output_tres_path)
	if err == OK:
		print("✅ [VinoShaderConverter] 成功转换并连线，保存至: ", output_tres_path)
	else:
		push_error("VinoShaderConverter: 保存资源失败，错误码: " + str(err))


## 编译正则的小工具
func _rx(p: String) -> RegEx:
	var r := RegEx.new()
	r.compile(p)
	return r


## 提取 void <fname>() {...}，返回 [完整函数文本, 函数体]，不存在返回 []
func _extract_function(code: String, fname: String) -> Array:
	var m := _rx("void\\s+" + fname + "\\s*\\(\\s*\\)\\s*\\{").search(code)
	if m == null:
		return []
	var depth := 1
	var i := m.get_end()
	while i < code.length() and depth > 0:
		if code[i] == "{": depth += 1
		elif code[i] == "}": depth -= 1
		i += 1
	return [code.substr(m.get_start(), i - m.get_start()), code.substr(m.get_end(), i - m.get_end() - 1)]


## 在主输出节点上按端口名查找输入引脚索引，找不到返回 -1
func _find_output_pin(vs: VisualShader, port_name: String) -> int:
	var outn := vs.get_node(FRAG, 0) as VisualShaderNodeOutput
	if outn == null:
		return -1
	for i in outn.get_input_port_count():
		if outn.get_input_port_name(i).to_lower() == port_name.to_lower():
			return i
	return -1


## 按 uniform 类型创建 Parameter 节点，返回 [节点, 表达式输入端口类型]（采样器为 -1），不支持则返回 []
func _make_param(u: Dictionary) -> Array:
	var t: String = u.type
	var def: String = u.def
	var nums := []
	for m in _rx("-?\\d*\\.?\\d+").search_all(def):
		nums.append(m.get_string().to_float())
	if nums.size() == 1:
		nums = [nums[0], nums[0], nums[0], nums[0]] # vec4(1.0) 这种单值写法
	var c := nums.size()
	var n: VisualShaderNodeParameter
	var pt: int = VisualShaderNode.PORT_TYPE_SCALAR
	var v: Variant = null
	match t:
		"float":
			n = VisualShaderNodeFloatParameter.new()
			if c > 0: v = nums[0]
		"int":
			n = VisualShaderNodeIntParameter.new()
			pt = VisualShaderNode.PORT_TYPE_SCALAR_INT
			if c > 0: v = int(nums[0])
		"bool":
			n = VisualShaderNodeBooleanParameter.new()
			pt = VisualShaderNode.PORT_TYPE_BOOLEAN
			if not def.is_empty(): v = def.strip_edges() == "true"
		"vec2":
			n = VisualShaderNodeVec2Parameter.new()
			pt = VisualShaderNode.PORT_TYPE_VECTOR_2D
			if c >= 2: v = Vector2(nums[0], nums[1])
		"vec3":
			n = VisualShaderNodeVec3Parameter.new()
			pt = VisualShaderNode.PORT_TYPE_VECTOR_3D
			if c >= 3: v = Vector3(nums[0], nums[1], nums[2])
		"vec4":
			pt = VisualShaderNode.PORT_TYPE_VECTOR_4D
			if "source_color" in String(u.hint):
				n = VisualShaderNodeColorParameter.new()
				if c >= 4: v = Color(nums[0], nums[1], nums[2], nums[3])
			else:
				n = VisualShaderNodeVec4Parameter.new()
				if c >= 4: v = Vector4(nums[0], nums[1], nums[2], nums[3])
		"sampler2D":
			n = VisualShaderNodeTexture2DParameter.new()
			pt = -1
		_:
			return []
	n.parameter_name = u.name
	if v != null:
		n.set("default_value_enabled", true)
		n.set("default_value", v)
	return [n, pt]


## 拆分 shader 代码：Parameter 节点 + Expression(fragment 函数体) + GlobalExpression，并建立连线
func _build_graph(code_text: String, vs: VisualShader) -> void:
	var code := _rx("/\\*[\\s\\S]*?\\*/").sub(code_text, "", true) # 去注释
	code = _rx("//[^\\n]*").sub(code, "", true)
	var frag := _extract_function(code, "fragment")
	var body: String = frag[1] if not frag.is_empty() else ""
	var g := code # 全局部分：从整份代码里逐项剔除已处理内容
	if not frag.is_empty(): g = g.replace(frag[0], "")
	for f in ["vertex", "light"]:
		var fn := _extract_function(code, f)
		if not fn.is_empty():
			push_warning("VinoShaderConverter: 暂不转换 %s()，已忽略" % f)
			g = g.replace(fn[0], "")

	# 1. uniform -> Parameter 节点 + Expression 输入端口
	var expr := VisualShaderNodeExpression.new()
	var wires := [] # [参数节点ID, 表达式输入端口]
	var id := 4
	var y := -200
	var in_idx := 0
	for m in _rx(UNIFORM_RX).search_all(code):
		var uname := m.get_string(2)
		var u := {"type": m.get_string(1), "name": uname, "hint": m.get_string(3), "def": m.get_string(4)}
		var p := _make_param(u)
		if p.is_empty(): continue
		vs.add_node(FRAG, p[0], Vector2(-700, y), id)
		if p[1] != -1:
			var pname := "u_" + uname # 加前缀，避免与全局 uniform 同名冲突
			expr.add_input_port(in_idx, p[1], pname)
			body = _rx("(?<![\\w.])" + uname + "\\b").sub(body, pname, true)
			wires.append([id, in_idx])
			in_idx += 1
		id += 1
		y += 150

	# 2. 内置输出变量 -> Expression 输出端口（仅处理纯赋值，复合赋值/分量赋值的跳过）
	var outs := [] # [表达式输出端口, 主输出节点引脚]
	var pre := ""
	if vs.mode == Shader.MODE_SPATIAL:
		for k in OUT_TYPES:
			var kn: String = k
			var plain := _rx("(?<![\\w.])" + kn + "\\s*=(?!=)")
			var any_w := _rx("(?<![\\w.])" + kn + "(\\.\\w+)?\\s*[+\\-*/]?=(?!=)")
			var n_plain := plain.search_all(body).size()
			if n_plain == 0 or n_plain != any_w.search_all(body).size(): continue
			var pin := _find_output_pin(vs, kn)
			if pin == -1:
				push_warning("VinoShaderConverter: 主输出节点找不到 %s 引脚，保持直接写内置变量" % kn)
				continue
			body = plain.sub(body, "o_" + kn + " =", true)
			expr.add_output_port(outs.size(), OUT_TYPES[kn], "o_" + kn)
			pre += "o_%s = %s;\n" % [kn, kn] # 先继承内置变量当前值，防止条件赋值时被清零
			outs.append([outs.size(), pin])

	expr.expression = pre + body
	expr.size = Vector2(420, 260)
	vs.add_node(FRAG, expr, Vector2(-300, -200), 2)

	# 3. 全局部分（函数 / const / varying）
	for pat in [UNIFORM_RX, "shader_type\\s+\\w+\\s*;", "render_mode[^;]*;", "group_uniforms[^;]*;"]:
		g = _rx(pat).sub(g, "", true)
	if not g.strip_edges().is_empty():
		var ge := VisualShaderNodeGlobalExpression.new()
		ge.expression = g.strip_edges()
		ge.size = Vector2(420, 200)
		vs.add_node(FRAG, ge, Vector2(-300, -450), 3)

	# 4. 连线（失败时给出警告，通常是端口类型不匹配）
	for w in wires:
		if vs.connect_nodes(FRAG, w[0], 0, 2, w[1]) != OK:
			push_warning("VinoShaderConverter: 参数连线失败 node %d -> port %d" % [w[0], w[1]])
	for o in outs:
		if vs.connect_nodes(FRAG, 2, o[0], 0, o[1]) != OK:
			push_warning("VinoShaderConverter: 输出连线失败 port %d -> 主输出引脚 %d" % [o[0], o[1]])
