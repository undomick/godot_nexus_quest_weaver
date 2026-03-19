# res://addons/quest_weaver/editor/components/synchronize_output_port.gd
@tool
class_name SynchronizeOutputPort
extends Resource

## Defines a single output of a SynchronizeNode.
## Now holds a pattern definition matching the inputs.

@export var port_name: StringName = &"Out"

## Optional: A condition that is checked AFTER synchronization pattern match.
@export var condition: ConditionResource

## Stores the expected state for each input index.
## Values correspond to SynchronizeNodeResource.InputState
## [0: IGNORE, 1: REQUIRED, 2: FORBIDDEN]
@export var patterns: Array[int] = []


func _init() -> void:
	condition = ConditionResource.new()
	condition.type = ConditionResource.ConditionType.BOOL  # Default to always true if pattern matches


func to_dictionary() -> Dictionary:
	var data: Dictionary = {
		"@script_path": get_script().resource_path, "port_name": port_name, "patterns": patterns
	}

	if is_instance_valid(condition):
		data["condition"] = condition.to_dictionary()

	return data


func from_dictionary(data: Dictionary) -> void:
	port_name = StringName(data.get("port_name", &"Out"))

	var pat_data = data.get("patterns", [])
	if pat_data is Array:
		# JSON numbers come as floats often, force int
		patterns.clear()
		for val in pat_data:
			patterns.append(int(val))

	var condition_data: Variant = data.get("condition")
	if condition_data is Dictionary:
		var new_cond = GraphNodeResource.new_condition_from_path(condition_data.get("@script_path"))
		if is_instance_valid(new_cond):
			condition = new_cond as ConditionResource
			condition.from_dictionary(condition_data)
