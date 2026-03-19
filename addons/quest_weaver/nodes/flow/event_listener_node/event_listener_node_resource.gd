# res://addons/quest_weaver/nodes/flow/event_listener_node/event_listener_node_resource.gd
@tool

class_name EventListenerNodeResource

extends GraphNodeResource

enum SimpleOperator {
	EQUALS, NOT_EQUALS, GREATER_THAN, LESS_THAN, GREATER_OR_EQUAL, LESS_OR_EQUAL, HAS
}

@export var event_name: StringName = &"my_game_event"

@export var payload_condition: ConditionResource

@export var use_simple_conditions: bool = true

@export var simple_conditions: Array[Dictionary] = []  # Format: [{"key": "", "op": 0, "value": ""}]

@export var keep_listening: bool = false


func _init() -> void:
	category = "Flow"
	input_ports = ["In", "Cancel"]
	output_ports = ["On Event", "On Cancel"]

	if id.is_empty() and not is_instance_valid(payload_condition):
		payload_condition = ConditionResource.new()


func get_editor_summary() -> String:
	var event_name_text = event_name if not event_name.is_empty() else "???"
	var loop_text = " [Loop]" if keep_listening else ""
	return "Listen for:%s\n'%s'" % [loop_text, event_name_text]


func get_description() -> String:
	return "Pauses the flow until a specific global event is received from the game."


func get_icon() -> Texture2D:
	return preload("res://addons/quest_weaver/assets/icons/listener.svg")


func to_dictionary() -> Dictionary:
	var data = super.to_dictionary()
	data["event_name"] = self.event_name
	data["use_simple_conditions"] = self.use_simple_conditions
	data["simple_conditions"] = self.simple_conditions
	data["keep_listening"] = self.keep_listening

	if is_instance_valid(payload_condition):
		data["payload_condition"] = payload_condition.to_dictionary()
	return data


func from_dictionary(data: Dictionary):
	super.from_dictionary(data)
	self.event_name = StringName(data.get("event_name", &"my_game_event"))
	self.use_simple_conditions = data.get("use_simple_conditions", true)
	self.keep_listening = data.get("keep_listening", false)

	var loaded_conditions = data.get("simple_conditions", [])
	if loaded_conditions is Array:
		self.simple_conditions.assign(loaded_conditions)

	var cond_data = data.get("payload_condition")
	if cond_data is Dictionary:
		var new_cond = GraphNodeResource.new_condition_from_path(cond_data.get("@script_path"))
		if is_instance_valid(new_cond):
			self.payload_condition = new_cond as ConditionResource
			self.payload_condition.from_dictionary(cond_data)


func _validate(_context: Dictionary) -> Array[ValidationResult]:
	var results: Array[ValidationResult] = []

	if event_name.is_empty():
		results.append(
			ValidationResult.new(
				ValidationResult.Severity.ERROR, "Event Listener: Event Name is not set.", id
			)
		)

	return results


func determine_default_size() -> QWNodeSizes.Size:
	return QWNodeSizes.Size.LARGE
