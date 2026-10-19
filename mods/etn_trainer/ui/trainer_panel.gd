extends CanvasLayer

## 修改器面板（纯代码构建，不使用场景）。
##
## 视觉沿用本体像素 UI：近黑底 + 1px 白框 + 暖金标题（#FFEFC2 / #C9A86A）+
## 绿色开启态（#B0ED47）+ 红色写入警告（#E4384C）。
## 基准分辨率 640x360（窗口 720p 由 stretch=canvas_items 放大 2x），
## 所以所有尺寸/字号都按 640x360 设计，面板必须小于该视口。

const CoreScript := preload("res://mods/etn_trainer/core/trainer_core.gd")

const MOD_VERSION := "0.2.3"

## [key, 页签文字, 页面副标题]
const TABS := [
	["stats", "数值", "倍率与开关"],
	["res", "资源", "金币 / 青辉石"],
	["unlock", "解锁", "角色 / 服装 / 支援"],
	["support", "辅助", "减伤 / 护甲 / 治疗"],
	["debug", "调试", "场景与敌人"],
	["about", "关于", "设置与快捷键"],
]

## 只在对局中才有意义的页签
const IN_GAME_TABS := ["stats", "support", "debug"]

# ---- 调色板（对齐本体像素 UI）----
const C_BG := Color(0.043, 0.047, 0.059, 0.985)
const C_CARD := Color(0.086, 0.094, 0.118, 1.0)
const C_CARD_HI := Color(0.13, 0.145, 0.18, 1.0)
const C_TEXT := Color(0.949, 0.957, 0.976, 1.0)
const C_MUTED := Color(0.549, 0.588, 0.667, 1.0)
const C_GOLD := Color(1.0, 0.937, 0.761, 1.0)
const C_GOLD_DIM := Color(0.788, 0.659, 0.416, 1.0)
const C_GREEN := Color(0.690, 0.929, 0.278, 1.0)
const C_RED := Color(0.894, 0.220, 0.298, 1.0)
const C_LINE := Color(1.0, 1.0, 1.0, 0.16)
const C_LINE_SOFT := Color(1.0, 1.0, 1.0, 0.08)
const C_DIM := Color(0.0, 0.0, 0.0, 0.62)
const C_BLACK := Color(0.0, 0.0, 0.0, 0.0)

# ---- 字号（设计分辨率）----
const F_TITLE := 13
const F_PAGE := 11
const F_BODY := 9
const F_SMALL := 8
const F_MICRO := 7

const FOOTER_HINT := "F1 开关 · Esc 关闭 · 1–6 切页 · 拖拽标题栏移动"

var core: Node = null
var hud: CanvasLayer = null

var _root: Control
var _dim: ColorRect
var _panel: Panel
var _margin: MarginContainer
var _col: VBoxContainer
var _header: HBoxContainer
var _body: HBoxContainer

var _status_chip: PanelContainer
var _status_dot: ColorRect
var _status_text: Label
var _status_key: String = ""
var _fps_chip: PanelContainer
var _fps_label: Label
var _fps_color: Color = Color(0, 0, 0, 0)

var _tab_buttons: Dictionary = {}
var _pages_holder: MarginContainer
var _pages: Dictionary = {}
var _overlay: Control
var _overlay_title: Label
var _overlay_desc: Label
var _overlay_hint: Label

var _footer_label: Label
var _footer_hint: Label
var _toast_left: float = 0.0

var _confirm_layer: Control
var _confirm_title: Label
var _confirm_body: Label
var _confirm_ok: Button
var _confirm_cancel: Button
var _confirm_cb: Callable = Callable()
var _focus_before_confirm: Control = null

var _sliders: Dictionary = {}
var _checks: Dictionary = {}
var _live: Dictionary = {}
var _current_tab: String = "stats"

var _coin_value: Label
var _coin_note: Label
var _coin_actions: VBoxContainer
var _pyro_value: Label

var _hp_bar: ProgressBar
var _hp_text: Label
var _hp_color: String = ""
var _armor_cap_text: Label
var _support_tiles: Dictionary = {}

var _unlock_rows: Dictionary = {}
var _unlock_cache: Dictionary = {}

var _enemy_grid: GridContainer
var _enemy_search: LineEdit
var _enemy_count: Label
var _enemy_empty: Label
var _enemy_cards: Array = []
var _enemy_filtered: Array = []
var _enemy_built: bool = false

var _tile_enemies: Label
var _tile_round: Label
var _tile_left: Label

var _syncing: bool = false
var _paused_by_us: bool = false
var _self_lock: bool = false
var _external_lock: bool = false
var _prev_mouse: int = Input.MOUSE_MODE_VISIBLE
var _dragging: bool = false
var _drag_off: Vector2 = Vector2.ZERO
var _tick: float = 0.0
var _last_locked: bool = false
var _last_ingame: bool = false


func _ready() -> void:
	layer = 200
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_show_tab(_current_tab)
	_last_locked = core != null and core.is_locked()
	_last_ingame = core != null and core.in_game()
	if core != null and core.has_signal("cheats_reset"):
		if not core.cheats_reset.is_connected(_on_cheats_reset):
			core.cheats_reset.connect(_on_cheats_reset)
	get_viewport().size_changed.connect(_layout)


func _exit_tree() -> void:
	if _paused_by_us and not _external_lock:
		_paused_by_us = false
		var t := get_tree()
		if t != null:
			t.paused = false
			_self_lock = true
			GameEvents.emit_pause_lock(false)
			_self_lock = false
		Input.mouse_mode = _prev_mouse


# ============================================================ 构建 · 外壳

func _build() -> void:
	_root = Control.new()
	_root.name = "TrainerRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.color = C_DIM
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_dim)

	_panel = Panel.new()
	_panel.name = "Panel"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.size = Vector2(600, 336)
	_panel.add_theme_stylebox_override("panel", _sb(C_BG, Color(1, 1, 1, 0.92), 1, 0, 0, 0, 0))
	_panel.gui_input.connect(_on_panel_input)
	_root.add_child(_panel)

	var top_bar := ColorRect.new()
	top_bar.name = "Accent"
	top_bar.color = C_GOLD
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_bottom = 2.0
	_panel.add_child(top_bar)

	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_margin.add_theme_constant_override("margin_left", 8)
	_margin.add_theme_constant_override("margin_right", 8)
	_margin.add_theme_constant_override("margin_top", 6)
	_margin.add_theme_constant_override("margin_bottom", 5)
	_panel.add_child(_margin)

	_col = VBoxContainer.new()
	_col.add_theme_constant_override("separation", 3)
	_margin.add_child(_col)

	_build_header()
	_col.add_child(_hline(1, C_LINE))
	_build_body()
	_build_footer()
	_build_confirm()


func _build_header() -> void:
	_header = HBoxContainer.new()
	_header.name = "Header"
	_header.custom_minimum_size = Vector2(0, 22)
	_header.add_theme_constant_override("separation", 6)
	_header.mouse_filter = Control.MOUSE_FILTER_STOP
	_header.gui_input.connect(_on_header_input)
	_col.add_child(_header)

	var title := Label.new()
	title.text = "修改器"
	title.add_theme_font_size_override("font_size", F_TITLE)
	title.add_theme_color_override("font_color", C_GOLD)
	_header.add_child(title)

	var tag := Label.new()
	tag.text = "TRAINER v" + MOD_VERSION
	tag.add_theme_font_size_override("font_size", F_MICRO)
	tag.add_theme_color_override("font_color", C_MUTED)
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_header.add_child(tag)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header.add_child(spacer)

	_fps_chip = PanelContainer.new()
	_fps_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fps_chip.add_theme_stylebox_override("panel", _sb(Color(0, 0, 0, 0.25), C_LINE, 1, 5, 1, 5, 1))
	_header.add_child(_fps_chip)

	_fps_label = Label.new()
	_fps_label.text = "FPS —"
	_fps_label.add_theme_font_size_override("font_size", F_MICRO)
	_fps_label.add_theme_color_override("font_color", C_MUTED)
	_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fps_chip.add_child(_fps_label)

	_status_chip = PanelContainer.new()
	_status_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header.add_child(_status_chip)

	var chip_row := HBoxContainer.new()
	chip_row.add_theme_constant_override("separation", 4)
	chip_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_chip.add_child(chip_row)

	_status_dot = ColorRect.new()
	_status_dot.custom_minimum_size = Vector2(5, 5)
	_status_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_status_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip_row.add_child(_status_dot)

	_status_text = Label.new()
	_status_text.text = "主菜单"
	_status_text.add_theme_font_size_override("font_size", F_MICRO)
	_status_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip_row.add_child(_status_text)

	var keycap := PanelContainer.new()
	keycap.add_theme_stylebox_override("panel", _sb(C_BLACK, C_LINE, 1, 5, 1, 5, 1))
	keycap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header.add_child(keycap)

	var kl := Label.new()
	kl.text = "F1"
	kl.add_theme_font_size_override("font_size", F_MICRO)
	kl.add_theme_color_override("font_color", C_MUTED)
	keycap.add_child(kl)

	var close := _button("关闭", "ghost", F_SMALL, 40, 18)
	close.tooltip_text = "关闭面板（F1 / Esc）"
	close.pressed.connect(close_panel)
	_header.add_child(close)

	_update_status_chip("menu")


func _build_body() -> void:
	_body = HBoxContainer.new()
	_body.name = "Body"
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 6)
	_col.add_child(_body)

	var rail := VBoxContainer.new()
	rail.name = "Tabs"
	rail.custom_minimum_size = Vector2(64, 0)
	rail.add_theme_constant_override("separation", 1)
	_body.add_child(rail)

	for entry in TABS:
		var key := str(entry[0])
		var b := _button(str(entry[1]), "tab", F_BODY, 0, 24)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_show_tab.bind(key))
		rail.add_child(b)
		_tab_buttons[key] = b

	var rail_spacer := Control.new()
	rail_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rail_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rail.add_child(rail_spacer)

	var rail_ver := Label.new()
	rail_ver.text = "v" + MOD_VERSION
	rail_ver.add_theme_font_size_override("font_size", F_MICRO)
	rail_ver.add_theme_color_override("font_color", C_MUTED)
	rail_ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rail_ver.modulate.a = 0.7
	rail.add_child(rail_ver)

	var vsep := ColorRect.new()
	vsep.color = C_LINE
	vsep.custom_minimum_size = Vector2(1, 0)
	vsep.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vsep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(vsep)

	_pages_holder = MarginContainer.new()
	_pages_holder.name = "Pages"
	_pages_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pages_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_pages_holder.add_theme_constant_override("margin_left", 2)
	_body.add_child(_pages_holder)

	_build_stats_page()
	_build_resource_page()
	_build_unlock_page()
	_build_support_page()
	_build_debug_page()
	_build_about_page()
	_build_overlay()


func _build_footer() -> void:
	_col.add_child(_hline(1, C_LINE_SOFT))
	var row := HBoxContainer.new()
	row.name = "Footer"
	row.custom_minimum_size = Vector2(0, 13)
	row.add_theme_constant_override("separation", 8)
	_col.add_child(row)

	_footer_hint = Label.new()
	_footer_hint.text = FOOTER_HINT
	_footer_hint.add_theme_font_size_override("font_size", F_MICRO)
	_footer_hint.add_theme_color_override("font_color", C_MUTED)
	_footer_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_footer_hint.clip_text = true
	row.add_child(_footer_hint)

	_footer_label = Label.new()
	_footer_label.text = ""
	_footer_label.add_theme_font_size_override("font_size", F_MICRO)
	_footer_label.add_theme_color_override("font_color", C_GREEN)
	_footer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_footer_label.custom_minimum_size = Vector2(220, 0)
	_footer_label.clip_text = true
	_footer_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(_footer_label)


func _build_confirm() -> void:
	_confirm_layer = Control.new()
	_confirm_layer.name = "ConfirmLayer"
	_confirm_layer.visible = false
	_confirm_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_child(_confirm_layer)

	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.66)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirm_layer.add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	_confirm_layer.add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(348, 0)
	card.add_theme_stylebox_override("panel", _sb(C_BG, C_GOLD_DIM, 1, 10, 8, 10, 8))
	center.add_child(card)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	card.add_child(v)

	_confirm_title = Label.new()
	_confirm_title.text = "需要确认"
	_confirm_title.add_theme_font_size_override("font_size", F_PAGE)
	_confirm_title.add_theme_color_override("font_color", C_GOLD)
	v.add_child(_confirm_title)

	_confirm_body = Label.new()
	_confirm_body.text = ""
	_confirm_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_body.add_theme_font_size_override("font_size", F_BODY)
	_confirm_body.add_theme_color_override("font_color", C_TEXT)
	v.add_child(_confirm_body)

	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_END
	btns.add_theme_constant_override("separation", 6)
	v.add_child(btns)

	_confirm_cancel = _button("取消", "ghost", F_SMALL, 62, 19)
	_confirm_cancel.pressed.connect(_hide_confirm)
	btns.add_child(_confirm_cancel)

	_confirm_ok = _button("确认", "primary", F_SMALL, 68, 19)
	_confirm_ok.pressed.connect(_on_confirm)
	btns.add_child(_confirm_ok)


func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.name = "Unavailable"
	_overlay.visible = false
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_pages_holder.add_child(_overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	_overlay.add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(320, 0)
	card.add_theme_stylebox_override("panel", _sb(C_CARD, C_LINE, 1, 14, 12, 14, 12))
	center.add_child(card)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	card.add_child(v)

	_overlay_title = Label.new()
	_overlay_title.text = "需要在对局中"
	_overlay_title.add_theme_font_size_override("font_size", F_PAGE)
	_overlay_title.add_theme_color_override("font_color", C_GOLD)
	v.add_child(_overlay_title)

	_overlay_desc = Label.new()
	_overlay_desc.text = "该页会直接作用于当前玩家与场景。"
	_overlay_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_overlay_desc.custom_minimum_size = Vector2(292, 0)
	_overlay_desc.add_theme_font_size_override("font_size", F_SMALL)
	_overlay_desc.add_theme_color_override("font_color", C_TEXT)
	v.add_child(_overlay_desc)

	_overlay_hint = Label.new()
	_overlay_hint.text = "进入对局后自动解除。"
	_overlay_hint.add_theme_font_size_override("font_size", F_MICRO)
	_overlay_hint.add_theme_color_override("font_color", C_MUTED)
	v.add_child(_overlay_hint)

	var close := _button("关闭面板", "ghost", F_MICRO, 76, 17)
	close.pressed.connect(close_panel)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(row)
	row.add_child(close)


# ============================================================ 构建 · 各页

func _new_page(key: String) -> VBoxContainer:
	var page := MarginContainer.new()
	page.name = "Page_" + key
	page.visible = false
	page.add_theme_constant_override("margin_right", 1)
	_pages_holder.add_child(page)

	var box := VBoxContainer.new()
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)
	page.add_child(box)

	_pages[key] = page
	return box


func _page_header(box: VBoxContainer, title: String, desc: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)

	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", F_PAGE)
	t.add_theme_color_override("font_color", C_GOLD)
	row.add_child(t)

	var d := Label.new()
	d.text = desc
	d.add_theme_font_size_override("font_size", F_MICRO)
	d.add_theme_color_override("font_color", C_MUTED)
	d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	d.clip_text = true
	d.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(d)


func _section(parent: Node, text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.custom_minimum_size = Vector2(0, 10)
	parent.add_child(row)

	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", F_MICRO)
	l.add_theme_color_override("font_color", C_GOLD_DIM)
	row.add_child(l)

	var line := ColorRect.new()
	line.color = C_LINE_SOFT
	line.custom_minimum_size = Vector2(0, 1)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)


func _build_stats_page() -> void:
	var p := _new_page("stats")
	_page_header(p, "数值", "倍率注入 · 关闭即还原 · 不写存档")

	# 预设
	var pr := HBoxContainer.new()
	pr.add_theme_constant_override("separation", 5)
	p.add_child(pr)

	var pl := Label.new()
	pl.text = "预设"
	pl.add_theme_font_size_override("font_size", F_MICRO)
	pl.add_theme_color_override("font_color", C_MUTED)
	pl.custom_minimum_size = Vector2(28, 0)
	pl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pr.add_child(pl)

	for item in [["轻度", "light"], ["爽玩", "fun"], ["全开", "all"]]:
		var b := _button(str(item[0]), "chip", F_SMALL, 52, 18)
		b.pressed.connect(_apply_preset.bind(str(item[1])))
		pr.add_child(b)

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pr.add_child(sp)

	var reset := _button("复位", "ghost", F_MICRO, 40, 18)
	reset.tooltip_text = "四项倍率归 1，并关闭无敌/秒杀"
	reset.pressed.connect(_reset_stats)
	pr.add_child(reset)

	_section(p, "倍率")
	_slider_row(p, "speed", "移速", 0.1, 10.0, 0.1, [1, 2, 5, 10])
	_slider_row(p, "fire", "射速", 0.1, 10.0, 0.1, [1, 2, 5, 10])
	_slider_row(p, "damage", "伤害", 0.1, 10.0, 0.1, [1, 2, 5, 10])
	_slider_row(p, "pickup", "拾取", 0.1, 10.0, 0.1, [1, 2, 5, 10])

	_section(p, "开关")
	var toggles := HBoxContainer.new()
	toggles.add_theme_constant_override("separation", 10)
	p.add_child(toggles)
	_check_row(toggles, "invincible", "无敌", func(v: bool) -> void: core.set_invincible(v))
	_check_row(toggles, "one_hit_kill", "秒杀（一击致命）", func(v: bool) -> void: core.set_one_hit_kill(v))

	_section(p, "本局实际数值")
	var card := _card(p, 34)
	var live_row := HBoxContainer.new()
	live_row.add_theme_constant_override("separation", 6)
	card.add_child(live_row)
	for item in [["speed", "移速"], ["rpm", "射速"], ["damage", "伤害"], ["pickup", "拾取"]]:
		var cell := VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_constant_override("separation", 0)
		live_row.add_child(cell)

		var l := Label.new()
		l.text = str(item[1])
		l.add_theme_font_size_override("font_size", F_MICRO)
		l.add_theme_color_override("font_color", C_MUTED)
		cell.add_child(l)

		var val := Label.new()
		val.text = "—"
		val.add_theme_font_size_override("font_size", F_BODY)
		val.add_theme_color_override("font_color", C_TEXT)
		cell.add_child(val)
		_live[str(item[0])] = val

	_section(p, "预设说明")
	var tips := _card(p, 0)
	tips.add_theme_constant_override("separation", 1)
	_tip_line(tips, "轻度：移 1.2 · 射 1.2 · 伤 1.5 · 拾 2.0")
	_tip_line(tips, "爽玩：移 1.5 · 射 2.0 · 伤 5.0 · 拾 3.0 · 无敌")
	_tip_line(tips, "全开：移 2.0 · 射 5.0 · 伤 10 · 拾 5.0 · 减伤 + 护甲 · 无敌 + 秒杀")


func _build_resource_page() -> void:
	var p := _new_page("res")
	_page_header(p, "资源", "金币局内生效 · 青辉石写入存档")

	var cards := HBoxContainer.new()
	cards.custom_minimum_size = Vector2(0, 136)
	cards.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	cards.add_theme_constant_override("separation", 8)
	p.add_child(cards)

	_build_currency_card(cards, true)
	_build_currency_card(cards, false)

	var tips := _card(p, 0)
	tips.add_theme_constant_override("separation", 2)

	var tip_title := Label.new()
	tip_title.text = "提示"
	tip_title.add_theme_font_size_override("font_size", F_MICRO)
	tip_title.add_theme_color_override("font_color", C_GOLD_DIM)
	tips.add_child(tip_title)

	_tip_line(tips, "金币只在当前对局有效，离开对局或重开即清空。")
	_tip_line(tips, "青辉石是账号货币，每次写入前都会二次确认。")
	_tip_line(tips, "联机会话下整个面板只读，避免影响他人房间。")
	_tip_line(tips, "自定义数量支持正负；青辉石只接受正整数。")
	_tip_line(tips, "青辉石改动会立即写入存档，且无法撤销。", C_RED)


func _build_currency_card(parent: Node, is_coin: bool) -> void:
	var card := _card(parent, 0)
	var panel := card.get_parent()
	panel.custom_minimum_size = Vector2(0, 136)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	card.add_theme_constant_override("separation", 4)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	card.add_child(head)

	var title := Label.new()
	title.text = "金币" if is_coin else "青辉石"
	title.add_theme_font_size_override("font_size", F_BODY)
	title.add_theme_color_override("font_color", C_TEXT)
	head.add_child(title)

	var tag := Label.new()
	tag.text = "局内" if is_coin else "存档"
	tag.add_theme_font_size_override("font_size", F_MICRO)
	tag.add_theme_color_override("font_color", C_GOLD if is_coin else C_RED)
	head.add_child(tag)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(spacer)

	var value := Label.new()
	value.text = "—"
	value.add_theme_font_size_override("font_size", 15)
	value.add_theme_color_override("font_color", C_GOLD)
	value.clip_text = true
	value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	card.add_child(value)

	var note := Label.new()
	note.text = "不写存档 · 离开对局即失效" if is_coin else "写入存档 · 立即生效"
	note.add_theme_font_size_override("font_size", F_MICRO)
	note.add_theme_color_override("font_color", C_MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(note)

	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 3)
	card.add_child(actions)

	var quick := HBoxContainer.new()
	quick.add_theme_constant_override("separation", 3)
	actions.add_child(quick)
	var amounts: Array = [1000, 10000, -1000] if is_coin else [100, 1000, 9999]
	for amount in amounts:
		var label := ("+%d" % int(amount)) if int(amount) > 0 else str(int(amount))
		if absi(int(amount)) >= 10000:
			label = ("+%dk" % (int(amount) / 1000)) if int(amount) > 0 else ("-%dk" % (absi(int(amount)) / 1000))
		var b := _button(label, "chip", F_MICRO, 0, 17)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if is_coin:
			b.pressed.connect(_on_coin_quick.bind(int(amount)))
		else:
			b.pressed.connect(_ask_pyro.bind(int(amount)))
		quick.add_child(b)

	var custom := HBoxContainer.new()
	custom.add_theme_constant_override("separation", 3)
	actions.add_child(custom)

	var edit := LineEdit.new()
	edit.placeholder_text = "自定义数量"
	edit.add_theme_font_size_override("font_size", F_SMALL)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.custom_minimum_size = Vector2(0, 17)
	_style_line_edit(edit)
	custom.add_child(edit)

	var add := _button("加", "chip", F_MICRO, 26, 17)
	if is_coin:
		add.pressed.connect(func() -> void:
			var n := int(edit.text)
			if n != 0:
				core.add_coin(n)
		)
	else:
		add.pressed.connect(func() -> void:
			var n := int(edit.text)
			if n <= 0:
				show_notice("请输入正整数")
				return
			_ask_pyro(n)
		)
	custom.add_child(add)

	if is_coin:
		_coin_value = value
		_coin_note = note
		_coin_actions = actions
	else:
		_pyro_value = value


func _build_unlock_page() -> void:
	var p := _new_page("unlock")
	_page_header(p, "解锁", "写入存档 · 不可撤销")

	var warn := _card(p, 0)
	warn.add_theme_constant_override("separation", 2)
	var wh := HBoxContainer.new()
	wh.add_theme_constant_override("separation", 7)
	warn.add_child(wh)

	var bar := ColorRect.new()
	bar.color = C_RED
	bar.custom_minimum_size = Vector2(2, 0)
	bar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wh.add_child(bar)

	var wv := VBoxContainer.new()
	wv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wv.add_theme_constant_override("separation", 1)
	wh.add_child(wv)

	var wt := Label.new()
	wt.text = "会立即写入存档"
	wt.add_theme_font_size_override("font_size", F_SMALL)
	wt.add_theme_color_override("font_color", C_RED)
	wv.add_child(wt)

	var wd := Label.new()
	wd.text = "角色、服装、支援与社团全部解锁；没有撤销入口。"
	wd.add_theme_font_size_override("font_size", F_MICRO)
	wd.add_theme_color_override("font_color", C_MUTED)
	wd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wv.add_child(wd)

	var card := _card(p, 0)
	card.add_theme_constant_override("separation", 4)
	for item in [["characters", "角色"], ["clothes", "服装"], ["supports", "支援"], ["groups", "社团"]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		card.add_child(row)

		var l := Label.new()
		l.text = str(item[1])
		l.custom_minimum_size = Vector2(28, 0)
		l.add_theme_font_size_override("font_size", F_SMALL)
		l.add_theme_color_override("font_color", C_TEXT)
		row.add_child(l)

		var pb := ProgressBar.new()
		pb.show_percentage = false
		pb.custom_minimum_size = Vector2(0, 6)
		pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pb.add_theme_stylebox_override("background", _sb(Color(1, 1, 1, 0.08), C_LINE, 1, 0, 0, 0, 0))
		pb.add_theme_stylebox_override("fill", _sb(C_GREEN, C_BLACK, 0, 0, 0, 0, 0))
		row.add_child(pb)

		var count := Label.new()
		count.text = "—"
		count.custom_minimum_size = Vector2(52, 0)
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count.add_theme_font_size_override("font_size", F_MICRO)
		count.add_theme_color_override("font_color", C_MUTED)
		row.add_child(count)

		_unlock_rows[str(item[0])] = {"bar": pb, "label": count}

	var unlock := _button("一键全部解锁", "primary", F_BODY, 150, 25)
	unlock.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	unlock.pressed.connect(_confirm_unlock)
	p.add_child(unlock)

	var tips := _card(p, 0)
	tips.add_theme_constant_override("separation", 2)

	var tip_title := Label.new()
	tip_title.text = "说明"
	tip_title.add_theme_font_size_override("font_size", F_MICRO)
	tip_title.add_theme_color_override("font_color", C_GOLD_DIM)
	tips.add_child(tip_title)

	_tip_line(tips, "解锁范围是角色、服装、支援与社团；游戏模式是玩法开关，不在其中。")
	_tip_line(tips, "角色与社团会同时覆盖本体内容和 Mod 内容。")
	_tip_line(tips, "建议先备份存档（主菜单底部「存档文件夹」）。")
	_tip_line(tips, "解锁后若界面没刷新，回主菜单再进一次即可。")

	var save_row := HBoxContainer.new()
	save_row.alignment = BoxContainer.ALIGNMENT_END
	tips.add_child(save_row)
	var open_save := _button("打开存档文件夹", "chip", F_MICRO, 0, 17)
	open_save.pressed.connect(func() -> void:
		OS.shell_open(ProjectSettings.globalize_path("user://"))
	)
	save_row.add_child(open_save)


func _build_support_page() -> void:
	var p := _new_page("support")
	_page_header(p, "辅助", "叠加在角色自然成长之上")

	var hp_card := _card(p, 0)
	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 8)
	hp_card.add_child(hp_row)

	var hp_v := VBoxContainer.new()
	hp_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_v.add_theme_constant_override("separation", 2)
	hp_row.add_child(hp_v)

	var hp_head := HBoxContainer.new()
	hp_v.add_child(hp_head)

	var hp_name := Label.new()
	hp_name.text = "生命"
	hp_name.add_theme_font_size_override("font_size", F_MICRO)
	hp_name.add_theme_color_override("font_color", C_MUTED)
	hp_head.add_child(hp_name)

	var hp_sp := Control.new()
	hp_sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_head.add_child(hp_sp)

	_hp_text = Label.new()
	_hp_text.text = "—"
	_hp_text.add_theme_font_size_override("font_size", F_SMALL)
	_hp_text.add_theme_color_override("font_color", C_TEXT)
	hp_head.add_child(_hp_text)

	_hp_bar = ProgressBar.new()
	_hp_bar.show_percentage = false
	_hp_bar.custom_minimum_size = Vector2(0, 8)
	_hp_bar.add_theme_stylebox_override("background", _sb(Color(1, 1, 1, 0.08), C_LINE, 1, 0, 0, 0, 0))
	_hp_bar.add_theme_stylebox_override("fill", _sb(C_GREEN, C_BLACK, 0, 0, 0, 0, 0))
	hp_v.add_child(_hp_bar)

	var heal := _button("回满血", "primary", F_SMALL, 68, 22)
	heal.pressed.connect(func() -> void:
		core.heal_full()
		_refresh_hp()
	)
	hp_row.add_child(heal)

	_section(p, "额外减伤上限")
	_slider_row(p, "reduce", "减伤", 0.0, 0.75, 0.05, [])
	_armor_cap_text = _hint_line(p, "叠加在角色原护甲上限上，最高 98%")
	_slider_row(p, "armor", "护甲", 0.0, 100.0, 5.0, [0, 20, 50, 100])
	_hint_line(p, "在自然护甲之上加算（hurt_resis）")

	_section(p, "当前状态")
	var tiles := HBoxContainer.new()
	tiles.add_theme_constant_override("separation", 5)
	p.add_child(tiles)
	_support_tiles["max_hp"] = _stat_tile(tiles, "生命上限")
	_support_tiles["armor"] = _stat_tile(tiles, "护甲值")
	_support_tiles["cap"] = _stat_tile(tiles, "减伤上限")
	_support_tiles["invincible"] = _stat_tile(tiles, "无敌")

	var tips := _card(p, 0)
	tips.add_theme_constant_override("separation", 2)

	var tip_title := Label.new()
	tip_title.text = "说明"
	tip_title.add_theme_font_size_override("font_size", F_MICRO)
	tip_title.add_theme_color_override("font_color", C_GOLD_DIM)
	tips.add_child(tip_title)

	_tip_line(tips, "减伤上限 = 角色原上限 + 额外值，超过 98% 的部分无效。")
	_tip_line(tips, "护甲值直接加算到 hurt_resis，与减伤上限共同生效。")
	_tip_line(tips, "无敌会挡住治疗；「回满血」会临时关闭无敌再治疗。")
	_tip_line(tips, "关闭倍率或复位后，减伤与护甲会自动还原。")


func _build_debug_page() -> void:
	var p := _new_page("debug")
	_page_header(p, "调试", "清屏 / 刷怪 / 回合控制")

	var tiles := HBoxContainer.new()
	tiles.add_theme_constant_override("separation", 5)
	p.add_child(tiles)

	_tile_enemies = _stat_tile(tiles, "在场敌人")
	_tile_round = _stat_tile(tiles, "回合")
	_tile_left = _stat_tile(tiles, "倒计时")

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 5)
	p.add_child(actions)

	var clear := _button("清屏", "danger", F_SMALL, 54, 18)
	clear.pressed.connect(func() -> void: core.clear_enemies())
	actions.add_child(clear)

	var endr := _button("结束本回合", "normal", F_SMALL, 88, 18)
	endr.pressed.connect(func() -> void: core.end_round())
	actions.add_child(endr)

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	actions.add_child(sp)

	var refresh := _button("刷新列表", "ghost", F_MICRO, 60, 18)
	refresh.pressed.connect(_refresh_enemy_list)
	actions.add_child(refresh)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	p.add_child(head)

	var sec := Label.new()
	sec.text = "生成敌人"
	sec.add_theme_font_size_override("font_size", F_MICRO)
	sec.add_theme_color_override("font_color", C_GOLD_DIM)
	head.add_child(sec)

	var hs := Control.new()
	hs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(hs)

	_enemy_count = Label.new()
	_enemy_count.text = ""
	_enemy_count.add_theme_font_size_override("font_size", F_MICRO)
	_enemy_count.add_theme_color_override("font_color", C_MUTED)
	head.add_child(_enemy_count)

	_enemy_search = LineEdit.new()
	_enemy_search.placeholder_text = "搜索敌人 id…"
	_enemy_search.add_theme_font_size_override("font_size", F_SMALL)
	_enemy_search.custom_minimum_size = Vector2(0, 18)
	_style_line_edit(_enemy_search)
	_enemy_search.text_changed.connect(_on_enemy_filter_changed)
	p.add_child(_enemy_search)

	var list_card := _card(p, 0)
	list_card.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_card.add_theme_constant_override("separation", 2)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_style_scroll(scroll)
	list_card.add_child(scroll)

	_enemy_grid = GridContainer.new()
	_enemy_grid.columns = 2
	_enemy_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_enemy_grid.add_theme_constant_override("h_separation", 3)
	_enemy_grid.add_theme_constant_override("v_separation", 2)
	scroll.add_child(_enemy_grid)

	_enemy_empty = Label.new()
	_enemy_empty.text = "没有匹配的敌人"
	_enemy_empty.add_theme_font_size_override("font_size", F_MICRO)
	_enemy_empty.add_theme_color_override("font_color", C_MUTED)
	_enemy_empty.visible = false
	list_card.add_child(_enemy_empty)


func _build_about_page() -> void:
	var p := _new_page("about")
	_page_header(p, "关于", "版本、快捷键与设置")

	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 8)
	p.add_child(cols)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 3)
	cols.add_child(left)

	var brand := Label.new()
	brand.text = "TRAINER"
	brand.add_theme_font_size_override("font_size", 15)
	brand.add_theme_color_override("font_color", C_GOLD)
	left.add_child(brand)

	var desc := Label.new()
	desc.text = "etn_trainer " + MOD_VERSION + " · F1 开关 · 联机会话只读"
	desc.add_theme_font_size_override("font_size", F_MICRO)
	desc.add_theme_color_override("font_color", C_MUTED)
	left.add_child(desc)

	var build_line := Label.new()
	build_line.text = "构建 " + _read_build_id() + " · ModAPI v" + str(ModAPI.VERSION)
	build_line.add_theme_font_size_override("font_size", F_MICRO)
	build_line.add_theme_color_override("font_color", C_MUTED)
	build_line.modulate.a = 0.8
	left.add_child(build_line)

	_section(left, "快捷键")
	_key_hint(left, "F1", "打开 / 关闭面板")
	_key_hint(left, "Esc", "关闭面板或取消确认")
	_key_hint(left, "1 – 6", "切换页签")
	_key_hint(left, "拖拽", "移动面板位置")

	var f2 := Label.new()
	f2.text = "F2 是本体内置作弊菜单（需 config.ini 开启 developer_mode），两者互不影响。"
	f2.add_theme_font_size_override("font_size", F_MICRO)
	f2.add_theme_color_override("font_color", C_MUTED)
	f2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(f2)

	_section(left, "说明")
	var info := _card(left, 0)
	info.add_theme_constant_override("separation", 2)
	_tip_line(info, "倍率每局归零、不写存档；关闭或复位即还原。")
	_tip_line(info, "数值注入在每次属性重算后重新施加，不会吞掉自然成长。")
	_tip_line(info, "HUD 显示 FPS、敌人数、回合、倒计时与当前加成。")
	_tip_line(info, "面板位置与 HUD 开关记在 user://etn_trainer.cfg。")
	_tip_line(info, "联机会话下整体只读，防止污染他人房间。")

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(196, 0)
	right.add_theme_constant_override("separation", 3)
	cols.add_child(right)

	_section(right, "设置")
	var settings := _card(right, 0)
	settings.add_theme_constant_override("separation", 2)
	_check_row(settings, "dev_mode", "启用本体开发者模式", func(v: bool) -> void: core.set_dev_mode(v), F_SMALL)
	_check_row(settings, "hud", "局内显示常驻 HUD", func(v: bool) -> void:
		core.hud_on = v
		core.save_prefs()
		if hud != null:
			hud.set_shown(v)
	, F_SMALL)

	_section(right, "重置")
	var danger := _card(right, 0)
	danger.add_theme_constant_override("separation", 3)
	var reset_all := _button("关闭全部作弊", "danger", F_MICRO, 0, 18)
	reset_all.pressed.connect(_reset_all)
	danger.add_child(reset_all)
	var recenter := _button("面板回到中央", "ghost", F_MICRO, 0, 17)
	recenter.pressed.connect(_recenter)
	danger.add_child(recenter)


func _tip_line(parent: Node, text: String, color: Color = C_MUTED) -> Label:
	var l := Label.new()
	l.text = "· " + text
	l.add_theme_font_size_override("font_size", F_MICRO)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


func _read_build_id() -> String:
	var f := FileAccess.open("res://mods/etn_trainer/mod_build.json", FileAccess.READ)
	if f == null:
		return "local"
	var data = JSON.parse_string(f.get_as_text())
	if data is Dictionary:
		var id := str(data.get("build_id", ""))
		if id != "":
			return id
	return "local"


func _hint_line(parent: Node, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", F_MICRO)
	l.add_theme_color_override("font_color", C_MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


func _key_hint(parent: Node, key: String, text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)

	var cap := PanelContainer.new()
	cap.custom_minimum_size = Vector2(38, 0)
	cap.add_theme_stylebox_override("panel", _sb(C_BLACK, C_LINE, 1, 4, 1, 4, 1))
	row.add_child(cap)

	var kl := Label.new()
	kl.text = key
	kl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kl.add_theme_font_size_override("font_size", F_MICRO)
	kl.add_theme_color_override("font_color", C_GOLD_DIM)
	cap.add_child(kl)

	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", F_MICRO)
	l.add_theme_color_override("font_color", C_TEXT)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)


func _stat_tile(parent: Node, title: String) -> Label:
	var card := _card(parent, 32)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_constant_override("separation", 0)

	var l := Label.new()
	l.text = title
	l.add_theme_font_size_override("font_size", F_MICRO)
	l.add_theme_color_override("font_color", C_MUTED)
	card.add_child(l)

	var v := Label.new()
	v.text = "—"
	v.add_theme_font_size_override("font_size", 12)
	v.add_theme_color_override("font_color", C_TEXT)
	card.add_child(v)
	return v


# ============================================================ 控件工厂

func _sb(bg: Color, border: Color, width: int, ml: float, mt: float, mr: float, mb: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.content_margin_left = ml
	sb.content_margin_top = mt
	sb.content_margin_right = mr
	sb.content_margin_bottom = mb
	sb.anti_aliasing = false
	sb.corner_radius_top_left = 0
	sb.corner_radius_top_right = 0
	sb.corner_radius_bottom_left = 0
	sb.corner_radius_bottom_right = 0
	return sb


func _hline(h: int, color: Color) -> ColorRect:
	var line := ColorRect.new()
	line.color = color
	line.custom_minimum_size = Vector2(0, h)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


func _card(parent: Node, min_height: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(0, min_height)
	panel.add_theme_stylebox_override("panel", _sb(C_CARD, C_LINE_SOFT, 1, 6, 4, 6, 4))
	parent.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)
	return box


func _button(text: String, kind: String, size: int, min_w: float, min_h: float) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, min_h)
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", size)
	_style_button(b, kind)
	return b


func _style_button(b: Button, kind: String) -> void:
	var normal: StyleBoxFlat
	var hover: StyleBoxFlat
	var pressed: StyleBoxFlat
	var disabled: StyleBoxFlat
	var focus := _sb(C_BLACK, C_GOLD, 1, 0, 0, 0, 0)
	focus.draw_center = false
	var font := C_TEXT
	var font_hover := C_GOLD
	var font_pressed := Color(0, 0, 0, 1)
	var font_disabled := C_MUTED

	match kind:
		"primary":
			normal = _sb(C_GOLD, C_GOLD, 1, 8, 3, 8, 3)
			hover = _sb(Color(1, 1, 1, 1), Color(1, 1, 1, 1), 1, 8, 3, 8, 3)
			pressed = _sb(C_GOLD_DIM, C_GOLD_DIM, 1, 8, 3, 8, 3)
			disabled = _sb(C_CARD, C_LINE, 1, 8, 3, 8, 3)
			font = Color(0.08, 0.07, 0.05, 1)
			font_hover = Color(0.08, 0.07, 0.05, 1)
			font_pressed = Color(0.08, 0.07, 0.05, 1)
			font_disabled = C_MUTED
		"chip":
			normal = _sb(Color(1, 1, 1, 0.05), C_LINE, 1, 5, 2, 5, 2)
			hover = _sb(Color(1, 1, 1, 0.12), C_GOLD_DIM, 1, 5, 2, 5, 2)
			pressed = _sb(C_GOLD_DIM, C_GOLD_DIM, 1, 5, 2, 5, 2)
			disabled = _sb(C_CARD, C_LINE_SOFT, 1, 5, 2, 5, 2)
			font_pressed = Color(0.08, 0.07, 0.05, 1)
		"tab":
			normal = _sb(C_BLACK, C_BLACK, 0, 8, 3, 5, 3)
			hover = _sb(Color(1, 1, 1, 0.06), C_BLACK, 0, 8, 3, 5, 3)
			pressed = _sb(Color(1, 1, 1, 0.10), C_BLACK, 0, 8, 3, 5, 3)
			disabled = _sb(C_BLACK, C_BLACK, 0, 8, 3, 5, 3)
			font = C_MUTED
			font_hover = C_TEXT
			font_pressed = C_GOLD
		"danger":
			normal = _sb(Color(0.18, 0.05, 0.07, 1), C_RED, 1, 8, 3, 8, 3)
			hover = _sb(Color(0.32, 0.07, 0.11, 1), C_RED, 1, 8, 3, 8, 3)
			pressed = _sb(C_RED, C_RED, 1, 8, 3, 8, 3)
			disabled = _sb(C_CARD, C_LINE_SOFT, 1, 8, 3, 8, 3)
			font = Color(1.0, 0.72, 0.76, 1)
			font_hover = Color(1, 1, 1, 1)
			font_pressed = Color(1, 1, 1, 1)
		"ghost":
			normal = _sb(C_BLACK, C_BLACK, 0, 6, 2, 6, 2)
			hover = _sb(Color(1, 1, 1, 0.08), C_LINE, 1, 6, 2, 6, 2)
			pressed = _sb(Color(1, 1, 1, 0.14), C_LINE, 1, 6, 2, 6, 2)
			disabled = _sb(C_BLACK, C_BLACK, 0, 6, 2, 6, 2)
			font = C_MUTED
			font_hover = C_TEXT
			font_pressed = C_TEXT
		"list":
			normal = _sb(Color(1, 1, 1, 0.04), C_LINE_SOFT, 1, 5, 1, 5, 1)
			hover = _sb(Color(1, 1, 1, 0.10), C_GOLD_DIM, 1, 5, 1, 5, 1)
			pressed = _sb(C_GOLD_DIM, C_GOLD_DIM, 1, 5, 1, 5, 1)
			disabled = _sb(C_CARD, C_LINE_SOFT, 1, 5, 1, 5, 1)
			font_pressed = Color(0.08, 0.07, 0.05, 1)
		_:
			normal = _sb(Color(0.075, 0.083, 0.105, 1), C_LINE, 1, 7, 3, 7, 3)
			hover = _sb(C_CARD_HI, C_GOLD_DIM, 1, 7, 3, 7, 3)
			pressed = _sb(C_GOLD_DIM, C_GOLD_DIM, 1, 7, 3, 7, 3)
			disabled = _sb(C_CARD, C_LINE_SOFT, 1, 7, 3, 7, 3)
			font_pressed = Color(0.08, 0.07, 0.05, 1)

	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_color_override("font_color", font)
	b.add_theme_color_override("font_hover_color", font_hover)
	b.add_theme_color_override("font_pressed_color", font_pressed)
	b.add_theme_color_override("font_focus_color", font)
	b.add_theme_color_override("font_disabled_color", font_disabled)
	if kind == "tab":
		var tab_focus := _sb(C_BLACK, Color(1, 1, 1, 0.45), 1, 0, 0, 0, 0)
		tab_focus.draw_center = false
		b.add_theme_stylebox_override("focus", tab_focus)


func _set_tab_active(b: Button, active: bool) -> void:
	var normal: StyleBoxFlat
	if active:
		normal = _sb(Color(1, 1, 1, 0.055), C_GOLD, 0, 9, 3, 5, 3)
		normal.border_width_left = 2
		b.add_theme_color_override("font_color", C_GOLD)
		b.add_theme_color_override("font_hover_color", C_GOLD)
		b.add_theme_color_override("font_focus_color", C_GOLD)
	else:
		normal = _sb(C_BLACK, C_BLACK, 0, 8, 3, 5, 3)
		b.add_theme_color_override("font_color", C_MUTED)
		b.add_theme_color_override("font_hover_color", C_TEXT)
		b.add_theme_color_override("font_focus_color", C_MUTED)
	b.add_theme_stylebox_override("normal", normal)


func _style_line_edit(edit: LineEdit) -> void:
	edit.add_theme_stylebox_override("normal", _sb(Color(0, 0, 0, 0.35), C_LINE, 1, 5, 2, 5, 2))
	edit.add_theme_stylebox_override("focus", _sb(Color(0, 0, 0, 0.35), C_GOLD, 1, 5, 2, 5, 2))
	edit.add_theme_stylebox_override("read_only", _sb(Color(0, 0, 0, 0.2), C_LINE_SOFT, 1, 5, 2, 5, 2))
	edit.add_theme_color_override("font_color", C_TEXT)
	edit.add_theme_color_override("font_placeholder_color", C_MUTED)
	edit.add_theme_color_override("caret_color", C_GOLD)
	edit.add_theme_color_override("selection_color", Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, 0.28))


func _style_scroll(scroll: ScrollContainer) -> void:
	var bar := scroll.get_v_scroll_bar()
	bar.custom_minimum_size = Vector2(6, 0)
	bar.add_theme_stylebox_override("scroll", _sb(Color(1, 1, 1, 0.05), C_BLACK, 0, 0, 0, 0, 0))
	bar.add_theme_stylebox_override("grabber", _sb(Color(1, 1, 1, 0.28), C_BLACK, 0, 0, 0, 0, 0))
	bar.add_theme_stylebox_override("grabber_highlight", _sb(C_GOLD_DIM, C_BLACK, 0, 0, 0, 0, 0))
	bar.add_theme_stylebox_override("grabber_pressed", _sb(C_GOLD, C_BLACK, 0, 0, 0, 0, 0))


func _icon_blank() -> ImageTexture:
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)


func _icon_check(checked: bool) -> ImageTexture:
	var img := Image.create(9, 9, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	if checked:
		for y in 9:
			for x in 9:
				var edge := x == 0 or y == 0 or x == 8 or y == 8
				img.set_pixel(x, y, Color(0, 0, 0, 1) if edge else C_GREEN)
		for p in [[2, 5], [3, 6], [4, 5], [5, 4], [6, 3], [6, 2]]:
			img.set_pixel(int(p[0]), int(p[1]), Color(0.05, 0.09, 0.02, 1))
	else:
		for y in 9:
			for x in 9:
				var edge := x == 0 or y == 0 or x == 8 or y == 8
				img.set_pixel(x, y, Color(1, 1, 1, 0.55) if edge else Color(1, 1, 1, 0.04))
	return ImageTexture.create_from_image(img)


func _icon_grabber() -> ImageTexture:
	var img := Image.create(7, 11, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in 11:
		for x in 7:
			var edge := x == 0 or y == 0 or x == 6 or y == 10
			img.set_pixel(x, y, Color(0, 0, 0, 1) if edge else Color(1.0, 0.976, 0.910, 1.0))
	for y in range(2, 9):
		img.set_pixel(3, y, C_GOLD_DIM)
	return ImageTexture.create_from_image(img)


func _slider_row(parent: Node, key: String, title: String, minv: float, maxv: float, step: float, presets: Array) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)

	var name_label := Label.new()
	name_label.text = title
	name_label.custom_minimum_size = Vector2(28, 0)
	name_label.add_theme_font_size_override("font_size", F_BODY)
	name_label.add_theme_color_override("font_color", C_TEXT)
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(name_label)

	var slider := HSlider.new()
	slider.min_value = minv
	slider.max_value = maxv
	slider.step = step
	slider.value = 1.0 if key in ["speed", "fire", "damage", "pickup"] else 0.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size = Vector2(80, 13)
	_style_slider(slider)
	row.add_child(slider)

	var value_label := Label.new()
	value_label.text = "1.0x"
	value_label.custom_minimum_size = Vector2(38, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_font_size_override("font_size", F_SMALL)
	value_label.add_theme_color_override("font_color", C_GOLD)
	value_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(value_label)

	if not presets.is_empty():
		var pr := HBoxContainer.new()
		pr.add_theme_constant_override("separation", 1)
		row.add_child(pr)
		for p in presets:
			var b := _button(str(p), "chip", F_MICRO, 18, 15)
			b.pressed.connect(_set_slider_value.bind(slider, float(p)))
			pr.add_child(b)

	slider.value_changed.connect(_on_slider_value.bind(key))
	_sliders[key] = {"slider": slider, "label": value_label}


func _style_slider(slider: HSlider) -> void:
	slider.add_theme_stylebox_override("slider", _sb(Color(1, 1, 1, 0.10), C_LINE, 1, 0, 4, 0, 4))
	slider.add_theme_stylebox_override("grabber_area", _sb(C_GOLD_DIM, C_BLACK, 0, 0, 4, 0, 4))
	slider.add_theme_stylebox_override("grabber_area_highlight", _sb(C_GOLD, C_BLACK, 0, 0, 4, 0, 4))
	var grabber := _icon_grabber()
	slider.add_theme_icon_override("grabber", grabber)
	slider.add_theme_icon_override("grabber_highlight", grabber)
	slider.add_theme_icon_override("grabber_disabled", grabber)


func _check_row(parent: Node, key: String, title: String, on_change: Callable, size: int = F_BODY) -> CheckBox:
	var c := CheckBox.new()
	c.text = title
	c.focus_mode = Control.FOCUS_ALL
	c.custom_minimum_size = Vector2(0, 20)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.add_theme_font_size_override("font_size", size)
	# 原生图标置空，改由子节点 TextureRect 画，才能单独微调垂直位置（对齐中文字形）。
	c.add_theme_constant_override("h_separation", 0)
	var blank := _icon_blank()
	c.add_theme_icon_override("checked", blank)
	c.add_theme_icon_override("unchecked", blank)
	c.add_theme_icon_override("checked_disabled", blank)
	c.add_theme_icon_override("unchecked_disabled", blank)
	# 左侧留出 17px 给图标；不再画左侧竖线。
	c.add_theme_stylebox_override("normal", _check_style(false, false))
	c.add_theme_stylebox_override("hover", _check_style(false, true))
	c.add_theme_stylebox_override("pressed", _check_style(true, false))
	c.add_theme_stylebox_override("hover_pressed", _check_style(true, true))
	c.add_theme_stylebox_override("disabled", _check_style(false, false))
	var focus_style := _sb(C_BLACK, C_GOLD, 1, 0, 0, 0, 0)
	focus_style.draw_center = false
	c.add_theme_stylebox_override("focus", focus_style)
	c.add_theme_color_override("font_color", C_TEXT)
	c.add_theme_color_override("font_hover_color", C_TEXT)
	c.add_theme_color_override("font_pressed_color", C_TEXT)
	c.add_theme_color_override("font_hover_pressed_color", C_TEXT)
	c.add_theme_color_override("font_focus_color", C_TEXT)
	c.add_theme_color_override("font_disabled_color", C_MUTED)

	var icon := TextureRect.new()
	icon.texture = _icon_check(false)
	icon.custom_minimum_size = Vector2(9, 9)
	icon.size = Vector2(9, 9)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.anchor_left = 0.0
	icon.anchor_right = 0.0
	icon.anchor_top = 0.5
	icon.anchor_bottom = 0.5
	icon.offset_left = 4.0
	icon.offset_right = 13.0
	# 子节点按行中心对齐（原生 CheckBox 图标会被行框顶到偏上）。
	icon.offset_top = -4.5
	icon.offset_bottom = 4.5
	c.add_child(icon)
	c.toggled.connect(func(v: bool) -> void:
		icon.texture = _icon_check(v)
	)
	c.toggled.connect(_on_check_toggled.bind(key, on_change))
	parent.add_child(c)
	_checks[key] = c
	return c


func _check_style(on: bool, hover: bool) -> StyleBoxFlat:
	var bg := C_BLACK
	if on:
		bg = Color(0.16, 0.23, 0.11, 1.0) if hover else Color(0.13, 0.19, 0.09, 1.0)
	elif hover:
		bg = Color(1, 1, 1, 0.06)
	return _sb(bg, C_BLACK, 0, 17, 2, 4, 2)


func _on_check_toggled(v: bool, key: String, on_change: Callable) -> void:
	if _checks.has(key):
		var c: BaseButton = _checks[key]
		c.add_theme_stylebox_override("normal", _check_style(v, false))
		c.add_theme_stylebox_override("hover", _check_style(v, true))
		c.add_theme_stylebox_override("disabled", _check_style(v, false))
	if _syncing:
		return
	on_change.call(v)


func _set_slider_value(slider: HSlider, v: float) -> void:
	slider.value = v


func _on_slider_value(v: float, key: String) -> void:
	_update_slider_label(key, v)
	if _syncing:
		return
	match key:
		"speed":
			core.speed_mult = v
		"fire":
			core.fire_rate_mult = v
		"damage":
			core.damage_mult = v
		"pickup":
			core.pickup_mult = v
		"reduce":
			core.armor_cap = v
		"armor":
			core.armor_add = v
	core.push_values()


func _update_slider_label(key: String, v: float) -> void:
	if not _sliders.has(key):
		return
	var label: Label = _sliders[key]["label"]
	match key:
		"reduce":
			label.text = "+%d%%" % int(round(v * 100.0))
		"armor":
			label.text = "+%d" % int(round(v))
		_:
			label.text = "%.1fx" % v


# ============================================================ 交互

func _apply_preset(kind: String) -> void:
	match kind:
		"light":
			core.speed_mult = 1.2
			core.fire_rate_mult = 1.2
			core.damage_mult = 1.5
			core.pickup_mult = 2.0
			core.set_invincible(false)
			core.set_one_hit_kill(false)
		"fun":
			core.speed_mult = 1.5
			core.fire_rate_mult = 2.0
			core.damage_mult = 5.0
			core.pickup_mult = 3.0
			core.set_invincible(true)
			core.set_one_hit_kill(false)
		"all":
			core.speed_mult = 2.0
			core.fire_rate_mult = 5.0
			core.damage_mult = 10.0
			core.pickup_mult = 5.0
			core.armor_cap = 0.65
			core.armor_add = 60.0
			core.set_invincible(true)
			core.set_one_hit_kill(true)
	core.push_values()
	_sync_from_core()
	_refresh_actual_stats()
	var names := {"light": "轻度", "fun": "爽玩", "all": "全开"}
	show_notice("已应用预设：" + str(names.get(kind, kind)))


func _reset_stats() -> void:
	core.speed_mult = 1.0
	core.fire_rate_mult = 1.0
	core.damage_mult = 1.0
	core.pickup_mult = 1.0
	core.set_invincible(false)
	core.set_one_hit_kill(false)
	core.push_values()
	_sync_from_core()
	_refresh_actual_stats()
	show_notice("已复位四项倍率与开关")


func _reset_all() -> void:
	if core == null:
		return
	core.reset_cheats(true)
	_sync_from_core()
	_refresh_actual_stats()
	_refresh_hp()
	_refresh_availability()


func _recenter() -> void:
	core.panel_pos = Vector2(-99999.0, -99999.0)
	core.save_prefs()
	_layout()


func _on_coin_quick(amount: int) -> void:
	core.add_coin(amount)
	_refresh_currency()


func _ask_pyro(amount: int) -> void:
	_ask_confirm("写入存档", "青辉石 +%d 会立即写入存档，且无法撤销。" % amount,
		func() -> void:
			core.add_pyroxenes(amount)
			_refresh_currency()
	)


func _confirm_unlock() -> void:
	_ask_confirm("写入存档", "将把角色、服装、支援与社团全部写入存档，且无法撤销。",
		func() -> void:
			core.unlock_all()
			_refresh_unlock_progress(true)
	)


func _ask_confirm(title: String, body: String, cb: Callable) -> void:
	if core != null and core.is_locked():
		show_notice("联机会话中，修改器已禁用")
		return
	_confirm_cb = cb
	_confirm_title.text = title
	_confirm_body.text = body
	_confirm_layer.visible = true
	_focus_before_confirm = get_viewport().gui_get_focus_owner()
	_confirm_cancel.grab_focus()


func _hide_confirm() -> void:
	_confirm_layer.visible = false
	_confirm_cb = Callable()
	if _focus_before_confirm != null and is_instance_valid(_focus_before_confirm):
		_focus_before_confirm.grab_focus()
	_focus_before_confirm = null


func _on_confirm() -> void:
	var cb := _confirm_cb
	_hide_confirm()
	if cb.is_valid():
		cb.call()


func show_notice(text: String) -> void:
	if _footer_label == null:
		return
	_footer_label.text = text
	var bad := text.contains("无法") or text.contains("没有") or text.contains("失败") or text.contains("禁用")
	_footer_label.add_theme_color_override("font_color", C_RED if bad else C_GREEN)
	_toast_left = 3.5


# ============================================================ 状态同步

func _refresh_fps() -> void:
	if _fps_label == null:
		return
	var fps := Engine.get_frames_per_second()
	_fps_label.text = "FPS %d" % fps
	var c := C_GREEN
	if fps < 30:
		c = C_RED
	elif fps < 55:
		c = C_GOLD_DIM
	if c != _fps_color:
		_fps_color = c
		_fps_label.add_theme_color_override("font_color", c)


## core 整体重置后同步面板（联机进入 / 关于页「关闭全部作弊」）。
func _on_cheats_reset() -> void:
	if core == null:
		return
	_sync_from_core()
	_refresh_actual_stats()
	_refresh_hp()
	_refresh_currency()
	_refresh_availability()


func _show_tab(key: String) -> void:
	_current_tab = key
	for k in _tab_buttons.keys():
		_set_tab_active(_tab_buttons[k], str(k) == key)
	match key:
		"stats":
			_refresh_actual_stats()
		"res":
			_refresh_currency()
		"support":
			_refresh_hp()
		"unlock":
			_refresh_unlock_progress(false)
		"debug":
			if not _enemy_built:
				_refresh_enemy_list()
			_refresh_debug_status()
	_refresh_availability()


func _refresh_availability() -> void:
	if core == null:
		return
	var locked: bool = core.is_locked()
	var in_game: bool = core.in_game()
	_last_locked = locked
	_last_ingame = in_game
	if locked and _confirm_layer.visible:
		_hide_confirm()

	if locked:
		_update_status_chip("locked")
	elif in_game:
		_update_status_chip("game")
	else:
		_update_status_chip("menu")

	for k in _tab_buttons.keys():
		var b: Button = _tab_buttons[k]
		var ok := _page_available(str(k))
		b.modulate = Color(1, 1, 1, 1) if ok or str(k) == _current_tab else Color(1, 1, 1, 0.55)

	var available := _page_available(_current_tab)
	for k in _pages.keys():
		_pages[k].visible = str(k) == _current_tab and available
	_overlay.visible = not available
	if not available:
		if locked:
			_overlay_title.text = "联机会话中"
			_overlay_title.add_theme_color_override("font_color", C_RED)
			_overlay_desc.text = "修改器已整体禁用；进入房间时已自动重置全部作弊。"
			_overlay_hint.text = "退出联机后自动恢复。"
		else:
			_overlay_title.text = "需要在对局中"
			_overlay_title.add_theme_color_override("font_color", C_GOLD)
			_overlay_desc.text = "数值、辅助与调试会直接作用于当前玩家和场景。"
			_overlay_hint.text = "进入对局后自动解除；「资源」「解锁」「关于」页现在可用。"

	var coin_ok := in_game and not locked
	if _coin_actions != null:
		_coin_actions.modulate.a = 1.0 if coin_ok else 0.45
		_set_controls_enabled(_coin_actions, coin_ok)
	if _coin_note != null:
		_coin_note.text = "不写存档 · 离开对局即失效" if coin_ok else "进入对局后可用"
		_coin_note.add_theme_color_override("font_color", C_MUTED if coin_ok else C_GOLD_DIM)

	if not available:
		_focus_out_of_pages()


## 页面被隐藏/锁定时，把焦点从页内控件移回页签，避免键盘继续改隐藏的滑条。
func _focus_out_of_pages() -> void:
	if not visible:
		return
	var f := get_viewport().gui_get_focus_owner()
	if f == null:
		return
	if _pages_holder.is_ancestor_of(f) and _tab_buttons.has(_current_tab):
		_tab_buttons[_current_tab].grab_focus()


## 整组禁用/恢复（用于「金币」卡在没有玩家时不可操作）。
func _set_controls_enabled(node: Node, on: bool) -> void:
	for child in node.get_children():
		if child is BaseButton:
			child.disabled = not on
		elif child is LineEdit:
			child.editable = on
		_set_controls_enabled(child, on)


func _page_available(key: String) -> bool:
	if core == null:
		return false
	if core.is_locked():
		return false
	if key in IN_GAME_TABS:
		return core.in_game()
	return true


func _update_status_chip(kind: String) -> void:
	if _status_key == kind:
		return
	_status_key = kind
	var color := C_MUTED
	var text := "主菜单"
	if kind == "game":
		color = C_GREEN
		text = "对局中"
	elif kind == "locked":
		color = C_RED
		text = "联机 · 只读"
	_status_text.text = text
	_status_text.add_theme_color_override("font_color", color)
	_status_dot.color = color
	_status_chip.add_theme_stylebox_override("panel", _sb(Color(0, 0, 0, 0.25), color, 1, 6, 1, 6, 1))


func _sync_from_core() -> void:
	_syncing = true
	var vals := {
		"speed": core.speed_mult,
		"fire": core.fire_rate_mult,
		"damage": core.damage_mult,
		"pickup": core.pickup_mult,
		"reduce": maxf(0.0, core.armor_cap),
		"armor": core.armor_add,
	}
	for k in vals.keys():
		if not _sliders.has(k):
			continue
		var s: HSlider = _sliders[k]["slider"]
		s.value = float(vals[k])
		_update_slider_label(str(k), float(vals[k]))
	if _checks.has("invincible"):
		_checks["invincible"].button_pressed = core.invincible
	if _checks.has("one_hit_kill"):
		_checks["one_hit_kill"].button_pressed = core.one_hit_kill
	if _checks.has("hud"):
		_checks["hud"].button_pressed = core.hud_on
	if _checks.has("dev_mode"):
		_checks["dev_mode"].button_pressed = core.dev_mode_on
		_checks["dev_mode"].disabled = core.dev_mode_locked
		_checks["dev_mode"].text = "开发者模式（config.ini 已锁定）" if core.dev_mode_locked else "启用本体开发者模式"
	_syncing = false


func _refresh_currency() -> void:
	if _coin_value == null:
		return
	var coin: int = core.get_coin()
	_coin_value.text = "—" if coin < 0 else _fmt_int(coin)
	_pyro_value.text = _fmt_int(core.get_pyroxenes())


func _refresh_unlock_progress(force: bool) -> void:
	if _unlock_rows.is_empty():
		return
	if force or _unlock_cache.is_empty():
		_unlock_cache = core.unlock_progress()
	for k in _unlock_rows.keys():
		var data: Dictionary = _unlock_cache.get(k, {})
		var owned := int(data.get("owned", 0))
		var total := int(data.get("total", 0))
		var bar: ProgressBar = _unlock_rows[k]["bar"]
		var label: Label = _unlock_rows[k]["label"]
		bar.max_value = maxi(1, total)
		bar.value = owned
		label.text = "—" if total <= 0 else "%d / %d" % [owned, total]


func _refresh_hp() -> void:
	if _hp_bar == null:
		return
	var snap: Dictionary = core.snapshot()
	if snap.is_empty():
		_hp_text.text = "—"
		_hp_bar.max_value = 1
		_hp_bar.value = 0
		if _support_tiles.has("armor"):
			_support_tiles["max_hp"].text = "—"
			_support_tiles["armor"].text = "—"
			_support_tiles["cap"].text = "—"
			_support_tiles["invincible"].text = "—"
			_support_tiles["invincible"].add_theme_color_override("font_color", C_MUTED)
		return
	var hp := int(snap.get("hp", 0))
	var max_hp := maxi(1, int(snap.get("max_hp", 1)))
	_hp_text.text = "%d / %d" % [hp, max_hp]
	_hp_bar.max_value = max_hp
	_hp_bar.value = hp
	var ratio := float(hp) / float(max_hp)
	var state := "low" if ratio <= 0.25 else ("mid" if ratio <= 0.5 else "ok")
	if state != _hp_color:
		_hp_color = state
		var c := C_GREEN
		if state == "mid":
			c = C_GOLD_DIM
		elif state == "low":
			c = C_RED
		_hp_bar.add_theme_stylebox_override("fill", _sb(c, C_BLACK, 0, 0, 0, 0, 0))
	if _armor_cap_text != null:
		_armor_cap_text.text = "叠加在角色原护甲上限上，最高 98%"
	if _support_tiles.has("armor"):
		var armor := int(snap.get("armor", 0))
		var cap := float(snap.get("armor_cap", 0.0))
		_support_tiles["max_hp"].text = str(int(snap.get("max_hp", 0)))
		_support_tiles["armor"].text = str(armor)
		_support_tiles["cap"].text = "%.0f%%" % (cap * 100.0)
		var on: bool = core.invincible
		_support_tiles["invincible"].text = "开" if on else "关"
		_support_tiles["invincible"].add_theme_color_override("font_color", C_GREEN if on else C_MUTED)


func _refresh_actual_stats() -> void:
	var snap: Dictionary = core.snapshot()
	var empty := snap.is_empty()
	var speed_label: Label = _live.get("speed")
	var rpm_label: Label = _live.get("rpm")
	var damage_label: Label = _live.get("damage")
	var pickup_label: Label = _live.get("pickup")
	if speed_label != null:
		speed_label.text = "—" if empty else str(int(snap.get("speed", 0)))
	if rpm_label != null:
		rpm_label.text = "—" if empty else str(int(snap.get("rpm", 0)))
	if damage_label != null:
		damage_label.text = "—" if empty else "%.1f" % float(snap.get("damage", 0.0))
	if pickup_label != null:
		pickup_label.text = "—" if empty else str(int(snap.get("pickup", 0)))


func _refresh_debug_status() -> void:
	if _tile_enemies == null:
		return
	var count := 0
	if is_instance_valid(PoolManager):
		count = PoolManager.get_active_enemies().size()
	_tile_enemies.text = str(count)
	var rt = core.get_round_timer()
	var rnd := 0
	var left := 0.0
	if rt != null:
		rnd = int(rt.get("now_round_num"))
		if rt.get("timer") != null:
			left = float(rt.timer.time_left)
	_tile_round.text = "第 %d 回合" % rnd
	_tile_left.text = _fmt_time(left)


func _refresh_enemy_list() -> void:
	_enemy_built = true
	_enemy_cards = core.list_enemy_cards()
	var seen := {}
	var unique: Array = []
	for card in _enemy_cards:
		if card == null:
			continue
		var id := str(card.get("id"))
		if id == "" or seen.has(id):
			continue
		seen[id] = true
		unique.append(card)
	unique.sort_custom(func(a, b) -> bool: return str(a.get("id")) < str(b.get("id")))
	_enemy_cards = unique
	_rebuild_enemy_grid()
	_refresh_enemy_count()


func _on_enemy_filter_changed(_text: String) -> void:
	_rebuild_enemy_grid()
	_refresh_enemy_count()


func _rebuild_enemy_grid() -> void:
	if _enemy_grid == null:
		return
	for child in _enemy_grid.get_children():
		_enemy_grid.remove_child(child)
		child.queue_free()
	var filter := _enemy_search.text.strip_edges().to_lower()
	_enemy_filtered.clear()
	for card in _enemy_cards:
		var id := str(card.get("id"))
		if filter != "" and not id.to_lower().contains(filter):
			continue
		_enemy_filtered.append(card)
		var b := _button(id, "list", F_SMALL, 0, 16)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = "生成 " + id
		b.pressed.connect(_on_spawn_enemy.bind(card))
		_enemy_grid.add_child(b)
	_enemy_empty.visible = _enemy_filtered.is_empty()


func _refresh_enemy_count() -> void:
	if _enemy_count == null:
		return
	if _enemy_search != null and _enemy_search.text.strip_edges() != "":
		_enemy_count.text = "%d / %d 种" % [_enemy_filtered.size(), _enemy_cards.size()]
	else:
		_enemy_count.text = "共 %d 种" % _enemy_cards.size()


func _on_spawn_enemy(card) -> void:
	if card == null:
		return
	core.spawn_enemy(card)
	_refresh_debug_status()


func _fmt_int(v: int) -> String:
	var negative := v < 0
	var digits := str(absi(v))
	var out := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			out = "," + out
		out = digits[i] + out
		count += 1
	return ("-" if negative else "") + out


func _fmt_time(seconds: float) -> String:
	var total := maxi(0, int(ceil(seconds)))
	return "%02d:%02d" % [total / 60, total % 60]


# ============================================================ 帧更新

func _process(delta: float) -> void:
	if core == null:
		return
	if _toast_left > 0.0:
		_toast_left -= delta
		if _toast_left <= 0.0 and _footer_label != null:
			_footer_label.text = ""
	if not visible:
		return
	_tick += delta
	if _tick < 0.25:
		return
	_tick = 0.0
	_refresh_fps()

	var locked: bool = core.is_locked()
	var in_game: bool = core.in_game()
	if locked != _last_locked or in_game != _last_ingame:
		_refresh_availability()

	match _current_tab:
		"stats":
			_refresh_actual_stats()
		"res":
			_refresh_currency()
		"support":
			_refresh_hp()
		"debug":
			_refresh_debug_status()


# ============================================================ 开关面板

func toggle() -> void:
	if visible:
		close_panel()
	else:
		open_panel()


func open_panel() -> void:
	if visible:
		return
	# 本体 GUI 命中测试按场景树逆序（不是按 CanvasLayer.layer）走，
	# 切场景后新场景是 root 的最后一个子节点，会把挂在 root 下的本面板挡在下面。
	# 打开时把面板移到 root 末尾，保证它排在当前场景之后、优先收到鼠标事件。
	var root := get_tree().root
	if get_parent() == root:
		root.move_child(self, root.get_child_count() - 1)
	if hud != null and hud.get_parent() == root:
		root.move_child(hud, root.get_child_count() - 1)
	_layout()
	_sync_from_core()
	_refresh_fps()
	_last_locked = core.is_locked()
	_last_ingame = core.in_game()
	_show_tab(_current_tab)
	visible = true
	_prev_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_external_lock = false
	if not GameEvents.pause_lock.is_connected(_on_pause_lock):
		GameEvents.pause_lock.connect(_on_pause_lock)
	if core.in_game():
		var t := get_tree()
		if t != null and not t.paused:
			_paused_by_us = true
			_self_lock = true
			GameEvents.emit_pause_lock(true)
			_self_lock = false
			t.paused = true
	if _tab_buttons.has(_current_tab):
		_tab_buttons[_current_tab].grab_focus()


func close_panel() -> void:
	if not visible:
		return
	visible = false
	_hide_confirm()
	Input.mouse_mode = _prev_mouse
	if GameEvents.pause_lock.is_connected(_on_pause_lock):
		GameEvents.pause_lock.disconnect(_on_pause_lock)
	# 若期间回合结束/升级页等系统也上了暂停锁，就把暂停交还给它们
	if _paused_by_us and not _external_lock:
		_paused_by_us = false
		var t := get_tree()
		if t != null:
			t.paused = false
			_self_lock = true
			GameEvents.emit_pause_lock(false)
			_self_lock = false
	else:
		_paused_by_us = false
	core.panel_pos = _panel.position
	core.save_prefs()


## 按 640x360 基准视口显式计算面板矩形，避免超出视口或依赖容器的隐式撑开。
func _layout() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var pw: float = minf(600.0, maxf(360.0, vp.x - 24.0))
	var ph: float = minf(336.0, maxf(240.0, vp.y - 20.0))
	_panel.size = Vector2(pw, ph)
	_dim.size = vp
	if core.panel_pos.x < -90000.0:
		_panel.position = ((vp - _panel.size) * 0.5).floor()
	else:
		_panel.position = Vector2(
			clampf(core.panel_pos.x, 0.0, maxf(0.0, vp.x - pw)),
			clampf(core.panel_pos.y, 0.0, maxf(0.0, vp.y - ph)))
	_col.queue_sort()


func _on_pause_lock(locked: bool) -> void:
	if _self_lock:
		return
	_external_lock = locked


func _on_header_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = true
				_drag_off = get_viewport().get_mouse_position() - _panel.position
			else:
				_dragging = false
				core.panel_pos = _panel.position
				core.save_prefs()
	elif event is InputEventMouseMotion and _dragging:
		var target: Vector2 = get_viewport().get_mouse_position() - _drag_off
		var vp: Vector2 = get_viewport().get_visible_rect().size
		_panel.position = Vector2(
			clampf(target.x, -_panel.size.x + 40.0, vp.x - 40.0),
			clampf(target.y, 0.0, vp.y - 20.0))


## 面板本体吃掉点击，避免穿透到游戏
func _on_panel_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if _confirm_layer.visible:
		if event.is_action_pressed("ui_cancel"):
			_hide_confirm()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		close_panel()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var idx := int(event.keycode) - int(KEY_1)
		if idx >= 0 and idx < TABS.size():
			var key := str(TABS[idx][0])
			_show_tab(key)
			if _tab_buttons.has(key):
				_tab_buttons[key].grab_focus()
			get_viewport().set_input_as_handled()
