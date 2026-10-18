extends RefCounted

## Mod 自带主题，避免要求旧版本体提供新版 settings_theme.tres。
const ACCENT := Color(0.36, 0.88, 0.57)
const TEXT := Color(0.91, 0.93, 0.90)
const MUTED := Color(0.59, 0.65, 0.61)

static func box(background: Color, border: Color, padding: float = 6.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style

static func get_theme() -> Theme:
	var _theme := Theme.new()
	_theme.default_font = preload("res://fonts/BoutiqueBitmap9x9_Bold_1.9.ttf")
	_theme.default_font_size = 11
	var normal := box(Color(0.12, 0.12, 0.12), Color(0.27, 0.27, 0.27))
	var hover := box(Color(0.19, 0.19, 0.19), ACCENT.darkened(0.3))
	var pressed := box(ACCENT, ACCENT)
	var focus := box(Color.TRANSPARENT, ACCENT)
	focus.draw_center = false
	focus.set_border_width_all(2)
	for type in ["Button", "CheckButton"]:
		_theme.set_stylebox("normal", type, normal)
		_theme.set_stylebox("hover", type, hover)
		_theme.set_stylebox("pressed", type, pressed)
		_theme.set_stylebox("hover_pressed", type, pressed)
		_theme.set_stylebox("disabled", type, normal)
		_theme.set_stylebox("focus", type, focus)
		_theme.set_color("font_color", type, TEXT)
		_theme.set_color("font_hover_color", type, TEXT)
		_theme.set_color("font_pressed_color", type, Color(0.04, 0.13, 0.08))
		_theme.set_color("font_hover_pressed_color", type, Color(0.04, 0.13, 0.08))
		_theme.set_color("font_disabled_color", type, MUTED)
		_theme.set_constant("outline_size", type, 0)
	_theme.set_stylebox("normal", "LineEdit", box(Color(0.065, 0.065, 0.065), Color(0.27, 0.27, 0.27)))
	_theme.set_stylebox("focus", "LineEdit", focus)
	_theme.set_color("font_color", "LineEdit", TEXT)
	_theme.set_color("font_placeholder_color", "LineEdit", MUTED)
	_theme.set_color("caret_color", "LineEdit", ACCENT)
	_theme.set_color("selection_color", "LineEdit", Color(0.16, 0.38, 0.25))
	_theme.set_color("font_color", "Label", TEXT)
	_theme.set_color("font_uneditable_color", "LineEdit", MUTED)
	_theme.set_stylebox("read_only", "LineEdit", box(Color(0.08, 0.08, 0.08), Color(0.20, 0.20, 0.20)))
	_theme.set_type_variation("CoopCard", "PanelContainer")
	var card := box(Color(0.075, 0.105, 0.088), Color(0.17, 0.24, 0.195), 10)
	card.content_margin_top = 9
	card.content_margin_bottom = 9
	_theme.set_stylebox("panel", "CoopCard", card)
	_theme.set_type_variation("CoopSurface", "PanelContainer")
	_theme.set_stylebox("panel", "CoopSurface", StyleBoxEmpty.new())
	_theme.set_type_variation("CoopPrimary", "Button")
	_theme.set_stylebox("normal", "CoopPrimary", box(ACCENT, ACCENT, 10))
	_theme.set_stylebox("hover", "CoopPrimary", box(ACCENT.lightened(0.12), ACCENT.lightened(0.12), 10))
	_theme.set_stylebox("pressed", "CoopPrimary", box(ACCENT.darkened(0.2), ACCENT.darkened(0.2), 10))
	_theme.set_color("font_color", "CoopPrimary", Color(0.035, 0.10, 0.06))
	_theme.set_color("font_hover_color", "CoopPrimary", Color(0.035, 0.10, 0.06))
	_theme.set_type_variation("CoopTab", "Button")
	var active := box(Color(0.12, 0.23, 0.16), Color(0.12, 0.23, 0.16), 10)
	active.border_color = ACCENT
	active.set_border_width_all(0)
	active.border_width_left = 3
	_theme.set_stylebox("normal", "CoopTab", box(Color(0.075, 0.105, 0.088), Color(0.075, 0.105, 0.088), 10))
	_theme.set_stylebox("pressed", "CoopTab", active)
	_theme.set_stylebox("hover_pressed", "CoopTab", active)
	_theme.set_color("font_pressed_color", "CoopTab", ACCENT)
	_theme.set_color("font_hover_pressed_color", "CoopTab", ACCENT)
	_theme.set_color("font_color", "CoopTab", MUTED)
	_theme.set_constant("outline_size", "Label", 0)
	_theme.set_constant("shadow_offset_x", "Label", 0)
	_theme.set_constant("shadow_offset_y", "Label", 0)
	var track := box(Color(0.08, 0.08, 0.08), Color(0.27, 0.27, 0.27), 0)
	track.content_margin_top = 2
	track.content_margin_bottom = 2
	_theme.set_stylebox("slider", "HSlider", track)
	_theme.set_stylebox("grabber_area", "HSlider", box(ACCENT.darkened(0.3), ACCENT.darkened(0.3), 0))
	_theme.set_stylebox("grabber_area_highlight", "HSlider", box(ACCENT, ACCENT, 0))
	var grabber := GradientTexture2D.new()
	grabber.width = 8
	grabber.height = 12
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([ACCENT, ACCENT])
	grabber.gradient = gradient
	_theme.set_icon("grabber", "HSlider", grabber)
	_theme.set_icon("grabber_highlight", "HSlider", grabber)
	var scroll_track := box(Color(0.08, 0.08, 0.08), Color(0.08, 0.08, 0.08), 3)
	_theme.set_stylebox("scroll", "VScrollBar", scroll_track)
	_theme.set_stylebox("grabber", "VScrollBar", normal)
	_theme.set_stylebox("grabber_highlight", "VScrollBar", hover)
	_theme.set_stylebox("grabber_pressed", "VScrollBar", pressed)
	return _theme
