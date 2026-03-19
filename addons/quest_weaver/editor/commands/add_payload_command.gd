# res://addons/quest_weaver/editor/commands/add_payload_command.gd
@tool
class_name AddPayloadCommand
extends EditorCommand

var _event_node: EventNodeResource
var _entry_to_add: EventNodeResource.PayloadEntry


func _init(p_event_node: EventNodeResource):
	self._event_node = p_event_node


func execute() -> void:
	if not is_instance_valid(_entry_to_add):
		_entry_to_add = EventNodeResource.PayloadEntry.new()

	_event_node.payload_entries.append(_entry_to_add)


func undo() -> void:
	_event_node.payload_entries.erase(_entry_to_add)
