# res://addons/quest_weaver/nodes/flow/jump_node/jump_node_resource.gd
@tool
class_name JumpNodeResource
extends GraphNodeResource

@export var target_anchor_name: StringName = &""


func _init() -> void:
	category = "Flow"
	input_ports = ["In"]
	output_ports = []  # No output port, the flow jumps elsewhere


func get_display_name() -> String:
	return "Jump To"


func get_description() -> String:
	return "Teleports the execution flow to an Anchor Node with the matching name within this graph."


func get_icon() -> Texture2D:
	return preload("res://addons/quest_weaver/assets/icons/jumper.svg")


func determine_default_size() -> QWNodeSizes.Size:
	return QWNodeSizes.Size.SMALL


func get_editor_summary() -> String:
	if target_anchor_name.is_empty():
		return "[WARN]No Target"
	return "Jump to:\n-> [%s]" % target_anchor_name


func to_dictionary() -> Dictionary:
	var data = super.to_dictionary()
	data["target_anchor_name"] = self.target_anchor_name
	return data


func from_dictionary(data: Dictionary):
	super.from_dictionary(data)
	self.target_anchor_name = StringName(data.get("target_anchor_name", &""))


func _validate(_context: Dictionary) -> Array[ValidationResult]:
	var results: Array[ValidationResult] = []
	if target_anchor_name.is_empty():
		results.append(
			ValidationResult.new(
				ValidationResult.Severity.ERROR, "Jump Node: Target anchor name is not set.", id
			)
		)
	return results
