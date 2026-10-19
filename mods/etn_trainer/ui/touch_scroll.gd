extends ScrollContainer

## 触屏 / 鼠标拖动滚动。
##
## 项目 `pointing/emulate_mouse_from_touch=false`（本体 project.godot），
## ScrollContainer 原生只认滚轮与滚动条拖拽；移动端页面与敌人列表必须自己处理
## `InputEventScreenTouch` / `InputEventScreenDrag`。
##
## 触屏按下即 `accept_event()`：嵌在内层滚动区上的手势不会再带动外层页面。
## 鼠标左键拖动保留给桌面，滚轮与滚动条仍走原生路径。

var _touch_index: int = -1
var _touch_start_y: float = 0.0
var _touch_start_scroll: int = 0
var _mouse_dragging: bool = false
var _mouse_start_y: float = 0.0
var _mouse_start_scroll: int = 0


func _ready() -> void:
	gui_input.connect(_on_gui_input)
	visibility_changed.connect(_on_visibility_changed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_cancel()


func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		_cancel()


func _cancel() -> void:
	_touch_index = -1
	_mouse_dragging = false


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if touch.canceled or _touch_index != -1:
				return
			_touch_index = touch.index
			_touch_start_y = touch.position.y
			_touch_start_scroll = scroll_vertical
			accept_event()
		elif touch.index == _touch_index:
			_touch_index = -1
			accept_event()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index != _touch_index:
			return
		scroll_vertical = _touch_start_scroll - int(round(drag.position.y - _touch_start_y))
		accept_event()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT or mb.device == InputEvent.DEVICE_ID_EMULATION:
			return
		if mb.pressed:
			_mouse_dragging = true
			_mouse_start_y = mb.position.y
			_mouse_start_scroll = scroll_vertical
		else:
			_mouse_dragging = false
	elif event is InputEventMouseMotion and _mouse_dragging:
		var motion := event as InputEventMouseMotion
		if not (motion.button_mask & MOUSE_BUTTON_MASK_LEFT):
			_mouse_dragging = false
			return
		scroll_vertical = _mouse_start_scroll - int(round(motion.position.y - _mouse_start_y))
