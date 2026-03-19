# res://addons/quest_weaver/nodes/logic/reset_progress_node/reset_progress_node_resource.gd
@tool
class_name ResetProgressNodeResource
extends GraphNodeResource

## Resets the progress of all nodes within a defined Scope
## (starting with a 'Start Scope Node') and optionally restarts it.

@export var target_scope_id: StringName = &""
@export var restart_scope_on_completion: bool = true


func _init():
	category = "Logic"
	input_ports = ["In"]
	# This node has an optional output. Logic can continue here after a reset,
	# although usually the flow jumps back to the StartScopeNode.
	output_ports = ["On Reset"]


func get_editor_summary() -> String:
	var line1 = "Reset Scope:"
	var line2: String

	if target_scope_id.is_empty():
		line2 = "[WARN]No Target!"
	else:
		line2 = "'%s'" % target_scope_id

	return "%s\n%s" % [line1, line2]


func get_description() -> String:
	return "Resets all nodes within a specific Scope to their initial state to allow replaying."


func get_icon() -> Texture2D:
	return preload("res://addons/quest_weaver/assets/icons/erase.svg")


func to_dictionary() -> Dictionary:
	var data = super.to_dictionary()
	data["target_scope_id"] = self.target_scope_id
	data["restart_scope_on_completion"] = self.restart_scope_on_completion
	return data


func from_dictionary(data: Dictionary):
	super.from_dictionary(data)
	self.target_scope_id = StringName(data.get("target_scope_id", &""))
	self.restart_scope_on_completion = data.get("restart_scope_on_completion", true)


func _validate(_context: Dictionary) -> Array[ValidationResult]:
	var results: Array[ValidationResult] = []
	if target_scope_id.is_empty():
		results.append(
			ValidationResult.new(
				ValidationResult.Severity.ERROR, "Reset Progress: Target Scope ID is not set.", id
			)
		)
	return results


func determine_default_size() -> QWNodeSizes.Size:
	return QWNodeSizes.Size.SMALL
