# res://addons/quest_weaver/editor/commands/remove_sync_input_port_command.gd
@tool
class_name RemoveSyncInputPortCommand
extends EditorCommand

var _graph: QuestGraphResource
var _node_data: SynchronizeNodeResource
var _port_to_remove: SynchronizeInputPort
var _original_index: int = -1

# Stores connection data for undo
var _removed_connections_data: Array[Dictionary] = []

# Stores the pattern column data for undo { output_index: state_int }
var _removed_patterns_column: Dictionary = {}


func _init(p_graph: QuestGraphResource, p_node_data: SynchronizeNodeResource, p_index: int):
	self._graph = p_graph
	self._node_data = p_node_data

	if p_index >= 0 and p_index < p_node_data.inputs.size():
		self._port_to_remove = p_node_data.inputs[p_index]
		self._original_index = p_index


func execute() -> void:
	if not is_instance_valid(_port_to_remove):
		return

	# 1. Handle Connections (Standard)
	_removed_connections_data = _graph.connections.filter(
		func(c): return c.to_node == _node_data.id and c.to_port == _original_index
	)
	if not _removed_connections_data.is_empty():
		_graph.connections = _graph.connections.filter(
			func(c): return not (c.to_node == _node_data.id and c.to_port == _original_index)
		)

	for conn in _graph.connections:
		if conn.to_node == _node_data.id and conn.to_port > _original_index:
			conn.to_port -= 1

	# 2. Remove Port
	_node_data.inputs.erase(_port_to_remove)

	# 3. Remove Pattern Column & Store for Undo
	_removed_patterns_column.clear()
	for i in range(_node_data.outputs.size()):
		var out = _node_data.outputs[i]
		if _original_index < out.patterns.size():
			# Save state
			_removed_patterns_column[i] = out.patterns[_original_index]
			# Remove
			out.patterns.remove_at(_original_index)

	_node_data._update_ports_from_data()


func undo() -> void:
	if not is_instance_valid(_port_to_remove) or _original_index == -1:
		return

	# 1. Restore Port
	_node_data.inputs.insert(_original_index, _port_to_remove)

	# 2. Restore Pattern Column
	for i in range(_node_data.outputs.size()):
		var out = _node_data.outputs[i]
		var restored_state = _removed_patterns_column.get(i, 0)  # Default IGNORE

		if _original_index <= out.patterns.size():
			out.patterns.insert(_original_index, restored_state)
		else:
			out.patterns.append(restored_state)

	# 3. Restore Connections
	for conn in _graph.connections:
		if conn.to_node == _node_data.id and conn.to_port >= _original_index:
			conn.to_port += 1

	_graph.connections.append_array(_removed_connections_data)
	_node_data._update_ports_from_data()
