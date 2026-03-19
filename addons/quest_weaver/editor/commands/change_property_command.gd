# res://addons/quest_weaver/editor/commands/change_property_command.gd
@tool
class_name ChangePropertyCommand
extends EditorCommand

var _resource: Resource
var _property_name: String
var _new_value: Variant
var _old_value: Variant


func _init(p_resource: Resource, p_property_name: String, p_new_value: Variant):
	self._resource = p_resource
	self._property_name = p_property_name
	self._new_value = p_new_value


func execute() -> void:
	if not is_instance_valid(_resource):
		return
	_old_value = _resource.get(_property_name)
	_resource.set(_property_name, _new_value)


func undo() -> void:
	if not is_instance_valid(_resource):
		return
	_resource.set(_property_name, _old_value)
