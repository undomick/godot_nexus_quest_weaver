# res://addons/quest_weaver/nodes/action/task_node/task_node_executor.gd
class_name TaskNodeExecutor
extends NodeExecutor


func execute(context: ExecutionContext, node: GraphNodeResource, instance: QuestInstance) -> void:
	var task_node = node as TaskNodeResource
	if not is_instance_valid(task_node):
		return

	var controller = context.quest_controller
	var inventory_adapter = context.inventory_adapter
	var kill_adapter = context.kill_adapter
	var logger = context.logger

	if task_node.objectives.is_empty():
		if is_instance_valid(logger):
			logger.warn(
				"Executor",
				"TaskNode '%s' has no objectives. Completing immediately." % task_node.id
			)
		controller.complete_node(task_node)
		return

	if is_instance_valid(logger):
		logger.log(
			"Executor",
			(
				"TaskNode '%s': Activating %d objectives in instance '%s'."
				% [task_node.id, task_node.objectives.size(), instance.file_id]
			)
		)

	# 1. Register global listeners
	TaskNodeExecutor.register_listeners(context, task_node, instance)

	# 2. Initialize runtime state in the Instance
	for objective in task_node.objectives:
		if instance.get_objective_status(objective.id) == ObjectiveResource.Status.COMPLETED:
			continue

		instance.set_objective_status(objective.id, ObjectiveResource.Status.ACTIVE)

		# This enables "{item(0).amount}" to work specifically for this objective.
		var resolved_desc = instance.resolve_text(objective.description, objective)

		if resolved_desc != objective.description:
			instance.set_objective_description_override(objective.id, resolved_desc)

		# Snapshot logic for Item Collect (Track Progress Since Activation)
		if (
			objective.trigger_type == ObjectiveResource.TriggerType.ITEM_COLLECT
			and objective.track_progress_since_activation
			and is_instance_valid(inventory_adapter)
		):
			for item_id in objective.requirements:
				var current_amount = inventory_adapter.count_item(item_id)
				var snapshot_key = StringName("start_amount_%s_%s" % [objective.id, item_id])
				instance.set_node_data(task_node.id, snapshot_key, current_amount)
				if is_instance_valid(logger):
					logger.log(
						"Inventory",
						(
							"  - Snapshot for '%s' in '%s': %d"
							% [item_id, objective.id, current_amount]
						)
					)

		# Snapshot for KILL (Track Progress Since Activation) – from adapter if available, else 0
		if (
			objective.trigger_type == ObjectiveResource.TriggerType.KILL
			and objective.track_progress_since_activation
		):
			for enemy_id in objective.requirements:
				var current_count: int = 0
				if is_instance_valid(kill_adapter):
					current_count = kill_adapter.count_kill(enemy_id)
				else:
					current_count = instance.get_objective_progress_by_key(objective.id, enemy_id)
				var snapshot_key = StringName("start_amount_%s_%s" % [objective.id, enemy_id])
				instance.set_node_data(task_node.id, snapshot_key, current_count)
				if is_instance_valid(logger):
					logger.log(
						"Flow",
						(
							"  - Kill snapshot for '%s' in '%s': %d"
							% [enemy_id, objective.id, current_count]
						)
					)

	var signal_id = instance.quest_id if not instance.quest_id.is_empty() else instance.file_id
	controller.quest_data_changed.emit(signal_id)


# Updated Cleanup to handle multiple listeners per objective
func cleanup_listeners(context: ExecutionContext, node: TaskNodeResource):
	if not is_instance_valid(context):
		return

	for objective in node.objectives:
		if is_instance_valid(context.quest_controller):
			context.quest_controller._unregister_objective_instance(objective.id)
		match objective.trigger_type:
			ObjectiveResource.TriggerType.ITEM_COLLECT:
				for item_id in objective.requirements:
					_remove_listener_wrapper(
						context.item_objective_listeners, str(item_id), objective
					)

			ObjectiveResource.TriggerType.KILL:
				for enemy_id in objective.requirements:
					_remove_listener_wrapper(
						context.kill_objective_listeners, str(enemy_id), objective
					)

			ObjectiveResource.TriggerType.INTERACT:
				var t = objective.trigger_params.get("target_path")
				if t:
					_remove_listener_wrapper(
						context.interact_objective_listeners, str(t), objective
					)

			ObjectiveResource.TriggerType.LOCATION_ENTER:
				var l = objective.trigger_params.get("location_id")
				if l:
					_remove_listener_wrapper(
						context.location_objective_listeners, str(l), objective
					)


# --- STATIC HELPER FOR REGISTRATION ---


static func register_listeners(
	context: ExecutionContext, node: TaskNodeResource, instance: QuestInstance
):
	if not is_instance_valid(context):
		return

	for objective in node.objectives:
		if instance.get_objective_status(objective.id) == ObjectiveResource.Status.COMPLETED:
			continue
		if is_instance_valid(context.quest_controller):
			context.quest_controller._register_objective_instance(objective.id, instance.file_id)

		# Wrapper Base Data
		var wrapper = {
			"objective": objective,
			"file_id": instance.file_id,
			"task_node_id": node.id,
			"resolved_params": {}  # Will be filled if legacy
		}

		match objective.trigger_type:
			# CASE A: MULTI-TARGET (Requirements Dict)
			ObjectiveResource.TriggerType.ITEM_COLLECT:
				# complete_on_delivery: progress is only updated by GiveTakeItem, not ITEM_COLLECT
				if objective.complete_on_delivery:
					continue
				for item_id in objective.requirements:
					# Create a specific wrapper for this target to track it easily
					var target_wrapper = wrapper.duplicate()
					target_wrapper["target_key"] = item_id  # Store which item this listens to
					_add_listener_static(
						context.item_objective_listeners, str(item_id), target_wrapper
					)

			ObjectiveResource.TriggerType.KILL:
				for enemy_id in objective.requirements:
					var target_wrapper = wrapper.duplicate()
					target_wrapper["target_key"] = enemy_id
					_add_listener_static(
						context.kill_objective_listeners, str(enemy_id), target_wrapper
					)

			# CASE B: SINGLE TARGET (Legacy Params)
			ObjectiveResource.TriggerType.INTERACT:
				var target_path = instance.resolve_parameter(
					objective.trigger_params.get("target_path")
				)
				if target_path:
					wrapper.resolved_params = {"target_path": target_path}
					_add_listener_static(
						context.interact_objective_listeners, str(target_path), wrapper
					)

			ObjectiveResource.TriggerType.LOCATION_ENTER:
				var loc_id = instance.resolve_parameter(objective.trigger_params.get("location_id"))
				if loc_id:
					wrapper.resolved_params = {"location_id": loc_id}
					_add_listener_static(context.location_objective_listeners, str(loc_id), wrapper)


static func _add_listener_static(dict: Dictionary, key: String, wrapper: Dictionary):
	if not dict.has(key):
		dict[key] = []
	# Avoid duplicates based on file_id and objective reference
	for existing in dict[key]:
		if existing.file_id == wrapper.file_id and existing.objective == wrapper.objective:
			return
	dict[key].append(wrapper)


# --- INSTANCE HELPER FOR CLEANUP ---


func _remove_listener_wrapper(dict: Dictionary, key: String, objective: ObjectiveResource):
	if not dict.has(key):
		return
	var list = dict[key]
	for i in range(list.size() - 1, -1, -1):
		# Compare via resource reference
		if list[i].objective == objective:
			list.remove_at(i)
	if list.is_empty():
		dict.erase(key)
