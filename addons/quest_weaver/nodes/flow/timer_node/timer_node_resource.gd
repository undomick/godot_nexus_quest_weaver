# res://addons/quest_weaver/nodes/flow/timer_node/timer_node_resource.gd
@tool
class_name TimerNodeResource
extends GraphNodeResource

## A non-blocking timer that allows the quest flow to continue
## for a specific duration while emitting periodic signals.

@export_range(1, 3600, 1, "suffix:s") var duration: int = 10


func _init():
	category = "Flow"
	input_ports = ["In"]
	output_ports = ["On Start", "On Tick", "On Finish"]


func get_editor_summary() -> String:
	return "Duration: %d s" % duration


func get_description() -> String:
	return "Starts a background timer that triggers events on start, tick, and finish. Non-blocking."


func get_icon() -> Texture2D:
	return preload("res://addons/quest_weaver/assets/icons/timer.svg")


func to_dictionary() -> Dictionary:
	var data = super.to_dictionary()
	data["duration"] = self.duration
	return data


func from_dictionary(data: Dictionary):
	super.from_dictionary(data)
	self.duration = int(data.get("duration", 10))


func determine_default_size() -> QWNodeSizes.Size:
	return QWNodeSizes.Size.SMALL
