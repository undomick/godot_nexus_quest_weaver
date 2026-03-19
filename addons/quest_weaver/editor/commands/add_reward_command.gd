# res://addons/quest_weaver/editor/commands/add_reward_command.gd
@tool
class_name AddRewardCommand
extends EditorCommand

var _context_node: QuestContextNodeResource
var _reward_added: Dictionary = {}
var _added_index: int = -1


func _init(p_context_node: QuestContextNodeResource):
	self._context_node = p_context_node


func execute() -> void:
	if _reward_added.is_empty():
		_reward_added = {"id": &"", "amount": 1, "linked_objective_id": &"", "description": ""}
	_context_node.rewards.append(_reward_added)
	_added_index = _context_node.rewards.size() - 1


func undo() -> void:
	if _added_index >= 0 and _added_index < _context_node.rewards.size():
		_context_node.rewards.remove_at(_added_index)
	_added_index = -1
