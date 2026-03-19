## _check_tasks_in_instance) by design. Item flow requires tight integration; these APIs are not exposed publicly.
class_name GiveTakeItemNodeExecutor

extends NodeExecutor

# res://addons/quest_weaver/nodes/action/give_take_item_node/give_take_item_node_executor.gd
## Uses QuestController internals (_trigger_next_nodes_from_port, _mark_node_as_logically_complete,


func execute(context: ExecutionContext, node: GraphNodeResource, instance: QuestInstance) -> void:
	var item_node = node as GiveTakeItemNodeResource
	if not is_instance_valid(item_node):
		context.quest_controller.complete_node(node)
		return

	# Ensure output_ports are in sync at runtime (handles any load/deserialization edge cases)
	if item_node.has_method("_update_ports_from_data"):
		item_node._update_ports_from_data()

	var logger = context.logger
	var controller = context.quest_controller
	var adapter = context.inventory_adapter
	var exit_port := -1

	if not is_instance_valid(adapter):
		if is_instance_valid(logger):
			logger.error("Inventory", "No inventory adapter configured. Activating 'Failure' path.")
		exit_port = 1

	elif item_node.action == item_node.Action.REWARD_FROM_QUEST:
		if item_node.target_quest_id.is_empty():
			if is_instance_valid(logger):
				logger.warn("Inventory", "Reward from quest: No Target Quest ID specified.")
			exit_port = 1
		else:
			var rewards: Dictionary = controller.get_quest_rewards(item_node.target_quest_id)
			for item_id in rewards:
				var amount: int = rewards[item_id]
				if amount > 0:
					adapter.give_item(item_id, amount)
					if is_instance_valid(logger):
						logger.log(
							"Inventory",
							(
								"  - Gave reward %d x %s (from quest '%s')"
								% [amount, item_id, item_node.target_quest_id]
							)
						)
			exit_port = 0

	elif item_node.action == item_node.Action.ITEMS_FROM_OBJECTIVE:
		if item_node.target_objective_id == &"":
			if is_instance_valid(logger):
				logger.warn("Inventory", "ItemsFromObjective has no Target Objective ID.")
			exit_port = 1
		else:
			var obj_res = controller.get_objective_manager().get_objective_resource(
				item_node.target_objective_id
			)
			if not obj_res or obj_res.requirements.is_empty():
				if is_instance_valid(logger):
					logger.warn(
						"Inventory",
						(
							"Target Objective '%s' not found or has no requirements."
							% item_node.target_objective_id
						)
					)
				exit_port = 1
			else:
				var dynamic_requirements = {}
				var is_already_done = true
				for item_key in obj_res.requirements:
					var target = obj_res.requirements[item_key]
					var current = instance.get_objective_progress_by_key(obj_res.id, item_key)
					var needed = max(0, target - current)
					if is_instance_valid(logger):
						logger.log(
							"Inventory",
							(
								"  - Snapshot for '%s' in '%s': current=%d target=%d needed=%d"
								% [item_key, obj_res.id, current, target, needed]
							)
						)
					if needed > 0:
						dynamic_requirements[item_key] = needed
						is_already_done = false

				if is_already_done:
					if is_instance_valid(logger):
						logger.log(
							"Inventory",
							"Objective '%s' already fulfilled. Taking nothing." % obj_res.id
						)
					if item_node.complete_objective_on_success:
						_complete_objective_if_requested(
							controller, instance, item_node.target_objective_id
						)
					exit_port = 0
				else:
					var result = _process_take_logic(
						adapter,
						dynamic_requirements,
						item_node.allow_partial_deposit,
						instance,
						obj_res.id,
						logger,
						controller
					)
					exit_port = _take_result_to_port(result, item_node)
					var port_name = (
						item_node.output_ports[exit_port]
						if exit_port < item_node.output_ports.size()
						else str(exit_port)
					)
					if is_instance_valid(logger):
						logger.log(
							"Inventory",
							(
								"GiveTakeItem '%s' (objective '%s') -> %s (port %d)"
								% [
									item_node.id,
									item_node.target_objective_id,
									port_name,
									exit_port
								]
							)
						)
					if exit_port == 0 and item_node.complete_objective_on_success:
						_complete_objective_if_requested(
							controller, instance, item_node.target_objective_id
						)

	elif item_node.items.is_empty():
		if is_instance_valid(logger):
			logger.warn("Inventory", "Item list is empty. Nothing happened.")
		exit_port = 0

	elif item_node.action == item_node.Action.GIVE:
		for item_id in item_node.items:
			var amount = item_node.items[item_id]
			adapter.give_item(item_id, amount)
			if is_instance_valid(logger):
				logger.log("Inventory", "  - Gave %d x %s" % [amount, item_id])
		exit_port = 0

	elif item_node.action == item_node.Action.TAKE:
		var result = _process_take_logic(
			adapter,
			item_node.items,
			item_node.allow_partial_deposit,
			instance,
			&"",
			logger,
			controller
		)
		exit_port = _take_result_to_port(result, item_node)
		if is_instance_valid(logger):
			var port_name = (
				item_node.output_ports[exit_port]
				if exit_port < item_node.output_ports.size()
				else str(exit_port)
			)
			logger.log(
				"Inventory",
				"GiveTakeItem '%s' (TAKE) -> %s (port %d)" % [item_node.id, port_name, exit_port]
			)

	if exit_port >= 0:
		_finish_give_take(controller, item_node, exit_port)


func _finish_give_take(
	controller: QuestController, item_node: GiveTakeItemNodeResource, port: int
) -> void:
	controller._trigger_next_nodes_from_port(item_node, port)
	controller._mark_node_as_logically_complete(item_node)


# ==============================================================================
# HELPER: TAKE LOGIC (Atomic & Partial)
# ==============================================================================

# Returns: 0 = full success, 1 = partial (some taken), 2 = failure (nothing taken)


func _process_take_logic(
	adapter: QuestInventoryAdapterBase,
	requirements: Dictionary,
	partial: bool,
	instance: QuestInstance,
	update_obj_id: StringName,
	logger: QWLogger,
	controller: QuestController
) -> int:
	# 1. ATOMIC CHECK (If NOT partial)
	if not partial:
		for item_id in requirements:
			if not adapter.check_item(item_id, requirements[item_id]):
				if is_instance_valid(logger):
					logger.log("Inventory", "  - Atomic check failed. Missing: %s" % item_id)
				return 2  # FAILURE

	var something_taken = false
	var all_requirements_met = true
	var updates_made = false

	# 2. EXECUTION
	for item_id in requirements:
		var needed = requirements[item_id]
		var have = adapter.count_item(item_id)

		var to_take = 0
		if partial:
			to_take = min(needed, have)
		else:
			to_take = needed

		# Requirement not fully met (including when we took nothing of this item)
		if to_take < needed:
			all_requirements_met = false

		if to_take > 0:
			adapter.take_item(item_id, to_take)
			something_taken = true

			if is_instance_valid(logger):
				logger.log("Inventory", "  - Taken %d x %s" % [to_take, item_id])

			# Auto-Update Objective Logic
			if update_obj_id != &"":
				var old_prog = instance.get_objective_progress_by_key(update_obj_id, item_id)
				instance.set_objective_progress_by_key(update_obj_id, item_id, old_prog + to_take)
				updates_made = true

	# 3. NOTIFY CHANGES
	if updates_made:
		var signal_id = instance.quest_id if instance.quest_id != &"" else instance.file_id

		if is_instance_valid(controller):
			controller.quest_data_changed.emit(signal_id)

	# 4. RESULT: 0=success, 1=partial, 2=failure
	if not something_taken:
		return 2  # FAILURE
	# Success only when objective is fully met (all targets reached). Otherwise Partial.
	if update_obj_id != &"":
		var objective_def = (
			controller.get_objective_manager().get_objective_resource(update_obj_id)
			if is_instance_valid(controller)
			else null
		)
		if is_instance_valid(objective_def):
			var all_met = true
			for req_key in objective_def.requirements:
				var target = objective_def.requirements[req_key]
				var progress = instance.get_objective_progress_by_key(update_obj_id, req_key)
				if progress < target:
					all_met = false
					break
			if partial and not all_met:
				return 1  # PARTIAL
			if all_met:
				return 0  # SUCCESS
			return 1  # PARTIAL (partial deposit, objective not full)
	if partial and not all_requirements_met:
		return 1  # PARTIAL
	return 0  # SUCCESS


func _complete_objective_if_requested(
	controller: QuestController, instance: QuestInstance, objective_id: StringName
) -> void:
	if objective_id == &"":
		return
	instance.set_objective_status(objective_id, ObjectiveResource.Status.COMPLETED)
	var signal_id = instance.quest_id if instance.quest_id != &"" else instance.file_id
	controller.quest_data_changed.emit(signal_id)
	var global_bus = controller.get_tree().root.get_node_or_null("QuestWeaverGlobal")
	if is_instance_valid(global_bus):
		global_bus.quest_objective_state_changed.emit(
			signal_id, objective_id, ObjectiveResource.Status.COMPLETED
		)
	controller._check_tasks_in_instance(instance)


## Maps result (0=success, 1=partial, 2=failure) to output port index.
## Uses output_ports.size() as source of truth - more robust than allow_partial_deposit
## in case of deserialization/editor sync issues.
func _take_result_to_port(result: int, item_node: GiveTakeItemNodeResource) -> int:
	var has_partial_port = item_node.output_ports.size() == 3
	if has_partial_port:
		return result  # 0=Success, 1=Partial, 2=Failure
	# Two ports: map partial to success
	return 0 if result <= 1 else 1
