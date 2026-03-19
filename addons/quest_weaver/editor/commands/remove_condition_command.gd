# res://addons/quest_weaver/editor/commands/remove_condition_command.gd
@tool
class_name RemoveConditionCommand
extends EditorCommand

var _branch_node: BranchNodeResource
var _condition_to_remove: ConditionResource
var _original_index: int = -1


func _init(p_branch_node: BranchNodeResource, p_condition_to_remove: ConditionResource):
	self._branch_node = p_branch_node
	self._condition_to_remove = p_condition_to_remove


func execute() -> void:
	# Store the state *before* performing the action for undo.
	self._original_index = _branch_node.conditions.find(_condition_to_remove)

	if _original_index != -1:
		_branch_node.conditions.erase(_condition_to_remove)


func undo() -> void:
	# Restore the state using the stored information.
	if _original_index != -1:
		_branch_node.conditions.insert(_original_index, _condition_to_remove)
