class_name QuestDataManager
extends RefCounted

## Manages quest data queries and instance/node lookups.
## Holds get_quest_state, get_quest_data, get_all_managed_quests_data, get_quest_variable,
## get_quest_id_for_node, get_instance_for_node, get_node_definition,
## set_quest_description, set_quest_description_by_quest_id, add_quest_log_entry.
## Extracted from QuestController to reduce max-public-methods.

var _controller_weak: WeakRef


func _init(p_controller: QuestController) -> void:
	_controller_weak = weakref(p_controller)


func _get_controller() -> QuestController:
	return _controller_weak.get_ref() as QuestController


func get_quest_state(query_id: StringName) -> int:
	var controller = _get_controller()
	if not controller:
		return QWEnums.QuestState.UNAVAILABLE

	var file_id = controller._resolve_instance_file_id(query_id)
	var instance = controller._pool_registry.get_instance_by_file_id(file_id)
	if instance:
		return instance.current_status
	return QWEnums.QuestState.UNAVAILABLE


func get_quest_data(query_id: StringName) -> Dictionary:
	var result = {}
	var controller = _get_controller()
	if not controller:
		result["id"] = query_id
		result["status"] = QWEnums.QuestState.UNAVAILABLE
		result["log_entries"] = []
		return result

	var context_node = controller._id_to_context_node_map.get(query_id)
	if context_node:
		result["title"] = context_node.quest_title
		result["description"] = context_node.quest_description
		result["quest_type"] = context_node.quest_type
		result["rewards"] = {}

	var file_id = controller._resolve_instance_file_id(query_id)
	var instance = controller._pool_registry.get_instance_by_file_id(file_id)
	if instance:
		result["id"] = query_id
		result["status"] = instance.current_status
		result["log_entries"] = instance.get_variable("_logs", [])
		if context_node:
			result["title"] = instance.resolve_text(context_node.quest_title, null)
			var base_desc = context_node.quest_description
			var runtime_desc = instance.get_variable("_description_override", "")
			if not runtime_desc.is_empty():
				result["description"] = runtime_desc
			else:
				result["description"] = instance.resolve_text(base_desc, null)
	else:
		result["id"] = query_id
		result["status"] = QWEnums.QuestState.UNAVAILABLE
		result["log_entries"] = []

	return result


func get_all_managed_quests_data() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	var controller = _get_controller()
	if not controller:
		return list

	var processed_instance_ids: Dictionary = {}
	for q_id in controller._id_to_context_node_map:
		var context_node = controller._id_to_context_node_map[q_id]
		var instance_id = context_node.get_instance_id()
		if processed_instance_ids.has(instance_id):
			continue
		processed_instance_ids[instance_id] = true

		var primary_id = q_id
		if not context_node.quest_id.is_empty():
			primary_id = context_node.quest_id

		list.append(get_quest_data(primary_id))

	return list


## Retrieves a runtime variable from a specific quest instance.
func get_quest_variable(query_id: StringName, key: StringName, default: Variant = null) -> Variant:
	var controller = _get_controller()
	if not controller:
		return default

	var file_id = controller._resolve_instance_file_id(query_id)
	var instance = controller._pool_registry.get_instance_by_file_id(file_id)
	if instance:
		return instance.get_variable(key, default)
	return default


func get_quest_id_for_node(node_id: StringName) -> StringName:
	var controller = _get_controller()
	if not controller:
		return &""
	return controller._get_file_id_for_node(node_id)


## Returns the QuestInstance that owns the given node_id, or null if not found.
func get_instance_for_node(node_id: StringName) -> QuestInstance:
	var controller = _get_controller()
	if not controller:
		return null

	var file_id = controller._get_file_id_for_node(node_id)
	if file_id.is_empty():
		return null
	return controller._pool_registry.get_instance_by_file_id(file_id) as QuestInstance


## Returns the node definition for the given node_id, or null if not found.
func get_node_definition(node_id: StringName) -> GraphNodeResource:
	var controller = _get_controller()
	if not controller:
		return null
	return controller._node_definitions.get(node_id) as GraphNodeResource


func set_quest_description(node_id: StringName, description: String) -> void:
	var controller = _get_controller()
	if not controller:
		return

	var file_id = controller._get_file_id_for_node(node_id)
	if not file_id.is_empty() and controller._pool_registry.has_instance(file_id):
		var instance = controller._pool_registry.get_instance_by_file_id(file_id)
		instance.set_variable("_description_override", description)
		var signal_id = controller._get_signal_id_for_instance(instance)
		controller.quest_data_changed.emit(signal_id)


## Convenience: Set description by quest_id, file_id, or node_id.
func set_quest_description_by_quest_id(quest_id: StringName, description: String) -> void:
	var controller = _get_controller()
	if not controller:
		return

	var ctx = controller._id_to_context_node_map.get(quest_id)
	if not ctx:
		var file_id = controller._resolve_instance_file_id(quest_id)
		ctx = controller._id_to_context_node_map.get(file_id)
	if not ctx:
		var node_def = controller._node_definitions.get(quest_id)
		if node_def is QuestContextNodeResource:
			ctx = node_def
	if ctx:
		set_quest_description(ctx.id, description)
	else:
		var file_id = controller._get_file_id_for_node(quest_id)
		if not file_id.is_empty():
			set_quest_description(quest_id, description)


func add_quest_log_entry(node_id: StringName, log_text: String) -> void:
	var controller = _get_controller()
	if not controller:
		return

	var file_id = controller._get_file_id_for_node(node_id)
	if not file_id.is_empty() and controller._pool_registry.has_instance(file_id):
		var instance = controller._pool_registry.get_instance_by_file_id(file_id)
		var stored = instance.get_variable("_logs", [])
		var logs: Array = (stored as Array).duplicate()
		logs.append(log_text)
		instance.set_variable("_logs", logs)
		var signal_id = controller._get_signal_id_for_instance(instance)
		controller.quest_data_changed.emit(signal_id)
