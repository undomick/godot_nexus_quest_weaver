# res://addons/quest_weaver/nodes/logic/cancel_scope_node/cancel_scope_node_executor.gd
class_name CancelScopeNodeExecutor
extends NodeExecutor

## Uses QuestController internals (_scope_manager, _cleanup_node_runtime, _mark_node_as_logically_complete).
## Cancels a scope by cleaning up all nodes without restarting.


func execute(context: ExecutionContext, node: GraphNodeResource, instance: QuestInstance) -> void:
	var cancel_node = node as CancelScopeNodeResource
	if not is_instance_valid(cancel_node):
		context.quest_controller.complete_node(node)
		return

	var controller = context.quest_controller
	var scope_manager = controller._scope_manager
	var target_scope_id = cancel_node.target_scope_id
	var logger = context.logger

	if target_scope_id.is_empty():
		push_warning("CancelScopeNode '%s' has no target_scope_id." % cancel_node.id)
		controller.complete_node(cancel_node)
		return

	var nodes_to_cleanup: Array[StringName] = scope_manager.get_nodes_for_scope_cleanup(
		target_scope_id
	)

	if nodes_to_cleanup.is_empty():
		if is_instance_valid(logger):
			logger.warn(
				"Flow", "CancelScopeNode: Scope '%s' is empty or invalid." % target_scope_id
			)
		controller.complete_node(cancel_node)
		return

	if is_instance_valid(logger):
		logger.log(
			"Flow", "Canceling scope '%s' (%d nodes)." % [target_scope_id, nodes_to_cleanup.size()]
		)

	for node_id in nodes_to_cleanup:
		if instance.is_node_active(node_id):
			controller._cleanup_node_runtime(node_id, instance)
		instance.clear_node_state(node_id)

	# Reset scope execution counter so the scope can be re-entered cleanly later
	var var_key = StringName("_scope_%s_executions" % target_scope_id)
	instance.set_variable(var_key, 0)

	controller.complete_node(cancel_node)
