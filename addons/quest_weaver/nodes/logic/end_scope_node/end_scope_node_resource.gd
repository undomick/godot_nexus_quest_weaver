# res://addons/quest_weaver/nodes/logic/end_scope_node/end_scope_node_resource.gd
@tool
class_name EndScopeNodeResource
extends GraphNodeResource

## Must match the ID of a StartScopeNode within the same graph.
@export var scope_id: StringName = &"my_scope_1"


func _init():
	category = "Logic"
	input_ports = ["In"]
	_update_ports_from_data()


func _update_ports_from_data() -> void:
	if is_terminal:
		output_ports = []
	else:
		output_ports = [&"Scope Completed"]


func get_editor_summary() -> String:
	var id_text = String(scope_id) if not scope_id.is_empty() else "???"
	return "End Scope:\n'%s'" % id_text


func get_description() -> String:
	return "Marks the boundary of a Scope. Used to define what should be reset."


func get_icon() -> Texture2D:
	return preload("res://addons/quest_weaver/assets/icons/end_scope.svg")


func to_dictionary() -> Dictionary:
	var data = super.to_dictionary()
	data["scope_id"] = self.scope_id
	return data


func from_dictionary(data: Dictionary):
	if not data is Dictionary:
		return
	super.from_dictionary(data)
	self.scope_id = StringName(data.get("scope_id", &"my_scope_1"))
	_update_ports_from_data()


func _validate(_context: Dictionary) -> Array[ValidationResult]:
	var results: Array[ValidationResult] = []
	if scope_id.is_empty():
		results.append(
			ValidationResult.new(
				ValidationResult.Severity.ERROR, "End Scope: Scope ID is not set.", id
			)
		)
	return results


func determine_default_size() -> QWNodeSizes.Size:
	return QWNodeSizes.Size.SMALL
