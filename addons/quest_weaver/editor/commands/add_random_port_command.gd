# res://addons/quest_weaver/editor/commands/add_random_port_command.gd
@tool
class_name AddRandomPortCommand
extends EditorCommand

var _node_data: RandomNodeResource
var _new_port_data: RandomOutputPort


func _init(p_node_data: RandomNodeResource):
	self._node_data = p_node_data


func execute() -> void:
	if not is_instance_valid(_new_port_data):
		_new_port_data = RandomOutputPort.new()
		_new_port_data.port_name = "Choice %d" % (_node_data.outputs.size() + 1)

	_node_data.outputs.append(_new_port_data)
	_node_data._update_ports_from_data()


func undo() -> void:
	_node_data.outputs.erase(_new_port_data)
	_node_data._update_ports_from_data()
