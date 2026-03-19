# res://addons/quest_weaver/editor/components/random_output_port.gd
@tool
class_name RandomOutputPort
extends Resource

## Defines a single, weighted output of a RandomNode.

@export var port_name: StringName = &"Out"
@export_range(1, 1000) var weight: int = 50


func to_dictionary() -> Dictionary:
	var data: Dictionary = {
		"@script_path": get_script().resource_path, "port_name": port_name, "weight": weight
	}
	return data


func from_dictionary(data: Dictionary) -> void:
	port_name = StringName(data.get("port_name", &"Out"))
	weight = data.get("weight", 50)
