extends CanvasLayer

## 常驻小 HUD：FPS / 在场敌人 / 回合 / 当前倍率摘要。可在面板「关于」页开关。

var core: Node = null

var _label: Label = null
var _tick: float = 0.0


func _ready() -> void:
	layer = 129
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_TOP_LEFT)
	margin.offset_left = 6.0
	margin.offset_top = 6.0
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.5)
	style.content_margin_left = 5
	style.content_margin_right = 5
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(panel)

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 8)
	_label.add_theme_color_override("font_color", Color(0.82, 1.0, 0.86, 1.0))
	_label.text = ""
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_label)


func set_shown(on: bool) -> void:
	visible = on
	if on:
		_refresh()


func _process(delta: float) -> void:
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
	var t := get_tree()
	var count: int = 0
	if t != null and is_instance_valid(PoolManager):
		count = PoolManager.get_active_enemies().size()
	var round_num: int = 0
	var rt = null
	if core != null:
		rt = core.get_round_timer()
	if rt != null:
		round_num = int(rt.get("now_round_num"))
	var parts: Array = []
	parts.append("FPS %d" % Engine.get_frames_per_second())
	parts.append("敌 %d" % count)
	parts.append("第 %d 回合" % round_num)
	if core != null:
		var bits: Array = []
		if not is_equal_approx(core.speed_mult, 1.0):
			bits.append("速%.1fx" % core.speed_mult)
		if not is_equal_approx(core.fire_rate_mult, 1.0):
			bits.append("射%.1fx" % core.fire_rate_mult)
		if not is_equal_approx(core.damage_mult, 1.0):
			bits.append("伤%.1fx" % core.damage_mult)
		if core.invincible:
			bits.append("无敌")
		if core.one_hit_kill:
			bits.append("秒杀")
		if not bits.is_empty():
			parts.append(" | ".join(bits))
	_label.text = "trainer  " + "  |  ".join(parts)
