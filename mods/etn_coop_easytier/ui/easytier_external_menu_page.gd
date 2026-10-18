extends "res://script/ScrollBox.gd"

## 本体禁用触屏模拟鼠标：Android 引导页沿用本体的同指拖动滚动。
func get_interactive_controls() -> Array[Control]:
	var controls: Array[Control] = [self, get_v_scroll_bar()]
	controls.append_array($Form.get_interactive_controls())
	return controls
