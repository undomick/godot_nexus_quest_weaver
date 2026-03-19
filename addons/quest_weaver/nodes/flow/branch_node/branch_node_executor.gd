## Uses QuestController internals (_trigger_next_nodes_from_port) by design.
## Branch output routing requires tight integration; these APIs are not exposed publicly.
class_name BranchNodeExecutor
extends NodeExecutor


func execute(context: ExecutionContext, node: GraphNodeResource, instance: QuestInstance) -> void:
	var branch_node = node as BranchNodeResource
	if not is_instance_valid(branch_node):
		context.quest_controller.complete_node(node)
		return

	# Pass instance to allow variable checking
	var result_is_true = branch_node.check_all_conditions(context, instance)

	var logger = context.logger
	if is_instance_valid(logger):
		logger.log("Flow", "  <- BranchNode '%s' result: %s" % [branch_node.id, result_is_true])

	# Manual completion because BranchNode has custom output logic
	# (0 = True, 1 = False)
	instance.set_node_active(branch_node.id, false)

	var port_to_trigger = 0 if result_is_true else 1
	context.quest_controller._trigger_next_nodes_from_port(branch_node, port_to_trigger)
