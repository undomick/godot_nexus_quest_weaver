# res://addons/quest_weaver/editor/commands/remove_random_port_command.gd
@tool
class_name RemoveRandomPortCommand
extends EditorCommand

var _graph: QuestGraphResource
var _node_data: RandomNodeResource
var _port_to_remove: RandomOutputPort
var _original_index: int = -1

# Stores the connection data for the undo operation.
var _removed_connections_data: Array[Dictionary] = []


func _init(p_graph: QuestGraphResource, p_node_data: RandomNodeResource, p_index: int):
	self._graph = p_graph
	self._node_data = p_node_data

	if p_index >= 0 and p_index < p_node_data.outputs.size():
		self._port_to_remove = p_node_data.outputs[p_index]
		self._original_index = p_index


func execute() -> void:
	if not is_instance_valid(_port_to_remove):
		return

	# Step 1: Find, store, and remove connection DATA from the main graph.
	_removed_connections_data = _graph.connections.filter(
		func(c): return c.from_node == _node_data.id and c.from_port == _original_index
	)
	if not _removed_connections_data.is_empty():
		_graph.connections = _graph.connections.filter(
			func(c): return not (c.from_node == _node_data.id and c.from_port == _original_index)
		)

	# Step 2: Shift the port indices of any subsequent connections.
	for conn in _graph.connections:
		if conn.from_node == _node_data.id and conn.from_port > _original_index:
			conn.from_port -= 1

	# Step 3: Remove the port DATA from the node resource itself.
	_node_data.outputs.erase(_port_to_remove)
	_node_data._update_ports_from_data()


func undo() -> void:
	if not is_instance_valid(_port_to_remove) or _original_index == -1:
		return

	# Step 1: Re-insert the port DATA into the node resource.
	_node_data.outputs.insert(_original_index, _port_to_remove)

	# Step 2: Shift back the port indices of subsequent connections.
	for conn in _graph.connections:
		if conn.from_node == _node_data.id and conn.from_port >= _original_index:
			conn.from_port += 1

	# Step 3: Restore the connection DATA to the main graph.
	_graph.connections.append_array(_removed_connections_data)
	_node_data._update_ports_from_data()
