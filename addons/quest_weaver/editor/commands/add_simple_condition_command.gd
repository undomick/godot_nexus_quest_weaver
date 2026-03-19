# res://addons/quest_weaver/editor/commands/add_simple_condition_command.gd
@tool
class_name AddSimpleConditionCommand
extends EditorCommand

var _listener_node: EventListenerNodeResource
var _added_index: int = -1


func _init(p_listener_node: EventListenerNodeResource):
	self._listener_node = p_listener_node


func execute() -> void:
	var new_condition := {"key": "", "op": 0, "value": ""}
	_listener_node.simple_conditions.append(new_condition)
	_added_index = _listener_node.simple_conditions.size() - 1


func undo() -> void:
	if _added_index >= 0 and _added_index < _listener_node.simple_conditions.size():
		_listener_node.simple_conditions.remove_at(_added_index)
		_added_index = -1
