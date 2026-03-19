# res://addons/quest_weaver/editor/commands/paste_nodes_command.gd
@tool
class_name PasteNodesCommand
extends EditorCommand

var _editor: QuestWeaverEditor
var _graph: QuestGraphResource
var _graph_controller: QuestWeaverGraphController
var _pasted_nodes: Array[GraphNodeResource]
var _pasted_connections: Array[Dictionary]


func _init(
	p_editor: QuestWeaverEditor,
	p_graph: QuestGraphResource,
	p_graph_controller: QuestWeaverGraphController,
	p_paste_data: Dictionary
):
	self._editor = p_editor
	self._graph = p_graph
	self._graph_controller = p_graph_controller
	self._pasted_nodes = p_paste_data.get("nodes", [])
	self._pasted_connections = p_paste_data.get("connections", [])


func execute() -> void:
	for node_data in _pasted_nodes:
		_graph.add_node(node_data)
		_graph_controller.select_visual_node(node_data.id)

	for conn in _pasted_connections:
		_graph.add_connection(conn.from_node, conn.from_port, conn.to_node, conn.to_port)


func undo() -> void:
	for node_data in _pasted_nodes:
		_graph.remove_node(node_data.id)
