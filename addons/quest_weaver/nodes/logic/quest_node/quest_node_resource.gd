# res://addons/quest_weaver/nodes/logic/quest_node/quest_node_resource.gd
@tool
class_name QuestNodeResource
extends GraphNodeResource

enum QuestAction { COMPLETE, FAIL, START, MARK_AVAILABLE, MOVE_TO_CUSTOM_POOL }

## Reference to the Quest ID that should be affected.
@export var target_quest_id: StringName = &""
@export var action: QuestAction = QuestAction.COMPLETE
## Custom pool ID when action is MOVE_TO_CUSTOM_POOL. Must be registered in QuestWeaverSettings.
@export var custom_pool_id: StringName = &""


func _init() -> void:
	category = "Logic"
	input_ports = ["In"]
	_update_ports_from_data()


func get_editor_summary() -> String:
	if not target_quest_id.is_empty():
		var id_text = String(target_quest_id)
		var action_label = QuestAction.keys()[action].capitalize().replace("_", " ")
		if action == QuestAction.MOVE_TO_CUSTOM_POOL and not custom_pool_id.is_empty():
			return "%s:\n'%s' → %s" % [action_label, id_text, custom_pool_id]
		return "%s:\n'%s'" % [action_label, id_text]
	else:
		return "[WARN]%s:\n???" % QuestAction.keys()[action].capitalize().replace("_", " ")


func get_display_name() -> String:
	return "Set Quest Node"


func get_description() -> String:
	return "Manipulates the state of another quest (Start, Complete, Fail, Mark Available, or Move to Custom Pool) from within this graph."


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
	data["custom_pool_id"] = self.custom_pool_id
	return data


func from_dictionary(data: Dictionary):
	if not data is Dictionary:
		return
	super.from_dictionary(data)
	self.target_quest_id = StringName(data.get("target_quest_id", &""))
	self.action = _defensive_load(data, "action", QuestAction.keys(), QuestAction.COMPLETE)
	self.custom_pool_id = StringName(data.get("custom_pool_id", &""))
	_update_ports_from_data()


func _defensive_load(data: Dictionary, prop: String, keys: Array, default_val: int) -> int:
	var val = data.get(prop, default_val)
	if val is int and val >= 0 and val < keys.size():
		return val
	return default_val


func _validate(context: Dictionary) -> Array[ValidationResult]:
	var results: Array[ValidationResult] = []
	var quest_registry = context.get("quest_registry")

	if target_quest_id == &"":
		results.append(
			ValidationResult.new(
				ValidationResult.Severity.ERROR, "Quest Node: Target Quest ID is not set.", id
			)
		)
	elif (
		is_instance_valid(quest_registry) and not quest_registry.quest_path_map.has(target_quest_id)
	):
		results.append(
			ValidationResult.new(
				ValidationResult.Severity.WARNING,
				(
					"Quest Node: Target Quest ID '%s' not found in the Quest Registry."
					% target_quest_id
				),
				id
			)
		)
	if action == QuestAction.MOVE_TO_CUSTOM_POOL and custom_pool_id.is_empty():
		results.append(
			ValidationResult.new(
				ValidationResult.Severity.ERROR,
				"Quest Node: Custom Pool ID is not set for Move to Custom Pool action.",
				id
			)
		)
	elif action == QuestAction.MOVE_TO_CUSTOM_POOL:
		var pool_ids = QWEditorUtils.get_custom_pool_ids_from_settings()
		if not pool_ids.has(custom_pool_id):
			(
				results
				. append(
					(
						ValidationResult
						. new(
							ValidationResult.Severity.WARNING,
							(
								"Quest Node: Custom Pool '%s' not found in QuestWeaverSettings.additional_pool_scripts."
								% custom_pool_id
							),
							id
						)
					)
				)
			)
	return results


func determine_default_size() -> QWNodeSizes.Size:
	return QWNodeSizes.Size.SMALL
