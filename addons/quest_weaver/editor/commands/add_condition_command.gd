# res://addons/quest_weaver/editor/commands/add_condition_command.gd
@tool
class_name AddConditionCommand
extends EditorCommand

var _branch_node: BranchNodeResource
var _condition_to_add: ConditionResource


func _init(p_branch_node: BranchNodeResource):
	self._branch_node = p_branch_node


func execute() -> void:
	# If this is the first execution (not a redo), create a new condition.
	if not is_instance_valid(_condition_to_add):
		_condition_to_add = ConditionResource.new()

	_branch_node.conditions.append(_condition_to_add)


func undo() -> void:
	_branch_node.conditions.erase(_condition_to_add)
