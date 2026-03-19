class_name QuestObjectiveManager
extends RefCounted

## Manages objective queries and manual status updates.
## Holds get_active_objectives_for_quest, get_active_objective_markers, get_objective_status,
## set_manual_objective_status, get_objective_progress, get_objective_progress_by_key, get_objective_resource.
## Extracted from QuestController to reduce max-public-methods.

var _controller_weak: WeakRef


func _init(p_controller: QuestController) -> void:
	_controller_weak = weakref(p_controller)


func _get_controller() -> QuestController:
	return _controller_weak.get_ref() as QuestController


func get_active_objectives_for_quest(query_id: StringName) -> Array[ObjectiveResource]:
	var objectives: Array[ObjectiveResource] = []
	var controller = _get_controller()
	if not controller:
		return objectives

	var file_id = controller._resolve_instance_file_id(query_id)
	var instance = controller._pool_registry.get_instance_by_file_id(file_id)
	if not instance:
		return objectives

	for node_id in instance.active_node_ids:
		var node_def = controller._node_definitions.get(node_id)
		if node_def is TaskNodeResource:
			for bp_obj in node_def.objectives:
				var obj_status = instance.get_objective_status(bp_obj.id)
				var obj_progress = instance.get_objective_progress(bp_obj.id)
				if obj_status == ObjectiveResource.Status.ACTIVE:
					var ui_obj = bp_obj.duplicate()
					ui_obj.current_progress = obj_progress
					ui_obj.status = obj_status
					ui_obj.description = instance.get_objective_description(
						bp_obj.id, bp_obj.description
					)
					objectives.append(ui_obj)

	return objectives


## Returns active objective markers for map/minimap UI integration.
## Each marker is a Dictionary: {"type": "location"|"interact", "target": String, "quest_id": String, "objective_id": String, "description": String, "file_id": String}
func get_active_objective_markers() -> Array:
	var markers: Array = []
	var controller = _get_controller()
	if not controller or not is_instance_valid(controller._execution_context):
		return markers

	for target_key in controller._execution_context.location_objective_listeners:
		var wrappers = controller._execution_context.location_objective_listeners[target_key]
		for w in wrappers:
			var instance = controller._pool_registry.get_instance_by_file_id(w.file_id)
			if not instance:
				continue
			var obj: ObjectiveResource = w.objective
			if instance.get_objective_status(obj.id) != ObjectiveResource.Status.ACTIVE:
				continue
			var signal_id = controller._get_signal_id_for_instance(instance)
			markers.append(
				{
					"type": "location",
					"target": str(target_key),
					"quest_id": str(signal_id),
					"objective_id": str(obj.id),
					"description": instance.get_objective_description(obj.id, obj.description),
					"file_id": str(instance.file_id)
				}
			)

	for target_key in controller._execution_context.interact_objective_listeners:
		var wrappers = controller._execution_context.interact_objective_listeners[target_key]
		for w in wrappers:
			var instance = controller._pool_registry.get_instance_by_file_id(w.file_id)
			if not instance:
				continue
			var obj: ObjectiveResource = w.objective
			if instance.get_objective_status(obj.id) != ObjectiveResource.Status.ACTIVE:
				continue
			var signal_id = controller._get_signal_id_for_instance(instance)
			markers.append(
				{
					"type": "interact",
					"target": str(target_key),
					"quest_id": str(signal_id),
					"objective_id": str(obj.id),
					"description": instance.get_objective_description(obj.id, obj.description),
					"file_id": str(instance.file_id)
				}
			)

	return markers


func get_objective_status(p_objective_id: StringName) -> int:
	if p_objective_id.is_empty():
		return ObjectiveResource.Status.INACTIVE

	var controller = _get_controller()
	if not controller:
		return ObjectiveResource.Status.INACTIVE

	var file_id = controller._objective_id_to_file_id.get(p_objective_id, &"")
	if not file_id.is_empty() and controller._pool_registry.has_instance(file_id):
		var inst = controller._pool_registry.get_instance_by_file_id(file_id)
		var status = inst.get_objective_status(p_objective_id)
		if status != ObjectiveResource.Status.INACTIVE:
			return status
	for instance in controller._pool_registry.get_all_instances():
		var status = instance.get_objective_status(p_objective_id)
		if status != ObjectiveResource.Status.INACTIVE:
			return status
	return ObjectiveResource.Status.INACTIVE


func set_manual_objective_status(objective_id: StringName, new_status: int) -> void:
	var controller = _get_controller()
	if not controller:
		return

	var file_id = controller._objective_id_to_file_id.get(objective_id, &"")
	if not file_id.is_empty() and controller._pool_registry.has_instance(file_id):
		var instance = controller._pool_registry.get_instance_by_file_id(file_id)
		if instance.objective_states.has(objective_id):
			instance.set_objective_status(objective_id, new_status)
			var signal_id = controller._get_signal_id_for_instance(instance)
			var global_bus = controller._get_event_bus()
			if global_bus:
				global_bus.quest_objective_state_changed.emit(signal_id, objective_id, new_status)
			controller.quest_data_changed.emit(signal_id)
			controller._check_tasks_in_instance(instance)
			return
	for instance in controller._pool_registry.get_all_instances():
		if instance.objective_states.has(objective_id):
			instance.set_objective_status(objective_id, new_status)
			var signal_id = controller._get_signal_id_for_instance(instance)
			var global_bus = controller._get_event_bus()
			if global_bus:
				global_bus.quest_objective_state_changed.emit(signal_id, objective_id, new_status)
			controller.quest_data_changed.emit(signal_id)
			controller._check_tasks_in_instance(instance)
			return


func get_objective_progress(objective_id: StringName) -> int:
	if objective_id.is_empty():
		return 0

	var controller = _get_controller()
	if not controller:
		return 0

	var file_id = controller._objective_id_to_file_id.get(objective_id, &"")
	if not file_id.is_empty() and controller._pool_registry.has_instance(file_id):
		var instance: QuestInstance = controller._pool_registry.get_instance_by_file_id(file_id)
		if instance.objective_states.has(objective_id):
			return instance.get_objective_progress(objective_id)
	for instance: QuestInstance in controller._pool_registry.get_all_instances():
		if instance.objective_states.has(objective_id):
			return instance.get_objective_progress(objective_id)
	return 0


func get_objective_progress_by_key(objective_id: StringName, target_key: StringName) -> int:
	if objective_id.is_empty():
		return 0

	var controller = _get_controller()
	if not controller:
		return 0

	var file_id = controller._objective_id_to_file_id.get(objective_id, &"")
	if not file_id.is_empty() and controller._pool_registry.has_instance(file_id):
		var instance: QuestInstance = controller._pool_registry.get_instance_by_file_id(file_id)
		if instance.objective_states.has(objective_id):
			return instance.get_objective_progress_by_key(objective_id, target_key)
	for instance: QuestInstance in controller._pool_registry.get_all_instances():
		if instance.objective_states.has(objective_id):
			return instance.get_objective_progress_by_key(objective_id, target_key)
	return 0


func get_objective_resource(obj_id: StringName) -> ObjectiveResource:
	var controller = _get_controller()
	if not controller:
		return null
	if controller._objective_id_to_resource.has(obj_id):
		return controller._objective_id_to_resource[obj_id]
	return null
