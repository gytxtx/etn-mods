extends RefCounted

## 与官方联机菜单（2026-10-18 卡片化布局）一致的样式助手。
## 页面挂在官方菜单的 PageContent 下，字体与按钮/输入框样式继承官方 coop_theme；
## 这里只补卡片、分隔线、说明文字与语义色，避免自带整套主题造成两套观感。

# 与官方联机菜单状态栏一致的语义色（OK / DANGER）。
const ACCENT := Color(0.2, 0.9, 0.35)
const ERROR := Color(0.95, 0.18, 0.12)
const CARD_BG := Color(0.101961, 0.101961, 0.101961)
const CARD_BORDER := Color(0.223529, 0.223529, 0.223529)
const TEXT := Color(1, 1, 1)
const SECTION := Color(0.819608, 0.819608, 0.819608)
const DIM := Color(0.74902, 0.780392, 0.764706)

const SECTION_FONT_SIZE := 12
const ROW_FONT_SIZE := 11
const NOTE_FONT_SIZE := 9
const CONTROL_HEIGHT := 26.0
const LABEL_WIDTH := 132.0


## 返回 {panel, content}：panel 用于整卡显隐，content 用于填充内容。
static func card(parent: Container, title_key: String) -> Dictionary:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = CARD_BG
	style.border_color = CARD_BORDER
	style.set_border_width_all(1)
	style.content_margin_left = 6.0
	style.content_margin_top = 6.0
	style.content_margin_right = 6.0
	style.content_margin_bottom = 6.0
	style.anti_aliasing = false
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)

	var header := Label.new()
	header.text = title_key
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_theme_font_size_override("font_size", SECTION_FONT_SIZE)
	header.add_theme_color_override("font_color", SECTION)
	box.add_child(header)

	var divider := ColorRect.new()
	divider.custom_minimum_size = Vector2(0, 1)
	divider.color = CARD_BORDER
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(divider)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 4)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(content)
	return {"panel": panel, "content": content}


static func note(parent: Container, text: String = "") -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", NOTE_FONT_SIZE)
	label.add_theme_color_override("font_color", DIM)
	parent.add_child(label)
	return label


static func row(parent: Container, separation: int = 6) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_theme_constant_override("separation", separation)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)
	return line


static func row_label(parent: Container, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(LABEL_WIDTH, CONTROL_HEIGHT)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
	label.add_theme_color_override("font_color", TEXT)
	parent.add_child(label)
	return label


static func line_edit(parent: Container) -> LineEdit:
	var input := LineEdit.new()
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.custom_minimum_size = Vector2(0, CONTROL_HEIGHT)
	input.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(input)
	return input
