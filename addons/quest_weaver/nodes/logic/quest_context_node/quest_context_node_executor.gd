# res://addons/quest_weaver/nodes/logic/quest_context_node/quest_context_node_executor.gd
class_name QuestContextNodeExecutor
extends NodeExecutor


## Starts the quest via QuestController and completes the node to continue the flow.
func execute(context: ExecutionContext, node: GraphNodeResource, _instance: QuestInstance) -> void:
	var context_node = node as QuestContextNodeResource
	if not is_instance_valid(context_node):
		context.quest_controller.complete_node(node)
		return

	context.quest_controller.start_quest(context_node)

	# After updating the state, we continue the flow.
	context.quest_controller.complete_node(node)
