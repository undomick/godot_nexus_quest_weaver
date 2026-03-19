class_name WaitNodeExecutor
extends NodeExecutor


func execute(context: ExecutionContext, node: GraphNodeResource, instance: QuestInstance) -> void:
	var wait_node = node as WaitNodeResource
	if not is_instance_valid(wait_node):
		return

	var controller = context.quest_controller
	var logger = context.logger

	if is_instance_valid(logger):
		logger.log(
			"Executor", "WaitNode '%s': Waiting %s s..." % [wait_node.id, wait_node.wait_duration]
		)

	await controller.get_tree().create_timer(wait_node.wait_duration).timeout

	# Check if node is still active in THIS instance (it might have been reset or skipped)
	if instance.is_node_active(wait_node.id):
		if is_instance_valid(logger):
			logger.log("Executor", "  - Wait finished.")
		controller.complete_node(wait_node)
