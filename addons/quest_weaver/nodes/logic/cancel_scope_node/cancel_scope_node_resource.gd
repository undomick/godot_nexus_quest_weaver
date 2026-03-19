# res://addons/quest_weaver/nodes/logic/cancel_scope_node/cancel_scope_node_resource.gd
@tool
class_name CancelScopeNodeResource
extends GraphNodeResource

## Cancels a scope: cleans up all nodes within it and optionally continues flow.
## Does not restart the scope (unlike Reset Progress).

@export var target_scope_id: StringName = &""


func _init() -> void:
	category = "Logic"
	input_ports = ["In"]
	output_ports = ["Out"]


func get_editor_summary() -> String:
	if target_scope_id.is_empty():
		return "Cancel Scope:\n[No Target!]"
	return "Cancel Scope:\n'%s'" % target_scope_id


func get_display_name() -> String:
	return "Cancel Scope"


func get_description() -> String:
	return "Stops a scope by cleaning up all nodes within it. Use to abort a scope and optionally continue elsewhere."


func get_icon() -> Texture2D:
	return preload("res://addons/quest_weaver/assets/icons/erase.svg")


func to_dictionary() -> Dictionary:
	var data = super.to_dictionary()
	data["target_scope_id"] = target_scope_id
	return data


func from_dictionary(data: Dictionary) -> void:
	super.from_dictionary(data)
	target_scope_id = StringName(data.get("target_scope_id", &""))


func _validate(_context: Dictionary) -> Array[ValidationResult]:
	var results: Array[ValidationResult] = []
	if target_scope_id.is_empty():
		results.append(
			ValidationResult.new(
				ValidationResult.Severity.ERROR, "Cancel Scope: Target Scope ID is not set.", id
			)
		)
	return results


func determine_default_size() -> QWNodeSizes.Size:
	return QWNodeSizes.Size.SMALL
