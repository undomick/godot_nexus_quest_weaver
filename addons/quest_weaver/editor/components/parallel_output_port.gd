# res://addons/quest_weaver/editor/components/parallel_output_port.gd
@tool

class_name ParallelOutputPort

extends Resource

@export var port_name: StringName = &"Out"

## An optional condition that must be met for this output to activate.
## If null, the output will always activate.
@export var condition: ConditionResource

## Contains the configuration for a single output of a ParallelNode.

## The name displayed on the port in the GraphEdit.


func _init() -> void:
	condition = ConditionResource.new()
	condition.type = ConditionResource.ConditionType.BOOL


func to_dictionary() -> Dictionary:
	var data: Dictionary = {"@script_path": get_script().resource_path, "port_name": port_name}

	if is_instance_valid(condition):
		data["condition"] = condition.to_dictionary()

	return data


func from_dictionary(data: Dictionary) -> void:
	port_name = StringName(data.get("port_name", &"Out"))

	var condition_data: Variant = data.get("condition")
	if condition_data is Dictionary:
		var new_cond = GraphNodeResource.new_condition_from_path(condition_data.get("@script_path"))
		if is_instance_valid(new_cond):
			condition = new_cond as ConditionResource
			condition.from_dictionary(condition_data)
