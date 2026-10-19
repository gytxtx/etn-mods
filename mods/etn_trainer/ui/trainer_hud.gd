extends CanvasLayer

## 常驻小 HUD：FPS / 在场敌人 / 回合 / 倒计时 / 当前加成摘要。
## 只在局内显示，可在面板「关于」页开关；视觉与面板一致（近黑底、1px 白框）。

const F_HUD := 8

const C_TEXT := Color(0.949, 0.957, 0.976, 1.0)

var core: Node = null

var _label: RichTextLabel = null
var _panel: PanelContainer = null
var _tick: float = 0.0
var _enabled: bool = false


func _ready() -> void:
	layer = 129
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func _build() -> void:
	# 贴右上角：左上角被本体 HUD（头像 / 生命 / 弹药）占用。
	var row := HBoxContainer.new()
	row.name = "HudRow"
	row.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	row.offset_left = 8.0
	row.offset_right = -8.0
	row.offset_top = 8.0
	row.offset_bottom = 34.0
	row.alignment = BoxContainer.ALIGNMENT_END
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)

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
	row.add_child(panel)

	_label = RichTextLabel.new()
	_label.name = "HudText"
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("normal_font_size", F_HUD)
	_label.add_theme_font_size_override("bold_font_size", F_HUD)
	_label.add_theme_color_override("default_color", C_TEXT)
	panel.add_child(_label)


func set_shown(on: bool) -> void:
	_enabled = on
	_sync_visibility()


## 只在局内显示；标题/主菜单/商店等没有玩家的场景自动隐藏。
func _sync_visibility() -> void:
	var show: bool = _enabled and core != null and core.in_game()
	if show == visible:
		return
	visible = show
	if show:
		_refresh()


func _process(delta: float) -> void:
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
