## Uses QuestController internals (_sync_manager) by design.
## Pattern-matching gate requires manager coordination; these APIs are not exposed publicly.
class_name SynchronizeNodeExecutor
extends NodeExecutor


func execute(context: ExecutionContext, node: GraphNodeResource, instance: QuestInstance) -> void:
	var sync_node = node as SynchronizeNodeResource
	if not is_instance_valid(sync_node):
		return

	var controller = context.quest_controller
	var entry_port = instance.get_node_data(node.id, "_entry_port", 0)
	controller._sync_manager.handle_input(sync_node, instance, entry_port)
