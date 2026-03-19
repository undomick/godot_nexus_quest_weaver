@tool
class_name AddSwitchCaseCommand
extends EditorCommand

var _node_data: SwitchNodeResource
var _new_case: SwitchCasePort


func _init(p_node_data: SwitchNodeResource) -> void:
	_node_data = p_node_data


func execute() -> void:
	if _new_case == null:
		_new_case = SwitchCasePort.new()
		_new_case.value_string = str(_node_data.cases.size() + 1)
		_new_case.port_name = StringName("Case %s" % (char(65 + _node_data.cases.size())))
	_node_data.cases.append(_new_case)
	_node_data._update_ports_from_data()


func undo() -> void:
	_node_data.cases.erase(_new_case)
	_node_data._update_ports_from_data()
