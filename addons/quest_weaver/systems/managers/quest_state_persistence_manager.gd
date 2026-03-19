# res://addons/quest_weaver/systems/managers/quest_state_persistence_manager.gd
class_name QuestStatePersistenceManager
extends RefCounted

const SAVE_VERSION = "1.5"


func save_state(controller: QuestController) -> Dictionary:
	var instances_data: Array[Dictionary] = []
	var pool_state = controller._pool_registry.pool_state_as_dict()

	for instance: QuestInstance in controller._pool_registry.get_all_instances():
		if is_instance_valid(instance):
			var inst_data = instance.get_save_data()
			# v1.5: status is derived from pool_state, but keep for migration compatibility
			instances_data.append(inst_data)

	return {"version": SAVE_VERSION, "pool_state": pool_state, "instances": instances_data}


## Loads quest state from saved data. Returns true on success, false if data format is invalid.
func load_state(controller: QuestController, data: Dictionary) -> bool:
	var logger = controller._get_logger()
	if logger:
		logger.log("SaveLoad", "Loading quest state...")

	controller.reset_all_graphs_and_quests()

	var version = data.get("version", "1.0")
	var instances_data = data.get("instances", [])
	if not instances_data is Array:
		if logger:
			logger.warn("SaveLoad", "Invalid save data: 'instances' is not an Array. Load aborted.")
		return false

	var pool_state: Dictionary = data.get("pool_state", {})

	# Build reverse map: file_id -> pool info (O(1) lookup per instance)
	var file_id_to_pool: Dictionary = {}
	if not pool_state.is_empty():
		for pool_name in pool_state.keys():
			var ids = pool_state.get(pool_name, [])
			var target_state := QWEnums.QuestState.UNAVAILABLE
			var custom_pool_id: StringName = &""
			var is_custom: bool = (
				pool_name not in ["unavailable", "available", "active", "completed", "failed"]
			)

			if not is_custom:
				target_state = _pool_name_to_state(str(pool_name))
			else:
				custom_pool_id = StringName(str(pool_name))

			for id_val in ids:
				var fid: StringName = StringName(str(id_val))
				file_id_to_pool[fid] = {
					"target_state": target_state,
					"custom_pool_id": custom_pool_id,
					"is_custom": is_custom
				}

	for inst_data in instances_data:
		var instance = QuestInstance.new(&"")
		instance.load_save_data(inst_data)

		# Validation 1: Check if the Quest File still exists (O(1) via id map)
		if not controller._id_to_context_node_map.has(instance.file_id):
			if logger:
				logger.warn(
					"SaveLoad",
					"Loaded quest '%s' but no definition found. Skipping." % instance.file_id
				)
			continue

		# Validation 2: Check if the Nodes inside still exist (Update protection)
		_sanitize_instance_data(controller, instance)

		# Determine target pool: from pool_state (v1.5) or from instance.status (migration)
		var target_state: int = QWEnums.QuestState.UNAVAILABLE
		var custom_pool_id: StringName = &""
		var found_pool: bool = false

		var pool_info = file_id_to_pool.get(instance.file_id)
		if pool_info:
			found_pool = true
			if pool_info.is_custom:
				custom_pool_id = pool_info.custom_pool_id
			else:
				target_state = pool_info.target_state
		elif pool_state.is_empty():
			target_state = instance.current_status
			if (
				instance.current_status == QWEnums.QuestState.CUSTOM
				and not instance.custom_pool_id.is_empty()
			):
				custom_pool_id = instance.custom_pool_id
				found_pool = true
			else:
				found_pool = true

		if (
			not custom_pool_id.is_empty()
			and controller._pool_registry.get_pool_by_id(custom_pool_id)
		):
			controller._pool_registry.add_instance_to_custom_pool(instance, custom_pool_id)
		else:
			if not found_pool:
				target_state = instance.current_status
				if target_state == QWEnums.QuestState.CUSTOM:
					target_state = QWEnums.QuestState.UNAVAILABLE
			controller._pool_registry.add_instance_to_pool(instance, target_state)

	var all_instances = controller._pool_registry.get_all_instances()

	# Restore Runtime Hooks
	if is_instance_valid(controller._timer_manager):
		var instances_dict: Dictionary = {}
		for inst in all_instances:
			instances_dict[inst.file_id] = inst
		controller._timer_manager.restore_timers_from_instances(instances_dict)

	_restore_event_listeners(controller, all_instances)

	# Notify UI
	for inst in all_instances:
		var signal_id = inst.quest_id if inst.quest_id != &"" else inst.file_id
		controller.quest_data_changed.emit(signal_id)

	if logger:
		logger.log("SaveLoad", "Load complete. %d quests restored." % all_instances.size())
	return true


func _pool_name_to_state(pool_name: String) -> int:
	match pool_name:
		"unavailable":
			return QWEnums.QuestState.UNAVAILABLE
		"available":
			return QWEnums.QuestState.AVAILABLE
		"active":
			return QWEnums.QuestState.ACTIVE
		"completed":
			return QWEnums.QuestState.COMPLETED
		"failed":
			return QWEnums.QuestState.FAILED
	return QWEnums.QuestState.UNAVAILABLE


func _restore_event_listeners(controller: QuestController, instances: Array = []) -> void:
	var event_manager = controller._event_manager
	if not is_instance_valid(event_manager):
		return

	event_manager.clear()

	var iter_instances: Array = (
		instances if not instances.is_empty() else controller._pool_registry.get_all_instances()
	)
	for instance: QuestInstance in iter_instances:
		for node_id in instance.active_node_ids:
			# Safety check: if node does not exist in definition, skip
			var node_def = controller._node_definitions.get(node_id)
			if not node_def:
				continue

			if node_def is EventListenerNodeResource:
				event_manager.register_listener(node_def)
			elif node_def is TaskNodeResource:
				if is_instance_valid(controller._execution_context):
					TaskNodeExecutor.register_listeners(
						controller._execution_context, node_def, instance
					)


# Removes stale nodes from save data to prevent crashes
func _sanitize_instance_data(controller: QuestController, instance: QuestInstance) -> void:
	var logger = controller._get_logger()

	var invalid_active = _collect_invalid_node_ids(controller, instance.active_node_ids)
	for invalid_id in invalid_active:
		instance.active_node_ids.erase(invalid_id)
		if logger:
			(
				logger
				. warn(
					"SaveLoad",
					(
						"Sanitized savegame: Node '%s' in quest '%s' no longer exists. Removed from active state."
						% [invalid_id, instance.file_id]
					)
				)
			)

	var invalid_states = _collect_invalid_node_ids(controller, instance.node_states)
	for invalid_id in invalid_states:
		instance.node_states.erase(invalid_id)


func _collect_invalid_node_ids(
	controller: QuestController, node_ids_dict: Dictionary
) -> Array[StringName]:
	var result: Array[StringName] = []
	for node_id in node_ids_dict.keys():
		if not controller._node_definitions.has(node_id):
			result.append(node_id)
	return result
