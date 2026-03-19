# res://addons/quest_weaver/editor/commands/remove_reward_command.gd
@tool
class_name RemoveRewardCommand
extends EditorCommand

var _context_node: QuestContextNodeResource
var _index: int
var _removed_reward: Dictionary
var _has_stored: bool = false


func _init(p_context_node: QuestContextNodeResource, p_index: int):
	self._context_node = p_context_node
	self._index = p_index


func execute() -> void:
	if _index >= 0 and _index < _context_node.rewards.size():
		_removed_reward = _context_node.rewards[_index].duplicate(true)
		_context_node.rewards.remove_at(_index)
		_has_stored = true


func undo() -> void:
	if _has_stored:
		_context_node.rewards.insert(_index, _removed_reward)
		_has_stored = false
