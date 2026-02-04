# res://addons/quest_weaver/nodes/flow/synchronize_node/synchronize_node_executor.gd
class_name SynchronizeNodeExecutor
extends NodeExecutor

func execute(context: ExecutionContext, node: GraphNodeResource, instance: QuestInstance) -> void:
	var sync_node = node as SynchronizeNodeResource
	if not is_instance_valid(sync_node): return
	
	var controller = context.quest_controller
	var entry_port = instance.get_node_data(node.id, "_entry_port", 0)
	controller._sync_manager.handle_input(sync_node, instance, entry_port)
