# res://addons/quest_weaver/nodes/logic/reset_progress_node/reset_progress_node_executor.gd
class_name ResetProgressNodeExecutor
extends NodeExecutor

## Uses QuestController internals (_scope_manager, _node_definitions, _cleanup_node_runtime,
## _mark_node_as_logically_complete, _activate_node) by design. Scope reset requires tight integration.


func execute(context: ExecutionContext, node: GraphNodeResource, instance: QuestInstance) -> void:
	var reset_node = node as ResetProgressNodeResource
	if not is_instance_valid(reset_node):
		return

	var controller = context.quest_controller
	var scope_manager = controller._scope_manager
	var target_scope_id = reset_node.target_scope_id
	var logger = context.logger

	if target_scope_id.is_empty():
		push_warning("ResetProgressNode '%s' has no target_scope_id." % reset_node.id)
		controller.complete_node(reset_node)
		return

	# Ask Manager to find nodes in this scope.
	# The manager also resets the 'max execution' counter variable in the instance if restart is requested.
	var nodes_to_reset_ids: Array[String] = scope_manager.handle_reset_scope(reset_node, instance)

	if nodes_to_reset_ids.is_empty():
		if is_instance_valid(logger):
			logger.warn(
				"Flow", "ResetProgressNode: Scope '%s' is empty or invalid." % target_scope_id
			)
		controller.complete_node(reset_node)
		return

	if is_instance_valid(logger):
		logger.log(
			"Flow",
			"Resetting %d nodes in scope '%s'." % [nodes_to_reset_ids.size(), target_scope_id]
		)

	for node_id in nodes_to_reset_ids:
		# 1. Clean up runtime hooks via Controller Helper (Stop Timers, Unregister Listeners)
		# This ensures we don't have lingering logic running when we restart the nodes.
		if instance.is_node_active(node_id):
			controller._cleanup_node_runtime(node_id, instance)

		# 2. Clear internal node state in instance (e.g. Timer ticks, specific inputs)
		instance.clear_node_state(node_id)

	if reset_node.restart_scope_on_completion:
		var start_node_id = scope_manager.get_start_node_id_for_scope(target_scope_id)
		var start_node_def = controller._node_definitions.get(start_node_id)

		# Mark ResetNode complete logic-wise, but do NOT trigger the "On Reset" output port
		# because we are jumping flow back to the start of the scope.
		controller._mark_node_as_logically_complete(reset_node)

		if is_instance_valid(start_node_def):
			controller._activate_node(start_node_def)
		else:
			push_error(
				(
					"ResetProgressNode: Could not find StartScopeNode for scope '%s' to restart."
					% target_scope_id
				)
			)
	else:
		# Flow continues normally after this node via the "On Reset" port
		controller.complete_node(reset_node)
