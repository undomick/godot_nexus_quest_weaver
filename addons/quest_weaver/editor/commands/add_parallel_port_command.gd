# res://addons/quest_weaver/editor/commands/add_parallel_port_command.gd
@tool
class_name AddParallelPortCommand
extends EditorCommand

var _node_data: ParallelNodeResource
var _new_port_data: ParallelOutputPort


func _init(p_node_data: ParallelNodeResource):
	self._node_data = p_node_data


func execute() -> void:
	if not is_instance_valid(_new_port_data):
		_new_port_data = ParallelOutputPort.new()
		_new_port_data.port_name = "Out %d" % (_node_data.outputs.size() + 1)

	_node_data.outputs.append(_new_port_data)
	_node_data._update_ports_from_data()


func undo() -> void:
	_node_data.outputs.erase(_new_port_data)
	_node_data._update_ports_from_data()
