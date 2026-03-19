# res://addons/quest_weaver/nodes/action/event_node/event_node_resource.gd
@tool

class_name EventNodeResource
extends GraphNodeResource


class PayloadEntry:
	extends Resource
	enum Type { STRING, INT, FLOAT, BOOL }
	@export var key: StringName = &"my_key"
	@export var value_string: String = ""
	@export var value_type: Type = Type.STRING

	func to_dictionary() -> Dictionary:
		return {"key": key, "value_string": value_string, "value_type": value_type}


## The name of the global event to fire.
@export var event_name: StringName = &"my_quest_event"

## A List of PayloadEntries
@export var payload_entries: Array[PayloadEntry] = []


func _init() -> void:
	category = "Action"
	input_ports = ["In"]
	_update_ports_from_data()


func _update_ports_from_data() -> void:
	if is_terminal:
		output_ports = []
	else:
		output_ports = ["Out"]


func get_editor_summary() -> String:
	if event_name.is_empty():
		return "[WARN]No Event Name"
	else:
		return "Fire Event:\n'%s'" % event_name


func get_description() -> String:
	return "Fires a global signal ('quest_event_fired') to trigger external game logic (e.g., open door)."


func get_icon() -> Texture2D:
	return preload("res://addons/quest_weaver/assets/icons/signal.svg")


func get_runtime_payload() -> Dictionary:
	var payload: Dictionary = {}
	for entry in payload_entries:
		if not is_instance_valid(entry) or entry.key.is_empty():
			continue

		var parsed_value: Variant

		match entry.value_type:
			PayloadEntry.Type.INT:
				parsed_value = entry.value_string.to_int()
			PayloadEntry.Type.FLOAT:
				parsed_value = entry.value_string.to_float()
			PayloadEntry.Type.BOOL:
				parsed_value = entry.value_string.to_lower() == "true"
			PayloadEntry.Type.STRING:
				parsed_value = entry.value_string

		payload[entry.key] = parsed_value

	return payload


# Serialization remains the same, but with new variable names.
func to_dictionary() -> Dictionary:
	var data = super.to_dictionary()
	data["event_name"] = self.event_name
	var entries_data = []
	for entry in self.payload_entries:
		if is_instance_valid(entry):
			entries_data.append(entry.to_dictionary())

	data["payload_entries"] = entries_data
	return data


func from_dictionary(data: Dictionary):
	super.from_dictionary(data)
	self.event_name = StringName(data.get("event_name", &"my_quest_event"))
	self.payload_entries.clear()
	var entries_data = data.get("payload_entries", [])
	for entry_dict in entries_data:
		var new_entry = PayloadEntry.new()
		new_entry.key = StringName(entry_dict.get("key", &"my_key"))
		new_entry.value_string = str(entry_dict.get("value_string", ""))
		new_entry.value_type = _defensive_load(
			entry_dict, "value_type", PayloadEntry.Type.keys(), PayloadEntry.Type.STRING
		)
		self.payload_entries.append(new_entry)
	_update_ports_from_data()


func _defensive_load(data: Dictionary, prop: String, keys: Array, default_val: int) -> int:
	var val = data.get(prop, default_val)
	if val is int and val >= 0 and val < keys.size():
		return val
	return default_val


func _validate(_context: Dictionary) -> Array[ValidationResult]:
	var results: Array[ValidationResult] = []
	if event_name.is_empty():
		results.append(
			ValidationResult.new(
				ValidationResult.Severity.ERROR, "Event Node: Event name is not set.", id
			)
		)
	return results


func determine_default_size() -> QWNodeSizes.Size:
	return QWNodeSizes.Size.SMALL
