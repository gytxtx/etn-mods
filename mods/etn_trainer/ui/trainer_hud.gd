extends CanvasLayer

## 常驻小 HUD：FPS / 在场敌人 / 回合 / 倒计时 / 当前加成摘要。
## 只在局内显示，可在面板「关于」页开关；视觉与面板一致（近黑底、1px 白框）。
##
## 移动端（`mobile == true`）：没有 F1，HUD 行左侧增加常驻「修改器」按钮作为入口；
## 按钮与 HUD 在面板之外始终存在，主菜单 / 商店也能打开修改器。
## 局内右上角要给本体暂停按钮（TouchScreenButton，约 640x360 下 x 595–627）让位，
## 所以整行右缩进 52；暂停（`get_tree().paused`）时隐藏按钮，避免压在暂停菜单上。

signal open_requested

const F_HUD := 8

const C_TEXT := Color(0.949, 0.957, 0.976, 1.0)
const C_GOLD := Color(1.0, 0.937, 0.761, 1.0)
const C_GOLD_DIM := Color(0.788, 0.659, 0.416, 1.0)
const C_LINE := Color(1.0, 1.0, 1.0, 0.2)

## 移动端：由 entry 在 `_ready` 之前按 `OS.has_feature("mobile")` 赋值。
var mobile: bool = false
var core: Node = null

var _label: RichTextLabel = null
var _panel: PanelContainer = null
var _row: HBoxContainer = null
var _open_button: Button = null
var _tick: float = 0.0
var _enabled: bool = false
var _panel_open: bool = false


func _ready() -> void:
	layer = 129
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_sync_visibility()


func _build() -> void:
	# 贴右上角：左上角被本体 HUD（头像 / 生命 / 弹药）占用。
	_row = HBoxContainer.new()
	_row.name = "HudRow"
	_row.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_row.offset_left = 8.0
	_row.offset_right = -8.0
	_row.offset_top = 8.0
	_row.offset_bottom = 34.0
	_row.alignment = BoxContainer.ALIGNMENT_END
	_row.add_theme_constant_override("separation", 6)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)

	if mobile:
		_build_open_button()

	_panel = PanelContainer.new()
	var panel := _panel
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.025, 0.035, 0.78)
	sb.border_color = Color(1, 1, 1, 0.20)
	sb.set_border_width_all(1)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	sb.anti_aliasing = false
	panel.add_theme_stylebox_override("panel", sb)
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(panel)

	_label = RichTextLabel.new()
	_label.name = "HudText"
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font_size: int = 9 if mobile else F_HUD
	_label.add_theme_font_size_override("normal_font_size", font_size)
	_label.add_theme_font_size_override("bold_font_size", font_size)
	_label.add_theme_color_override("default_color", C_TEXT)
	panel.add_child(_label)


## 移动端入口按钮：普通 Button，4.7 的 BaseButton 原生处理 InputEventScreenTouch。
## 局内右缩进 52 让出本体暂停按钮；按钮只在未暂停时显示。
func _build_open_button() -> void:
	_open_button = Button.new()
	_open_button.name = "OpenButton"
	_open_button.text = "修改器"
	_open_button.focus_mode = Control.FOCUS_NONE
	_open_button.custom_minimum_size = Vector2(0, 22)
	_open_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_open_button.add_theme_font_size_override("font_size", 9)

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.02, 0.025, 0.035, 0.78)
	normal.border_color = C_LINE
	normal.set_border_width_all(1)
	normal.content_margin_left = 7
	normal.content_margin_right = 7
	normal.anti_aliasing = false

	var hover: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.13, 0.145, 0.18, 0.92)
	hover.border_color = C_GOLD_DIM

	var held: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	held.bg_color = C_GOLD_DIM
	held.border_color = C_GOLD_DIM

	_open_button.add_theme_stylebox_override("normal", normal)
	_open_button.add_theme_stylebox_override("hover", hover)
	_open_button.add_theme_stylebox_override("pressed", held)
	_open_button.add_theme_color_override("font_color", C_GOLD)
	_open_button.add_theme_color_override("font_hover_color", C_GOLD)
	_open_button.add_theme_color_override("font_pressed_color", Color(0.08, 0.07, 0.05, 1))
	_open_button.add_theme_color_override("font_focus_color", C_GOLD)
	_open_button.pressed.connect(func() -> void: open_requested.emit())
	_row.add_child(_open_button)


func set_shown(on: bool) -> void:
	_enabled = on
	_sync_visibility()


## 面板打开时隐藏入口按钮（菜单里不会被面板遮住，避免屏幕边缘残留一个按钮）。
func set_panel_open(on: bool) -> void:
	_panel_open = on
	_sync_visibility()


## 局内才显示 HUD 文本；移动端按钮在菜单里也显示。
## 移动端按钮在暂停（本体暂停菜单 / 升级页 / 面板自己）时隐藏。
func _sync_visibility() -> void:
	var in_game: bool = core != null and core.in_game()
	var paused: bool = get_tree() != null and get_tree().paused
	var text_on: bool = _enabled and in_game
	var button_on: bool = mobile and _open_button != null and not paused and not _panel_open

	if _panel != null:
		_panel.visible = text_on
	if _open_button != null:
		_open_button.visible = button_on
	if _row != null:
		_row.offset_right = -52.0 if (mobile and in_game) else -8.0

	var want: bool = text_on or button_on
	if want == visible:
		return
	visible = want
	if want and text_on:
		_refresh()


func _process(delta: float) -> void:
	# 移动端即使关闭 HUD 文本，也要维持按钮的显隐（暂停 / 场景切换）。
	if mobile:
		_sync_visibility()
	if not _enabled:
		return
	_sync_visibility()
	if not visible:
		return
	_tick += delta
	if _tick < 0.25:
		return
	_tick = 0.0
	_refresh()


func _refresh() -> void:
	if _label == null:
		return
	var parts: PackedStringArray = []
	parts.append("[color=#FFEFC2]TRAINER[/color]")

	var fps: int = Engine.get_frames_per_second()
	var fps_color := "#B0ED47"
	if fps < 30:
		fps_color = "#E4384C"
	elif fps < 55:
		fps_color = "#C9A86A"
	parts.append("[color=#8C96A8]FPS[/color] [color=%s]%d[/color]" % [fps_color, fps])

	var locked: bool = core != null and core.is_locked()
	if locked:
		parts.append("[color=#E4384C]联机只读[/color]")
	else:
		var in_game: bool = core != null and core.in_game()
		if in_game:
			var count := 0
			if is_instance_valid(PoolManager):
				count = PoolManager.get_active_enemies().size()
			parts.append("[color=#8C96A8]敌[/color] %d" % count)
			var rt = core.get_round_timer()
			var rnd := 0
			var left := 0.0
			if rt != null:
				rnd = int(rt.get("now_round_num"))
				if rt.get("timer") != null:
					left = float(rt.timer.time_left)
			parts.append("[color=#8C96A8]回合[/color] %d" % rnd)
			parts.append("[color=#8C96A8]倒计时[/color] %s" % _fmt_time(left))
			var bits: PackedStringArray = []
			_add_mult(bits, "移", core.speed_mult)
			_add_mult(bits, "射", core.fire_rate_mult)
			_add_mult(bits, "伤", core.damage_mult)
			_add_mult(bits, "拾", core.pickup_mult)
			if core.armor_add > 0.0:
				bits.append("甲+%d" % int(round(core.armor_add)))
			if core.armor_cap > 0.0:
				bits.append("减+%d%%" % int(round(core.armor_cap * 100.0)))
			if core.invincible:
				bits.append("无敌")
			if core.one_hit_kill:
				bits.append("秒杀")
			if bits.is_empty():
				parts.append("[color=#8C96A8]无加成[/color]")
			else:
				parts.append("[color=#B0ED47]%s[/color]" % " ".join(bits))
		else:
			parts.append("[color=#8C96A8]菜单[/color]")

	if get_tree() != null and get_tree().paused:
		parts.append("[color=#C9A86A]暂停[/color]")

	_label.text = "  ".join(parts)


func _add_mult(bits: PackedStringArray, name: String, value: float) -> void:
	if is_equal_approx(value, 1.0):
		return
	if is_equal_approx(value, roundf(value)):
		bits.append("%s×%d" % [name, int(roundf(value))])
	else:
		bits.append("%s×%.1f" % [name, value])


func _fmt_time(seconds: float) -> String:
	var total := maxi(0, int(ceil(seconds)))
	return "%02d:%02d" % [total / 60, total % 60]
