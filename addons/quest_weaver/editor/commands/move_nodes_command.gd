# res://addons/quest_weaver/editor/commands/move_nodes_command.gd
@tool
class_name MoveNodesCommand
extends EditorCommand

var _graph: QuestGraphResource
var _graph_controller: QuestWeaverGraphController
var _start_positions: Dictionary
var _end_positions: Dictionary


func _init(
	p_graph: QuestGraphResource,
	p_graph_controller: QuestWeaverGraphController,
	p_start_positions: Dictionary,
	p_end_positions: Dictionary
):
	self._graph = p_graph
	self._graph_controller = p_graph_controller
	self._start_positions = p_start_positions
	self._end_positions = p_end_positions


func execute() -> void:
	for node_id in _end_positions:
		if _graph.nodes.has(node_id):
			var node_data = _graph.nodes[node_id]
			node_data.graph_position = _end_positions[node_id]
			_graph_controller.update_visual_node_position(_graph, node_id)


func undo() -> void:
	for node_id in _start_positions:
		if _graph.nodes.has(node_id):
			var node_data = _graph.nodes[node_id]
			node_data.graph_position = _start_positions[node_id]
			_graph_controller.update_visual_node_position(_graph, node_id)
