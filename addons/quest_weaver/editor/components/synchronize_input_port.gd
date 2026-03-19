# res://addons/quest_weaver/editor/components/synchronize_input_port.gd
@tool

class_name SynchronizeInputPort

extends Resource

@export var port_name: StringName = &"In"

## Defines a single input port of a SynchronizeNode.

## The name displayed on the port in the GraphEdit.


func to_dictionary() -> Dictionary:
	var data: Dictionary = {
		"@script_path": get_script().resource_path,
		"port_name": port_name,
	}
	return data


func from_dictionary(data: Dictionary) -> void:
	port_name = StringName(data.get("port_name", &"In"))
