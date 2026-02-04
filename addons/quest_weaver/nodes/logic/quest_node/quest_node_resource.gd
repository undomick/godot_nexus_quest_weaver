# res://addons/quest_weaver/nodes/logic/quest_node/quest_node_resource.gd
@tool
class_name QuestNodeResource
extends GraphNodeResource

enum QuestAction {
	COMPLETE, # Sets the status to COMPLETED
	FAIL,     # Sets the status to FAILED
	START     # Explicitly starts another quest (rare but powerful)
}

## Reference to the Quest ID that should be affected.
@export var target_quest_id: StringName = &""
@export var action: QuestAction = QuestAction.COMPLETE

func _init() -> void:
	category = "Logic"
	input_ports = ["In"]
	_update_ports_from_data()

func get_editor_summary() -> String:
	if not target_quest_id.is_empty():
		var id_text = target_quest_id
		return "%s:\n'%s'" % [QuestAction.keys()[action].capitalize(), id_text]
	else:
		return "[WARN]%s:\n???" % QuestAction.keys()[action].capitalize()

func get_display_name() -> String:
	return "Set Quest Node"

func get_description() -> String:
	return "Manipulates the state of another quest (Start, Complete, or Fail) from within this graph."

func get_icon() -> Texture2D:
	return preload("res://addons/quest_weaver/assets/icons/quest.svg")

func _update_ports_from_data() -> void:
	if is_terminal:
		output_ports = []
	else:
		output_ports = ["Out"]

func to_dictionary() -> Dictionary:
	var data = super.to_dictionary()
	data["target_quest_id"] = self.target_quest_id
	data["action"] = self.action
	return data

func from_dictionary(data: Dictionary):
	super.from_dictionary(data)
	self.target_quest_id = StringName(data.get("target_quest_id", &""))
	self.action = data.get("action", QuestAction.COMPLETE)
	_update_ports_from_data()

func _validate(context: Dictionary) -> Array[ValidationResult]:
	var results: Array[ValidationResult] = []
	var quest_registry = context.get("quest_registry")
	
	if target_quest_id == &"":
		results.append(ValidationResult.new(ValidationResult.Severity.ERROR, "Quest Node: Target Quest ID is not set.", id))
	elif is_instance_valid(quest_registry) and not quest_registry.quest_path_map.has(target_quest_id):
		results.append(ValidationResult.new(ValidationResult.Severity.WARNING, "Quest Node: Target Quest ID '%s' not found in the Quest Registry." % target_quest_id, id))
		
	return results

func determine_default_size() -> QWNodeSizes.Size:
	return QWNodeSizes.Size.SMALL
