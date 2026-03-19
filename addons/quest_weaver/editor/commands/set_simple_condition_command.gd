# res://addons/quest_weaver/editor/commands/set_simple_condition_command.gd
@tool
class_name SetSimpleConditionCommand
extends EditorCommand

var _listener_node: EventListenerNodeResource
var _index: int
var _new_data: Dictionary
var _old_data: Dictionary = {}


func _init(p_listener_node: EventListenerNodeResource, p_index: int, p_new_data: Dictionary):
	self._listener_node = p_listener_node
	self._index = p_index
	self._new_data = p_new_data.duplicate()


func execute() -> void:
	if _index >= 0 and _index < _listener_node.simple_conditions.size():
		_old_data = _listener_node.simple_conditions[_index].duplicate()
		_listener_node.simple_conditions[_index] = _new_data.duplicate()


func undo() -> void:
	if (
		not _old_data.is_empty()
		and _index >= 0
		and _index < _listener_node.simple_conditions.size()
	):
		_listener_node.simple_conditions[_index] = _old_data.duplicate()
