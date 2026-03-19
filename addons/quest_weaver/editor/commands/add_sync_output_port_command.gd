# res://addons/quest_weaver/editor/commands/add_sync_output_port_command.gd
@tool
class_name AddSyncOutputPortCommand
extends EditorCommand

var _node_data: SynchronizeNodeResource
var _new_port_data: SynchronizeOutputPort


func _init(p_node_data: SynchronizeNodeResource):
	self._node_data = p_node_data


func execute() -> void:
	if not is_instance_valid(_new_port_data):
		_new_port_data = SynchronizeOutputPort.new()
		_new_port_data.port_name = "Out %d" % (_node_data.outputs.size() + 1)

		var input_count = _node_data.inputs.size()
		_new_port_data.patterns.resize(input_count)
		_new_port_data.patterns.fill(0)  # Fill with IGNORE

	_node_data.outputs.append(_new_port_data)
	_node_data._update_ports_from_data()


func undo() -> void:
	_node_data.outputs.erase(_new_port_data)
	_node_data._update_ports_from_data()
