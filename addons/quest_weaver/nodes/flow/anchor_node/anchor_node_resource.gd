# res://addons/quest_weaver/nodes/flow/anchor_node/anchor_node_resource.gd
@tool
class_name AnchorNodeResource
extends GraphNodeResource

@export var anchor_name: StringName = &"MyAnchor"


func _init() -> void:
	category = "Flow"
	input_ports = []
	output_ports = ["Out"]


func get_display_name() -> String:
	return "Anchor"


func get_description() -> String:
	return "A named target point for Jump Nodes. Used to organize the graph without long wires."


func get_icon() -> Texture2D:
	return preload("res://addons/quest_weaver/assets/icons/anchor.svg")


func determine_default_size() -> QWNodeSizes.Size:
	return QWNodeSizes.Size.SMALL


func get_editor_summary() -> String:
	if anchor_name.is_empty():
		return "[WARN]Missing Name"
	return "Target:\n[%s]" % anchor_name


func to_dictionary() -> Dictionary:
	var data = super.to_dictionary()
	data["anchor_name"] = self.anchor_name
	return data


func from_dictionary(data: Dictionary):
	super.from_dictionary(data)
	self.anchor_name = StringName(data.get("anchor_name", &"MyAnchor"))


func _validate(_context: Dictionary) -> Array[ValidationResult]:
	var results: Array[ValidationResult] = []
	if anchor_name.is_empty():
		results.append(
			ValidationResult.new(
				ValidationResult.Severity.ERROR, "Anchor Node: Anchor name is not set.", id
			)
		)
	return results
