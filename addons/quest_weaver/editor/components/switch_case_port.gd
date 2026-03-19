@tool
class_name SwitchCasePort
extends Resource

## Defines a single case in a Switch node: when variable equals value_string, flow goes to this output.

@export var value_string: String = ""
@export var port_name: StringName = &"Case"


func to_dictionary() -> Dictionary:
	return {
		"@script_path": get_script().resource_path,
		"value_string": value_string,
		"port_name": port_name
	}


func from_dictionary(data: Dictionary) -> void:
	value_string = str(data.get("value_string", ""))
	port_name = StringName(data.get("port_name", &"Case"))
