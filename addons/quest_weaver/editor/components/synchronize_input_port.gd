# res://addons/quest_weaver/editor/components/synchronize_input_port.gd
@tool
class_name SynchronizeInputPort
extends Resource

## Defines a single input port of a SynchronizeNode.

## The name displayed on the port in the GraphEdit.
@export var port_name: StringName = &"In"


func to_dictionary() -> Dictionary:
	var data: Dictionary = {
		"@script_path": get_script().get_path(),
		"port_name": port_name,
	}
	return data

func from_dictionary(data: Dictionary) -> void:
	port_name = StringName(data.get("port_name", &"In"))
