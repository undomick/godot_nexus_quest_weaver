@tool
class_name RemoveSwitchCaseCommand
extends EditorCommand

var _graph: QuestGraphResource
var _node_data: SwitchNodeResource
var _case_to_remove: SwitchCasePort
var _original_index: int = -1
var _removed_connections_data: Array[Dictionary] = []


func _init(p_graph: QuestGraphResource, p_node_data: SwitchNodeResource, p_index: int) -> void:
	_graph = p_graph
	_node_data = p_node_data
	if p_index >= 0 and p_index < p_node_data.cases.size():
		_case_to_remove = p_node_data.cases[p_index]
		_original_index = p_index


func execute() -> void:
	if _case_to_remove == null:
		return
	_removed_connections_data = _graph.connections.filter(
		func(c): return c.from_node == _node_data.id and c.from_port == _original_index
	)
	if not _removed_connections_data.is_empty():
		_graph.connections = _graph.connections.filter(
			func(c): return not (c.from_node == _node_data.id and c.from_port == _original_index)
		)
	for conn in _graph.connections:
		if conn.from_node == _node_data.id and conn.from_port > _original_index:
			conn.from_port -= 1
	_node_data.cases.erase(_case_to_remove)
	_node_data._update_ports_from_data()


func undo() -> void:
	if _case_to_remove == null or _original_index == -1:
		return
	_node_data.cases.insert(_original_index, _case_to_remove)
	for conn in _graph.connections:
		if conn.from_node == _node_data.id and conn.from_port >= _original_index:
			conn.from_port += 1
	_graph.connections.append_array(_removed_connections_data)
	_node_data._update_ports_from_data()
