# res://addons/quest_weaver/editor/commands/reorder_objective_command.gd
@tool
class_name ReorderObjectiveCommand
extends EditorCommand

var _task_node: TaskNodeResource
var _objective: ObjectiveResource
var _direction: int  # -1 for Up, 1 for Down


func _init(p_task_node: TaskNodeResource, p_objective: ObjectiveResource, p_direction: int):
	self._task_node = p_task_node
	self._objective = p_objective
	self._direction = p_direction


func execute() -> void:
	_swap()


func undo() -> void:
	# Swap back (inverse direction logic is implicit in swap)
	_swap()


func _swap() -> void:
	var current_index = _task_node.objectives.find(_objective)
	if current_index == -1:
		return

	var new_index = current_index + _direction

	# Bounds check
	if new_index >= 0 and new_index < _task_node.objectives.size():
		var other_obj = _task_node.objectives[new_index]
		_task_node.objectives[new_index] = _objective
		_task_node.objectives[current_index] = other_obj
