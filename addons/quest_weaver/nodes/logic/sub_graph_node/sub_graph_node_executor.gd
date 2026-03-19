# res://addons/quest_weaver/nodes/logic/sub_graph_node/sub_graph_node_executor.gd
class_name SubGraphNodeExecutor
extends NodeExecutor


## Starts the configured sub-graph. If wait_for_completion, pushes to call stack and returns when sub-graph finishes.
## Otherwise completes immediately and runs sub-graph in parallel.
func execute(context: ExecutionContext, node: GraphNodeResource, _instance: QuestInstance) -> void:
	var subgraph_node = node as SubGraphNodeResource
	if not is_instance_valid(subgraph_node):
		push_error("SubGraphNodeExecutor expects a SubGraphNodeResource.")
		context.quest_controller.complete_node(node)
		return

	var controller = context.quest_controller
	var graph_path = subgraph_node.quest_graph_path

	if graph_path.is_empty() or not ResourceLoader.exists(graph_path):
		push_error("SubGraphNode: Invalid path '%s'" % graph_path)
		controller.complete_node(subgraph_node)
		return

	if subgraph_node.wait_for_completion:
		# Pushing to call stack allows the controller to return here later
		controller.push_to_call_stack(subgraph_node.id)

	controller.start_sub_graph(graph_path)

	# If NOT waiting, we complete immediately and the sub-graph runs in parallel/detached
	if not subgraph_node.wait_for_completion:
		controller.complete_node(subgraph_node)
