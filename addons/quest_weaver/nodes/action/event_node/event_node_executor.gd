class_name EventNodeExecutor
extends NodeExecutor


func execute(context: ExecutionContext, node: GraphNodeResource, _instance: QuestInstance) -> void:
	var event_node = node as EventNodeResource
	if not is_instance_valid(event_node):
		return

	var payload = event_node.get_runtime_payload()
	# Optional: Resolve variable placeholders in payload strings using instance.resolve_text()

	if not event_node.event_name.is_empty():
		var global_bus = context.services.get_tree().root.get_node_or_null("QuestWeaverGlobal")
		if is_instance_valid(global_bus):
			global_bus.quest_event_fired.emit(event_node.event_name, payload)

	context.quest_controller.complete_node(event_node)
