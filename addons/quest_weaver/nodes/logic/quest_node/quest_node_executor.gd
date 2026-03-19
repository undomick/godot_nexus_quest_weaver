# res://addons/quest_weaver/nodes/logic/quest_node/quest_node_executor.gd
class_name QuestNodeExecutor
extends NodeExecutor


## Applies the configured quest action (Complete/Fail/Start/Mark Available/Move to Custom Pool) to the target quest.
## Always completes the current node to advance the graph.
func execute(context: ExecutionContext, node: GraphNodeResource, _instance: QuestInstance) -> void:
	var quest_node = node as QuestNodeResource
	if not is_instance_valid(quest_node):
		push_error("Executor expects a QuestNodeResource.")
		context.quest_controller.complete_node(node)
		return

	if quest_node.action == QuestNodeResource.QuestAction.MOVE_TO_CUSTOM_POOL:
		context.quest_controller.get_quest_pool_manager().move_quest_to_custom_pool(
			quest_node.target_quest_id, quest_node.custom_pool_id
		)
	else:
		context.quest_controller.set_quest_status(quest_node.target_quest_id, quest_node.action)

	context.quest_controller.complete_node(node)
