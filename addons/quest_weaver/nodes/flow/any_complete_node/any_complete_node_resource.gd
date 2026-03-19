# res://addons/quest_weaver/nodes/flow/any_complete_node/any_complete_node_resource.gd
@tool

class_name AnyCompleteNodeResource

extends GraphNodeResource

## Flow node that continues as soon as the FIRST of multiple parallel inputs completes.
## Use when one of several alternative paths should trigger the next step (race pattern).

@export var keep_listening: bool = false

@export var input_count: int:
	get:
		return _input_count
	set(v):
		_input_count = clampi(v, 1, 16)
		_update_ports_from_data()

var _input_count: int = 2


func _init() -> void:
	category = "Flow"
	_update_ports_from_data()


func _update_ports_from_data() -> void:
	input_ports.clear()
	for i in range(max(1, input_count)):
		input_ports.append(StringName("In %d" % (i + 1)))
	output_ports.clear()
	if not is_terminal:
		output_ports.append(&"Out")


func get_editor_summary() -> String:
	var loop_text = " [Loop]" if keep_listening else ""
	return "First of %d%s\n-> Out" % [input_count, loop_text]


func get_display_name() -> String:
	return "Any Complete"


func get_description() -> String:
	return "Continues as soon as the first of multiple parallel inputs completes. Use for alternative paths or race conditions."


func get_icon() -> Texture2D:
	return preload("res://addons/quest_weaver/assets/icons/join.svg")


func to_dictionary() -> Dictionary:
	var data = super.to_dictionary()
	data["keep_listening"] = keep_listening
	data["input_count"] = input_count
	return data


func from_dictionary(data: Dictionary) -> void:
	super.from_dictionary(data)
	keep_listening = data.get("keep_listening", false)
	input_count = clampi(int(data.get("input_count", 2)), 1, 16)
	_update_ports_from_data()


func add_input(_payload: Dictionary = {}) -> void:
	if input_count < 16:
		input_count += 1
		_update_ports_from_data()


func remove_input(payload: Dictionary = {}) -> void:
	if input_count <= 1:
		return
	var idx = payload.get("index", input_count - 1)
	if idx >= 0 and idx < input_count:
		input_count -= 1
		_update_ports_from_data()


func determine_default_size() -> QWNodeSizes.Size:
	return QWNodeSizes.Size.SMALL
