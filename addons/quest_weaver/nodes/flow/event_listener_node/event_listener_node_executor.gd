## Uses QuestController internals (_event_manager, _trigger_next_nodes_from_port) by design.
## Event listener registration and cancel flow require tight integration; these APIs are not exposed publicly.
class_name EventListenerNodeExecutor
extends NodeExecutor


func execute(context: ExecutionContext, node: GraphNodeResource, instance: QuestInstance) -> void:
	var listener_node = node as EventListenerNodeResource
	if not is_instance_valid(listener_node):
		return

	var controller = context.quest_controller

	# Read entry port from instance meta (set by Controller)
	var activated_on_port = instance.get_node_data(node.id, "_entry_port", 0)

	if activated_on_port == 0:
		# Register listener with Manager. Manager needs to know InstanceID to callback correctly?
		# Currently EventManager stores node_id. Controller resolves instance from node_id.
		# So this works without change in signature here, but Manager needs update later.
		controller._event_manager.register_listener(listener_node)

	elif activated_on_port == 1:
		# Cancel
		controller._event_manager.unregister_listener(listener_node)
		controller._trigger_next_nodes_from_port(listener_node, 1)
		controller.complete_node(listener_node)
