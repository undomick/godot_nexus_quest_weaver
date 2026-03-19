# res://addons/quest_weaver/editor/commands/add_sync_input_port_command.gd
@tool
class_name AddSyncInputPortCommand
extends EditorCommand

var _node_data: SynchronizeNodeResource
var _new_port_data: SynchronizeInputPort


func _init(p_node_data: SynchronizeNodeResource):
	self._node_data = p_node_data


func execute() -> void:
	if not is_instance_valid(_new_port_data):
		_new_port_data = SynchronizeInputPort.new()
		_new_port_data.port_name = "In %d" % (_node_data.inputs.size() + 1)

	_node_data.inputs.append(_new_port_data)

	for out in _node_data.outputs:
		out.patterns.append(0)  # 0 = IGNORE

	_node_data._update_ports_from_data()


func undo() -> void:
	_node_data.inputs.erase(_new_port_data)

	for out in _node_data.outputs:
		if not out.patterns.is_empty():
			out.patterns.pop_back()

	_node_data._update_ports_from_data()
