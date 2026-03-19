## When [param keep_listening] is false, completes after first match. When true, resets and reacts to each new round.
class_name AllCompleteNodeExecutor

extends NodeExecutor

# res://addons/quest_weaver/nodes/flow/all_complete_node/all_complete_node_executor.gd
## Continues only when all inputs have been received. Tracks which ports fired per instance.


func execute(context: ExecutionContext, node: GraphNodeResource, instance: QuestInstance) -> void:
	var all_node = node as AllCompleteNodeResource
	if not is_instance_valid(all_node):
		context.quest_controller.complete_node(node)
		return

	var controller = context.quest_controller
	var entry_port: int = instance.get_node_data(all_node.id, &"_entry_port", 0)

	var received_ports: Array = instance.get_node_data(all_node.id, &"_all_complete_received", [])
	if received_ports is Array:
		if not received_ports.has(entry_port):
			received_ports.append(entry_port)
	else:
		received_ports = [entry_port]

	instance.set_node_data(all_node.id, &"_all_complete_received", received_ports)

	var required_count = max(1, all_node.input_count)
	if received_ports.size() >= required_count:
		controller._trigger_next_nodes_from_port(all_node, 0)
		if all_node.keep_listening:
			instance.set_node_data(all_node.id, &"_all_complete_received", [])
		else:
			controller._mark_node_as_logically_complete(all_node)
