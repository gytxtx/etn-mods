extends VBoxContainer

## EasyTier 表单：房间码为主入口（房主生成 / 客机粘贴），入口与虚拟 IP 收进高级选项。
## 只产出连接计划；进程启动与就绪检测归连接后端——客机 IP 由 DHCP 自动分配，房主 IP 由 hostname 发现。
## 页面由官方联机菜单的 PageScroll 统一滚动，这里只提供内容高度的普通容器，不再自套滚动区。
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
var _advanced_panel: Control
var _advanced_toggle: Button
var _room_hint: Label
var _advanced_hint: Label
var _action_hint: Label
var _host_button: Button
var _join_button: Button
var _cancel_button: Button
var _generate_button: Button
var _copy_button: Button
var _public_node_button: Button = null
var actions: HBoxContainer
var _next_diagnostics: int = 0
var _busy_state: int = -1 # -1 表示尚未应用，保证首轮就按当前状态刷新按钮


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	_room_code_section()
	_advanced_section(cfg)
	_action_section()


func _room_code_section() -> void:
	var card: Dictionary = UIStyle.card(self, "coop_et_room_code")
	var body: VBoxContainer = card.content
	var row := UIStyle.row(body)
	var input := UIStyle.line_edit(row)
	input.max_length = 96
	input.placeholder_text = "XXXX-XXXX-XXXX-XXXX"
	input.tooltip_text = "coop_et_room_code_hint"
	_fields["room_code"] = input
	_controls.append(input)
	_generate_button = _button(row, "coop_et_generate", _generate_code, false)
	_copy_button = _button(row, "coop_et_copy", _copy_code, false)
	var hint_row := UIStyle.row(body)
	UIStyle.note(hint_row, "coop_et_quick_hint")
	_advanced_toggle = _button(hint_row, "coop_et_advanced", _toggle_advanced, false)
	_advanced_toggle.toggle_mode = true
	_advanced_toggle.tooltip_text = "coop_et_advanced_hint"
	_room_hint = _hint_label(body)
	_fields.room_code.text_changed.connect(func(_text: String): _clear_hint(_room_hint))


func _advanced_section(cfg: ConfigFile) -> void:
	var card: Dictionary = UIStyle.card(self, "coop_et_advanced")
	_advanced_panel = card.panel
	_advanced_panel.visible = false
	var body: VBoxContainer = card.content
	var seed_row := UIStyle.row(body)
	UIStyle.row_label(seed_row, "coop_et_seed")
	var seed := UIStyle.line_edit(seed_row)
	seed.text = str(cfg.get_value("connection", "seed", ""))
	seed.placeholder_text = "coop_et_seed_placeholder"
	seed.tooltip_text = "coop_et_seed_hint"
	_fields["seed"] = seed
	_controls.append(seed)
	_public_node_button = _button(seed_row, "coop_et_use_public_node", _use_public_node, false)
	_public_node_button.tooltip_text = "coop_et_use_public_node_hint"
	for key in ["port", "listen_port", "host_ip", "own_ip", "core_path"]:
		_field(body, key, cfg)
	_advanced_hint = _hint_label(body)
	UIStyle.note(body, "coop_et_advanced_hint")


func _action_section() -> void:
	var card: Dictionary = UIStyle.card(self, "coop_et_connection")
	var body: VBoxContainer = card.content
	actions = UIStyle.row(body)
	_host_button = _button(actions, "coop_et_host", _start.bind(true))
	_join_button = _button(actions, "coop_et_join", _start.bind(false))
	_cancel_button = _button(actions, "coop_et_cancel", _cancel)
	_action_hint = _hint_label(body)
	UIStyle.note(body, "coop_et_connection_hint")


func _field(body: Container, key: String, cfg: ConfigFile) -> void:
	var row := UIStyle.row(body)
	UIStyle.row_label(row, "coop_et_" + key)
	var input := UIStyle.line_edit(row)
	input.text = str(cfg.get_value("connection", key, DEFAULTS.get(key, "")))
	input.placeholder_text = str(PLACEHOLDERS.get(key, ""))
	input.tooltip_text = "coop_et_" + key + "_hint"
	_fields[key] = input
	_controls.append(input)


func _button(row: Container, key: String, callback: Callable, expand: bool = true) -> Button:
	var button := Button.new()
	button.set_script(Action)
	button.text = key
	if expand:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size.y = UIStyle.CONTROL_HEIGHT
	row.add_child(button)
	button.install_touch()
	button.pressed.connect(callback)
	_controls.append(button)
	return button


func get_interactive_controls() -> Array[Control]:
	return _controls


func _toggle_advanced() -> void:
	_advanced_panel.visible = _advanced_toggle.button_pressed


func _hint_label(parent: Container) -> Label:
	var label := UIStyle.note(parent, "")
	label.add_theme_color_override("font_color", UIStyle.ACCENT)
	label.visible = false
	return label


func _show_hint(hint: Label, key: String, error: bool = false) -> void:
	# 同一时间只保留一条就近提示，避免房间码/高级选项/连接三处重复显示同一错误。
	for other in [_room_hint, _advanced_hint, _action_hint]:
		if other != hint:
			_clear_hint(other)
	hint.text = key
	hint.visible = not key.is_empty()
	hint.add_theme_color_override("font_color", UIStyle.ERROR if error else UIStyle.ACCENT)


func _clear_hint(hint: Label) -> void:
	if hint == null or not is_instance_valid(hint):
		return
	hint.text = ""
	hint.visible = false


func _use_public_node() -> void:
	# 公益节点是显式选择：点了才写入，留空则不带入口（仅局域网/可直连时可用）。
	_fields.seed.text = PUBLIC_ENTRY
	_fields.seed.caret_column = PUBLIC_ENTRY.length()
	_show_hint(_advanced_hint, "coop_et_public_node_filled")


func _generate_code() -> void:
	var code: String = RoomCode.format(RoomCode.generate())
	_fields.room_code.text = code
	_fields.room_code.select_all()
	_clear_hint(_room_hint)
	_clear_hint(_action_hint)


func _copy_code() -> void:
	var code: String = RoomCode.normalize(_fields.room_code.text)
	if not RoomCode.is_valid(code):
		_show_hint(_room_hint, "coop_et_code_invalid", true)
		return
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		DisplayServer.clipboard_set(RoomCode.format(code))
	_show_hint(_room_hint, "coop_et_copied")


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
			_show_hint(_action_hint, "coop_et_code_invalid", true)
			return
		# 房主没填/填错时直接分配一个新码，避免"必须先点生成"的多余步骤。
		code = RoomCode.generate()
		_fields.room_code.text = RoomCode.format(code)
		_clear_hint(_room_hint)
	var derived: Dictionary = RoomCode.derive(code)
	if derived.is_empty():
		_show_hint(_action_hint, "coop_et_code_invalid", true)
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
		_clear_hint(_action_hint)
		_clear_hint(_room_hint)


func _cancel() -> void:
	var coop = controller
	if coop != null:
		coop.cancel_connection()
