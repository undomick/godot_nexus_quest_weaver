## Uses QuestController internals (_node_connections, _node_definitions, _activate_node) by design.
## Parallel branching requires direct connection lookup; these APIs are not exposed publicly.
## When [param keep_listening] is false, fires only once and ignores subsequent activations.
class_name ParallelNodeExecutor
extends NodeExecutor


func execute(context: ExecutionContext, node: GraphNodeResource, instance: QuestInstance) -> void:
	var parallel_node = node as ParallelNodeResource
	if not is_instance_valid(parallel_node):
		return

	if not parallel_node.keep_listening:
		var has_fired: bool = instance.get_node_data(parallel_node.id, &"_parallel_fired", false)
		if has_fired:
			instance.set_node_active(parallel_node.id, false)
			return
		instance.set_node_data(parallel_node.id, &"_parallel_fired", true)

	instance.set_node_active(parallel_node.id, false)

	var controller = context.quest_controller
	var connections = controller._node_connections.get(parallel_node.id, [])

	for i in range(parallel_node.outputs.size()):
		var output_info: ParallelOutputPort = parallel_node.outputs[i]
		var should_fire = true

		if is_instance_valid(output_info.condition):
			should_fire = output_info.condition.check(context, instance)

		if should_fire:
			for connection in connections:
				if connection.from_port == i:
					var next_node_def = controller._node_definitions.get(connection.to_node)
					if next_node_def:
						controller._activate_node(next_node_def, connection.to_port)
