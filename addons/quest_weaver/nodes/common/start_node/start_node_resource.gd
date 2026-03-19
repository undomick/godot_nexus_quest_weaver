# res://addons/quest_weaver/nodes/common/start_node/start_node_resource.gd
@tool
class_name StartNodeResource
extends GraphNodeResource

@export var graph_category: String = ""


func _init():
	category = "Default"
	input_ports = []  # Entry point has no inputs
	output_ports = ["Out"]


func get_editor_summary() -> String:
	if graph_category.is_empty():
		return ""
	return "[%s]" % graph_category


func get_description() -> String:
	return "The entry point of the quest graph. Execution begins here."


func get_icon() -> Texture2D:
	return preload("res://addons/quest_weaver/assets/icons/flag.svg")


func determine_default_size() -> QWNodeSizes.Size:
	return QWNodeSizes.Size.TINY


func to_dictionary() -> Dictionary:
	var data = super.to_dictionary()
	data["graph_category"] = self.graph_category
	return data


func from_dictionary(data: Dictionary):
	super.from_dictionary(data)
	self.graph_category = data.get("graph_category", "")
