class_name QuestControllerDebug
extends RefCounted

## Helper for QuestController debug API. Holds implementation of debug methods
## to reduce quest_controller.gd size and public method count.

var _controller: QuestController


func _init(controller: QuestController) -> void:
	_controller = controller


func dump_quest_state(query_id: StringName) -> void:
	var file_id = _controller._resolve_instance_file_id(query_id)
	var instance = _controller._pool_registry.get_instance_by_file_id(file_id)
	if not instance:
		print("[QW Debug] Quest '%s' not found or inactive." % query_id)
		return
	var data = instance.get_save_data()
	print(JSON.stringify(data, "\t"))


func complete_active_tasks(query_id: StringName) -> void:
	var file_id = _controller._resolve_instance_file_id(query_id)
	var instance = _controller._pool_registry.get_instance_by_file_id(file_id)
	if not instance:
		return
	var modified = false

	for node_id in instance.active_node_ids:
		var node_def = _controller._node_definitions.get(node_id)
		if node_def is TaskNodeResource:
			for objective in node_def.objectives:
				if (
					instance.get_objective_status(objective.id)
					!= ObjectiveResource.Status.COMPLETED
				):
					instance.set_objective_status(objective.id, ObjectiveResource.Status.COMPLETED)
					print(
						(
							"[QW Debug] Force completed objective '%s' in quest '%s'"
							% [objective.id, query_id]
						)
					)
					modified = true

	if modified:
		var signal_id = _controller._get_signal_id_for_instance(instance)
		_controller.quest_data_changed.emit(signal_id)
		_controller._check_tasks_in_instance(instance)


func set_variable(query_id: StringName, key: StringName, value: Variant) -> void:
	var file_id = _controller._resolve_instance_file_id(query_id)
	var instance = _controller._pool_registry.get_instance_by_file_id(file_id)
	if instance:
		instance.set_variable(key, value)
		print("[QW Debug] Set variable '%s' = %s in quest '%s'" % [key, value, query_id])


func list_quests() -> void:
	print("[QW Debug] --- Registered Quests ---")
	if _controller._registry_map.is_empty():
		print("  (none - registry not loaded or empty)")
		return
	for quest_id in _controller._registry_map:
		var path: String = _controller._registry_map[quest_id]
		var file_id = _controller._resolve_instance_file_id(quest_id)
		var instance = _controller._pool_registry.get_instance_by_file_id(file_id)
		var status_str := "not loaded"
		if instance:
			status_str = (
				QWEnums.QuestState.keys()[instance.current_status]
				if (
					instance.current_status >= 0
					and instance.current_status < QWEnums.QuestState.size()
				)
				else str(instance.current_status)
			)
		print("  %s -> %s [%s]" % [quest_id, path, status_str])


func list_active_instances() -> void:
	print("[QW Debug] --- Active Instances ---")
	var all_instances = _controller._pool_registry.get_all_instances()
	if all_instances.is_empty():
		print("  (none)")
		return
	for instance in all_instances:
		var file_id = instance.file_id
		var status_str = (
			QWEnums.QuestState.keys()[instance.current_status]
			if instance.current_status >= 0 and instance.current_status < QWEnums.QuestState.size()
			else str(instance.current_status)
		)
		var active_keys: Array = []
		for k in instance.active_node_ids:
			active_keys.append(str(k))
		print(
			(
				"  file_id=%s quest_id=%s status=%s active_nodes=%s"
				% [file_id, instance.quest_id, status_str, active_keys]
			)
		)
