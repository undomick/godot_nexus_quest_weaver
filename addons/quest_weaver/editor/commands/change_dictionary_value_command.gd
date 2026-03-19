# res://addons/quest_weaver/editor/commands/change_dictionary_value_command.gd
@tool
class_name ChangeDictionaryValueCommand
extends EditorCommand

var _target_dictionary: Dictionary
var _key: Variant
var _new_value: Variant
var _old_value: Variant
var _key_existed: bool


func _init(p_dictionary: Dictionary, p_key: Variant, p_new_value: Variant):
	self._target_dictionary = p_dictionary
	self._key = p_key
	self._new_value = p_new_value


func execute() -> void:
	if _target_dictionary == null:
		return
	_key_existed = _target_dictionary.has(_key)
	if _key_existed:
		_old_value = _target_dictionary.get(_key)

	_target_dictionary[_key] = _new_value


func undo() -> void:
	if _target_dictionary == null:
		return
	if _key_existed:
		_target_dictionary[_key] = _old_value
	else:
		_target_dictionary.erase(_key)
