extends VBoxContainer

## EasyTier 表单：房间码为主入口（房主生成 / 客机粘贴），入口与虚拟 IP 收进高级选项。
## 只产出连接计划；进程启动与就绪检测归连接后端——客机 IP 由 DHCP 自动分配，房主 IP 由 hostname 发现。
var controller: Node
const RoomCode := preload("res://mods/etn_coop_easytier/net/room_code.gd")
const Action := preload("res://mods/etn_coop_easytier/ui/action_button.gd")
const UIStyle := preload("res://mods/etn_coop_easytier/ui/ui_style.gd")
const SETTINGS_PATH := "user://etn_coop_easytier.cfg"
# 公益中继/会合节点（ETN 自建，已关闭 private mode、白名单放宽到 etn-coop*）。
# 默认不预填：入口留空＝不使用入口节点，只有玩家点「使用公益节点」才写入这里。
# 写域名而不是 IP：换机器/换机房只需改 DNS，不必再发版；域名只是别名，节点仍监听 11010 UDP+TCP。
const PUBLIC_ENTRY := "udp://et.saibamidori.com:11010"
# 只保存非凭据项：房间码含组网名称与密码，绝不落盘（与旧版不保存密码一致）。
const PERSIST_KEYS: Array[String] = ["seed", "port", "listen_port", "host_ip", "own_ip", "core_path"]
const PLACEHOLDERS := {
	"seed": "coop_et_seed_placeholder",
	"host_ip": "coop_et_auto",
	"own_ip": "coop_et_auto",
	"core_path": "coop_et_auto",
	"port": "24591",
	"listen_port": "11010",
}
# 全新配置下的默认值：端口/监听端口必须有值，否则会以 0 提交并被后端判为参数无效。
const DEFAULTS := {
	"port": "24591",
	"listen_port": "11010",
}
# 诊断轮询节流：每帧调用 diagnostics() 会持续构造字典；0.3 秒一次足够反映按钮可用性。
const DIAGNOSTICS_INTERVAL_MSEC: int = 300

var _fields: Dictionary = {}
var _controls: Array[Control] = []
var _advanced_card: Control
var _advanced_grid: GridContainer
var _generate_button: Button
var _copy_button: Button
var _advanced_toggle: Button
var _status_hint: Label
var _hint_row: HBoxContainer
var _host_button: Button
var _join_button: Button
var _cancel_button: Button
var actions: HBoxContainer
var _next_diagnostics: int = 0
var _busy_state: int = -1 # -1 表示尚未应用，保证首轮就按当前状态刷新按钮
var _public_node_button: Button = null


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 4)
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	_room_code_section()
	_advanced_toggle_button()
	_advanced_section(cfg)
	_action_row()


func _room_code_section() -> void:
	var body := _section("coop_et_room_code")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	body.add_child(row)
	var input := LineEdit.new()
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.custom_minimum_size = Vector2(0, 28)
	input.max_length = 96
	input.placeholder_text = "XXXX-XXXX-XXXX-XXXX"
	input.tooltip_text = "coop_et_room_code_hint"
	row.add_child(input)
	_fields["room_code"] = input
	_controls.append(input)
	_generate_button = _button(row, "coop_et_generate", _generate_code, false)
	_copy_button = _button(row, "coop_et_copy", _copy_code, false)
	var hint := Label.new()
	_hint_row = HBoxContainer.new()
	_hint_row.add_theme_constant_override("separation", 6)
	body.add_child(_hint_row)
	hint.text = "coop_et_quick_hint"
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", UIStyle.MUTED)
	_hint_row.add_child(hint)
	_status_hint = Label.new()
	_status_hint.visible = false
	_status_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_hint.add_theme_font_size_override("font_size", 10)
	_status_hint.add_theme_color_override("font_color", UIStyle.ACCENT)
	body.add_child(_status_hint)


func _advanced_toggle_button() -> void:
	_advanced_toggle = Button.new()
	_advanced_toggle.set_script(Action)
	_advanced_toggle.text = "coop_et_advanced"
	_advanced_toggle.tooltip_text = "coop_et_advanced_hint"
	_advanced_toggle.toggle_mode = true
	_advanced_toggle.custom_minimum_size.y = 28
	_advanced_toggle.add_theme_font_size_override("font_size", 10)
	_hint_row.add_child(_advanced_toggle)
	_advanced_toggle.install_touch()
	_advanced_toggle.pressed.connect(_toggle_advanced)
	_controls.append(_advanced_toggle)


func _advanced_section(cfg: ConfigFile) -> void:
	var body := VBoxContainer.new()
	body.name = "AdvancedOptions"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 4)
	add_child(body)
	_advanced_card = body
	body.visible = false
	_public_node_button = _field(body, "seed", cfg, "coop_et_use_public_node", _use_public_node)
	_advanced_grid = GridContainer.new()
	_advanced_grid.columns = 2
	_advanced_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_advanced_grid.add_theme_constant_override("h_separation", 6)
	_advanced_grid.add_theme_constant_override("v_separation", 4)
	body.add_child(_advanced_grid)
	for key in ["port", "listen_port", "host_ip", "own_ip"]:
		_field(_advanced_grid, key, cfg)
	_field(body, "core_path", cfg)
	body.resized.connect(_update_advanced_columns)
	_update_advanced_columns.call_deferred()


func _update_advanced_columns() -> void:
	_advanced_grid.columns = 2 if _advanced_grid.get_parent().size.x >= 400.0 else 1


func _action_row() -> void:
	if actions == null:
		actions = HBoxContainer.new()
		add_child(actions)
	actions.add_theme_constant_override("separation", 6)
	_host_button = _button(actions, "coop_et_host", _start.bind(true))
	_host_button.theme_type_variation = &"CoopPrimary"
	_join_button = _button(actions, "coop_et_join", _start.bind(false))
	_cancel_button = _button(actions, "coop_et_cancel", _cancel)


func _section(title_key: String) -> VBoxContainer:
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	add_child(body)
	var title := Label.new()
	title.text = title_key
	body.add_child(title)
	return body


func _field(body: Container, key: String, cfg: ConfigFile, trailing_key: String = "", trailing_action: Callable = Callable()) -> Button:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 6)
	body.add_child(row)
	var label := Label.new()
	label.custom_minimum_size = Vector2(110, 26)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text = "coop_et_" + key
	label.add_theme_font_size_override("font_size", 10)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)
	var input := LineEdit.new()
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.custom_minimum_size = Vector2(0, 26)
	input.text = str(cfg.get_value("connection", key, DEFAULTS.get(key, "")))
	input.placeholder_text = str(PLACEHOLDERS.get(key, ""))
	input.tooltip_text = "coop_et_" + key + "_hint"
	row.add_child(input)
	_fields[key] = input
	_controls.append(input)
	# 可选同行按钮（目前只有入口节点用）：公益节点必须显式点击才写入，默认留空。
	if trailing_key == "":
		return null
	var trailing := _button(row, trailing_key, trailing_action, false)
	trailing.tooltip_text = trailing_key + "_hint"
	return trailing


func _button(row: HBoxContainer, key: String, callback: Callable, expand: bool = true) -> Button:
	var button := Button.new()
	button.set_script(Action)
	button.text = key
	if expand:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size.y = 28
	button.add_theme_font_size_override("font_size", 10)
	row.add_child(button)
	button.install_touch()
	button.pressed.connect(callback)
	_controls.append(button)
	return button


func get_interactive_controls() -> Array[Control]:
	return _controls


func _toggle_advanced() -> void:
	_advanced_card.visible = _advanced_toggle.button_pressed
	_update_advanced_columns.call_deferred()


func _set_hint(message: String) -> void:
	_status_hint.text = message
	_status_hint.visible = not message.is_empty()


func _use_public_node() -> void:
	# 公益节点是显式选择：点了才写入，留空则不带入口（仅局域网/可直连时可用）。
	_fields.seed.text = PUBLIC_ENTRY
	_fields.seed.caret_column = PUBLIC_ENTRY.length()
	_set_hint("coop_et_public_node_filled")


func _generate_code() -> void:
	var code: String = RoomCode.format(RoomCode.generate())
	_fields.room_code.text = code
	_fields.room_code.select_all()
	_set_hint("")


func _copy_code() -> void:
	var code: String = RoomCode.normalize(_fields.room_code.text)
	if not RoomCode.is_valid(code):
		_set_hint("coop_et_code_invalid")
		return
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		DisplayServer.clipboard_set(RoomCode.format(code))
	_set_hint("coop_et_copied")


func _process(_delta: float) -> void:
	# 节流后再读诊断：避免每帧构造字典，同时保证状态一变就刷新（最迟 0.3 秒）。
	var now: int = Time.get_ticks_msec()
	if now < _next_diagnostics:
		return
	_next_diagnostics = now + DIAGNOSTICS_INTERVAL_MSEC
	var coop = controller
	var busy: bool = coop != null and int(coop.diagnostics().get("pid", 0)) > 0
	var busy_state: int = 1 if busy else 0
	if busy_state == _busy_state:
		return
	_busy_state = busy_state
	_host_button.disabled = busy
	_join_button.disabled = busy
	_cancel_button.disabled = not busy
	_generate_button.disabled = busy
	_copy_button.disabled = busy
	if _public_node_button != null:
		_public_node_button.disabled = busy
	# 高级设置可在连接期间展开查看；只锁定会改变连接参数的输入和操作。
	for field in _fields.values():
		field.editable = not busy


func _start(hosting: bool) -> void:
	var coop = controller
	if coop == null:
		return
	var parsed: Dictionary = RoomCode.parse(_fields.room_code.text)
	var code: String = str(parsed.code)
	if not bool(parsed.valid):
		if not hosting:
			_set_hint("coop_et_code_invalid")
			return
		# 房主没填/填错时直接分配一个新码，避免"必须先点生成"的多余步骤。
		code = RoomCode.generate()
		_fields.room_code.text = RoomCode.format(code)
	var derived: Dictionary = RoomCode.derive(code)
	if derived.is_empty():
		_set_hint("coop_et_code_invalid")
		return
	var plan: Dictionary = {"room_code": code, "network_name": derived.network_name, "network_secret": derived.network_secret}
	for key in PERSIST_KEYS:
		var value: String = _fields[key].text.strip_edges()
		if key == "port" or key == "listen_port":
			plan[key] = value.to_int() if value.is_valid_int() else 0
		else:
			plan[key] = value
	# 入口优先级：粘贴的「码@入口」→ 高级选项里填的（含「使用公益节点」写入的）；都不填＝不使用入口节点。
	var explicit_seed: String = str(parsed.seed).strip_edges()
	if explicit_seed.is_empty():
		explicit_seed = str(_fields.seed.text).strip_edges()
	plan["seed"] = explicit_seed
	var cfg := ConfigFile.new()
	for key in PERSIST_KEYS:
		cfg.set_value("connection", key, explicit_seed if key == "seed" else str(_fields[key].text).strip_edges())
	cfg.save(SETTINGS_PATH)
	if coop.start_connection(plan, hosting):
		_set_hint("")


func _cancel() -> void:
	var coop = controller
	if coop != null:
		coop.cancel_connection()
