# res://addons/quest_weaver/editor/commands/delete_nodes_command.gd
@tool
class_name DeleteNodesCommand
extends EditorCommand

var _editor: QuestWeaverEditor
var _graph: QuestGraphResource
var _node_ids: Array[StringName]

var _deleted_nodes_data: Array[GraphNodeResource]
var _deleted_connections_data: Array[Dictionary]


func _init(p_editor: QuestWeaverEditor, p_graph: QuestGraphResource, p_node_ids: Array[StringName]):
	self._editor = p_editor
	self._graph = p_graph
	self._node_ids = p_node_ids


func execute() -> void:
	_deleted_nodes_data = []
	for node_id_sname in _node_ids:
		var node_id = String(node_id_sname)
		if _graph.nodes.has(node_id):
			_deleted_nodes_data.append(_graph.nodes[node_id].duplicate(true))

	var deleted_ids_str = _node_ids.map(func(id): return String(id))
	_deleted_connections_data = _graph.connections.filter(
		func(c): return deleted_ids_str.has(c.from_node) or deleted_ids_str.has(c.to_node)
	)

	for node_data in _deleted_nodes_data:
		_graph.remove_node(node_data.id)


func undo() -> void:
	for node_data in _deleted_nodes_data:
		_graph.add_node(node_data)

	for conn in _deleted_connections_data:
		_graph.add_connection(conn.from_node, conn.from_port, conn.to_node, conn.to_port)
