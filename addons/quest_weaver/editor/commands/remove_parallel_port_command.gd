# res://addons/quest_weaver/editor/commands/remove_parallel_port_command.gd
@tool
class_name RemoveParallelPortCommand
extends EditorCommand

var _graph: QuestGraphResource
var _node_data: ParallelNodeResource
var _port_to_remove: ParallelOutputPort
var _original_index: int = -1

var _removed_connections_data: Array[Dictionary] = []


func _init(p_graph: QuestGraphResource, p_node_data: ParallelNodeResource, p_index: int):
	self._graph = p_graph
	self._node_data = p_node_data

	if p_index >= 0 and p_index < p_node_data.outputs.size():
		self._port_to_remove = p_node_data.outputs[p_index]
		self._original_index = p_index


func execute() -> void:
	if not is_instance_valid(_port_to_remove):
		return

	_removed_connections_data = _graph.connections.filter(
		func(c): return c.from_node == _node_data.id and c.from_port == _original_index
	)
	_graph.connections = _graph.connections.filter(
		func(c): return not (c.from_node == _node_data.id and c.from_port == _original_index)
	)

	for conn in _graph.connections:
		if conn.from_node == _node_data.id and conn.from_port > _original_index:
			conn.from_port -= 1

	_node_data.outputs.erase(_port_to_remove)
	_node_data._update_ports_from_data()


func undo() -> void:
	if not is_instance_valid(_port_to_remove) or _original_index == -1:
		return

	_node_data.outputs.insert(_original_index, _port_to_remove)

	for conn in _graph.connections:
		if conn.from_node == _node_data.id and conn.from_port >= _original_index:
			conn.from_port += 1

	_graph.connections.append_array(_removed_connections_data)
	_node_data._update_ports_from_data()
