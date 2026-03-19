## Uses QuestController internals (_mark_node_as_logically_complete, jump_to_anchor) by design.
## Jump flow requires tight integration; these APIs are not exposed publicly.
class_name JumpNodeExecutor
extends NodeExecutor


func execute(context: ExecutionContext, node: GraphNodeResource, _instance: QuestInstance) -> void:
	var jump_node = node as JumpNodeResource
	if not is_instance_valid(jump_node):
		return

	var controller = context.quest_controller
	var logger = context.logger

	if jump_node.target_anchor_name.is_empty():
		if is_instance_valid(logger):
			logger.warn("Flow", "JumpNode '%s' has no target anchor name." % jump_node.id)
		# Terminate the node without jumping (Dead end)
		controller._mark_node_as_logically_complete(jump_node)
		return

	# Call the controller to handle the jump logic
	controller.jump_to_anchor(jump_node, jump_node.target_anchor_name)

	# Mark node as complete (does not fire any output ports since JumpNode has none)
	controller._mark_node_as_logically_complete(jump_node)
