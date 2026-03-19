# res://addons/quest_weaver/editor/commands/reorder_condition_command.gd
@tool
class_name ReorderConditionCommand
extends EditorCommand

var _branch_node: BranchNodeResource
var _condition: ConditionResource
var _direction: int  # -1 for Up, 1 for Down


func _init(p_branch_node: BranchNodeResource, p_condition: ConditionResource, p_direction: int):
	self._branch_node = p_branch_node
	self._condition = p_condition
	self._direction = p_direction


func execute() -> void:
	_swap()


func undo() -> void:
	_swap()


func _swap() -> void:
	var current_index = _branch_node.conditions.find(_condition)
	if current_index == -1:
		return

	var new_index = current_index + _direction

	# Bounds check
	if new_index >= 0 and new_index < _branch_node.conditions.size():
		var other_cond = _branch_node.conditions[new_index]
		_branch_node.conditions[new_index] = _condition
		_branch_node.conditions[current_index] = other_cond
