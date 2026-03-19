## Uses QuestController internals (_node_connections, _node_definitions, _activate_node) by design.
## Random path selection requires direct connection lookup; these APIs are not exposed publicly.
class_name RandomNodeExecutor
extends NodeExecutor


func execute(context: ExecutionContext, node: GraphNodeResource, instance: QuestInstance) -> void:
	var random_node = node as RandomNodeResource
	if not is_instance_valid(random_node):
		return

	instance.set_node_active(random_node.id, false)
	var controller = context.quest_controller

	if random_node.outputs.is_empty():
		return

	var total_weight = 0
	for port in random_node.outputs:
		total_weight += port.weight
	if total_weight <= 0:
		return

	var pick = randi_range(1, total_weight)
	var chosen_index = 0
	var current = 0
	for i in range(random_node.outputs.size()):
		current += random_node.outputs[i].weight
		if pick <= current:
			chosen_index = i
			break

	var connections = controller._node_connections.get(random_node.id, [])
	for connection in connections:
		if connection.from_port == chosen_index:
			var next_def = controller._node_definitions.get(connection.to_node)
			if next_def:
				controller._activate_node(next_def, connection.to_port)
