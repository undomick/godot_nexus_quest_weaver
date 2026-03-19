# res://addons/quest_weaver/nodes/logic/objective_node/objective_node_executor.gd
class_name ObjectiveNodeExecutor
extends NodeExecutor


## Applies the configured objective action (Complete/Fail/Reset) to the target manual objective.
## Affects objectives globally across all active quest instances. Always completes the current node.
func execute(context: ExecutionContext, node: GraphNodeResource, _instance: QuestInstance) -> void:
	var obj_node = node as ObjectiveNodeResource
	var logger = context.logger

	if not is_instance_valid(obj_node) or obj_node.target_objective_id.is_empty():
		if is_instance_valid(logger):
			logger.warn("Executor", "ObjectiveNode '%s' has no target ID." % node.id)
		context.quest_controller.complete_node(node)
		return

	var target_status = ObjectiveResource.Status.COMPLETED

	match obj_node.action:
		ObjectiveNodeResource.Action.COMPLETE:
			target_status = ObjectiveResource.Status.COMPLETED
		ObjectiveNodeResource.Action.FAIL:
			target_status = ObjectiveResource.Status.FAILED
		ObjectiveNodeResource.Action.RESET:
			target_status = ObjectiveResource.Status.ACTIVE

	# This affects objectives globally (in any active quest instance)
	context.quest_controller.get_objective_manager().set_manual_objective_status(
		obj_node.target_objective_id, target_status
	)

	context.quest_controller.complete_node(node)
