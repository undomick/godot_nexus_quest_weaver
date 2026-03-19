# res://addons/quest_weaver/editor/commands/remove_simple_condition_command.gd
@tool
class_name RemoveSimpleConditionCommand
extends EditorCommand

var _listener_node: EventListenerNodeResource
var _index: int
var _removed_condition: Dictionary = {}


func _init(p_listener_node: EventListenerNodeResource, p_index: int):
	self._listener_node = p_listener_node
	self._index = p_index


func execute() -> void:
	if _index >= 0 and _index < _listener_node.simple_conditions.size():
		_removed_condition = _listener_node.simple_conditions[_index].duplicate()
		_listener_node.simple_conditions.remove_at(_index)


func undo() -> void:
	if not _removed_condition.is_empty():
		_listener_node.simple_conditions.insert(_index, _removed_condition)
		_removed_condition = {}
