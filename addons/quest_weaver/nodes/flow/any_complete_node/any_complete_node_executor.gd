## When [param keep_listening] is false, ignores subsequent inputs. When true, reacts to each new round of inputs.
class_name AnyCompleteNodeExecutor

extends NodeExecutor

# res://addons/quest_weaver/nodes/flow/any_complete_node/any_complete_node_executor.gd
## Continues as soon as the first input is received.


func execute(context: ExecutionContext, node: GraphNodeResource, instance: QuestInstance) -> void:
	var any_node = node as AnyCompleteNodeResource
	if not is_instance_valid(any_node):
		context.quest_controller.complete_node(node)
		return

	var controller = context.quest_controller
	var has_fired: bool = instance.get_node_data(any_node.id, &"_any_complete_fired", false)

	if not any_node.keep_listening and has_fired:
		controller._mark_node_as_logically_complete(any_node)
		return

	instance.set_node_data(any_node.id, &"_any_complete_fired", true)
	controller._trigger_next_nodes_from_port(any_node, 0)

	if any_node.keep_listening:
		instance.set_node_data(any_node.id, &"_any_complete_fired", false)
	else:
		controller._mark_node_as_logically_complete(any_node)
