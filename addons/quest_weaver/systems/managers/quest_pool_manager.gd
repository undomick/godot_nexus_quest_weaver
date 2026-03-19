class_name QuestPoolManager
extends RefCounted

## Manages quest pool queries and pool state changes.
## Holds set_quest_available, get_*_quests, move_quest_to_custom_pool.
## Extracted from QuestController to reduce max-public-methods.

var _controller_weak: WeakRef


func _init(p_controller: QuestController) -> void:
	_controller_weak = weakref(p_controller)


func _get_controller() -> QuestController:
	return _controller_weak.get_ref() as QuestController


## Marks a quest as AVAILABLE (e.g. for Quest Board). Auto-loads if registered.
func set_quest_available(query_id: StringName) -> void:
	if query_id.is_empty():
		return

	var controller = _get_controller()
	if not controller:
		return
	if not controller._ensure_quest_loaded(query_id):
		var logger = controller._get_logger()
		if logger:
			logger.warn("Flow", "set_quest_available: Could not load '%s'." % query_id)
		return

	var file_id = controller._resolve_instance_file_id(query_id)
	var instance = controller._get_or_create_instance(file_id, query_id)

	if instance.current_status == QWEnums.QuestState.UNAVAILABLE:
		controller._pool_registry.move_instance_to_pool(instance, QWEnums.QuestState.AVAILABLE)
		var signal_id = controller._get_signal_id_for_instance(instance)
		controller.quest_became_available.emit(signal_id)
		controller.quest_data_changed.emit(signal_id)
		controller._send_instance_update(instance)
		var logger = controller._get_logger()
		if logger:
			logger.log("Flow", "Quest '%s' marked as AVAILABLE." % signal_id)


func _get_quest_ids_by_status(status: int) -> Array[StringName]:
	var list: Array[StringName] = []
	var controller = _get_controller()
	if not controller:
		return list

	var pool = controller._pool_registry.get_pool_for_state(status)
	for instance: QuestInstance in pool.get_all_instances():
		var q_id = controller._get_signal_id_for_instance(instance)
		list.append(q_id)
	return list


## Getter for Quest Boards (Pool-style API)
func get_available_quests() -> Array[StringName]:
	return _get_quest_ids_by_status(QWEnums.QuestState.AVAILABLE)


## Returns all quests currently ACTIVE.
func get_active_quests() -> Array[StringName]:
	return _get_quest_ids_by_status(QWEnums.QuestState.ACTIVE)


## Returns all quests that are COMPLETED (success).
func get_completed_quests() -> Array[StringName]:
	return _get_quest_ids_by_status(QWEnums.QuestState.COMPLETED)


## Returns all quests that are FAILED.
func get_failed_quests() -> Array[StringName]:
	return _get_quest_ids_by_status(QWEnums.QuestState.FAILED)


## Returns IDs of all custom pools (from additional_pool_scripts).
func get_all_custom_pool_ids() -> Array[StringName]:
	var controller = _get_controller()
	if not controller:
		return []
	return controller._pool_registry.get_all_pool_ids()


## Returns quest IDs (signal_id) in a custom pool.
func get_quests_in_pool(pool_id: StringName) -> Array[StringName]:
	var controller = _get_controller()
	if not controller:
		return []
	return controller._pool_registry.get_quests_in_pool(pool_id)


## Moves a quest instance to a custom pool. Quest must exist and pool_id must be registered.
func move_quest_to_custom_pool(quest_id: StringName, pool_id: StringName) -> void:
	var controller = _get_controller()
	if not controller:
		return
	if not controller._is_valid_quest_id(quest_id) or pool_id.is_empty():
		push_warning("[QuestPoolManager] move_quest_to_custom_pool: invalid quest_id or pool_id.")
		return
	if not controller._pool_registry.get_pool_by_id(pool_id):
		push_warning("[QuestPoolManager] move_quest_to_custom_pool: unknown pool '%s'." % pool_id)
		return
	if not controller._ensure_quest_loaded(quest_id):
		var logger = controller._get_logger()
		if logger:
			logger.warn("Flow", "move_quest_to_custom_pool: Could not load '%s'." % quest_id)
		return

	var file_id = controller._resolve_instance_file_id(quest_id)
	var instance = controller._get_or_create_instance(file_id, quest_id)
	controller._pool_registry.move_instance_to_custom_pool(instance, pool_id)
	var signal_id = controller._get_signal_id_for_instance(instance)
	controller.quest_data_changed.emit(signal_id)
	controller._send_instance_update(instance)
	var logger = controller._get_logger()
	if logger:
		logger.log("Flow", "Quest '%s' moved to custom pool '%s'." % [signal_id, pool_id])
