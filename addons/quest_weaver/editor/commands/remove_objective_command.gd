# res://addons/quest_weaver/editor/commands/remove_objective_command.gd
@tool
class_name RemoveObjectiveCommand
extends EditorCommand

var _task_node: TaskNodeResource
var _objective_to_remove: ObjectiveResource

# These store the state for the undo operation.
var _original_index: int = -1


func _init(p_task_node: TaskNodeResource, p_objective_to_remove: ObjectiveResource):
	self._task_node = p_task_node
	self._objective_to_remove = p_objective_to_remove


func execute() -> void:
	# Store the state *before* performing the action.
	self._original_index = _task_node.objectives.find(_objective_to_remove)

	if _original_index != -1:
		_task_node.objectives.erase(_objective_to_remove)


func undo() -> void:
	# Restore the state using the stored information.
	if _original_index != -1:
		_task_node.objectives.insert(_original_index, _objective_to_remove)
