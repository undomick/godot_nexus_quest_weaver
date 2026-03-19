# res://addons/quest_weaver/nodes/flow/wait_node/wait_node_resource.gd
@tool
class_name WaitNodeResource
extends GraphNodeResource

# wait time in seconds
@export_range(0.1, 600.0, 0.1) var wait_duration: float = 1.0


func _init():
	category = "Flow"
	input_ports = ["In"]
	output_ports = ["Out"]


func get_editor_summary() -> String:
	return "Wait for %s s" % wait_duration


func get_description() -> String:
	return "Pauses the execution of this quest branch for a specific amount of seconds."


func get_icon() -> Texture2D:
	return preload("res://addons/quest_weaver/assets/icons/hourglass.svg")


func to_dictionary() -> Dictionary:
	var data = super.to_dictionary()
	data["wait_duration"] = self.wait_duration
	return data


func from_dictionary(data: Dictionary):
	super.from_dictionary(data)
	self.wait_duration = float(data.get("wait_duration", 1.0))


func determine_default_size() -> QWNodeSizes.Size:
	return QWNodeSizes.Size.SMALL
