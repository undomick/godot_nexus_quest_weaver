# res://addons/quest_weaver/editor/commands/remove_payload_command.gd
@tool
class_name RemovePayloadCommand
extends EditorCommand

var _event_node: EventNodeResource
var _entry_to_remove: EventNodeResource.PayloadEntry
var _original_index: int = -1


func _init(
	p_event_node: EventNodeResource,
	p_entry_to_remove: EventNodeResource.PayloadEntry,
	p_index: int = -1
):
	self._event_node = p_event_node
	self._entry_to_remove = p_entry_to_remove
	self._original_index = (
		p_index
		if p_index >= 0
		else (
			_event_node.payload_entries.find(_entry_to_remove)
			if is_instance_valid(p_entry_to_remove)
			else -1
		)
	)


func execute() -> void:
	if _original_index < 0 and is_instance_valid(_entry_to_remove):
		_original_index = _event_node.payload_entries.find(_entry_to_remove)
	if _original_index >= 0 and _original_index < _event_node.payload_entries.size():
		var entry = _event_node.payload_entries[_original_index]
		_event_node.payload_entries.remove_at(_original_index)
		_entry_to_remove = entry


func undo() -> void:
	if _original_index >= 0 and is_instance_valid(_entry_to_remove):
		_event_node.payload_entries.insert(_original_index, _entry_to_remove)
