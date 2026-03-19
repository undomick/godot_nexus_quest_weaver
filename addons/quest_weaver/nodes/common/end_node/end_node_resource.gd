# res://addons/quest_weaver/nodes/common/end_node/end_node_resource.gd
@tool
class_name EndNodeResource
extends GraphNodeResource


func _init() -> void:
	category = "Default"
	input_ports = ["In"]
	output_ports = []


func get_editor_summary() -> String:
	return ""


func get_description() -> String:
	return "Marks the end of a quest branch. Does not necessarily finish the quest itself."


func get_icon() -> Texture2D:
	return preload("res://addons/quest_weaver/assets/icons/stop.svg")


func to_dictionary() -> Dictionary:
	return super.to_dictionary()


func from_dictionary(data: Dictionary):
	super.from_dictionary(data)


func determine_default_size() -> QWNodeSizes.Size:
	return QWNodeSizes.Size.TINY
