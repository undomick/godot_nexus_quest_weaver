# res://addons/quest_weaver/editor/components/parallel_output_editor_entry.gd
@tool

class_name ParallelOutputEditorEntry

extends VBoxContainer

signal remove_requested

signal name_changed(new_name: String)

# FIX: Added target_resource
signal property_changed(property_name: String, new_value: Variant, target_resource: Resource)

signal rebuild_requested

var output_port: ParallelOutputPort

var _port_name_undo_value: String = ""

@onready var remove_button: Button = %RemoveButton

@onready var port_name_edit: LineEdit = %PortNameEdit

@onready var condition_editor: PanelContainer = %ConditionEditor


func _ready() -> void:
	remove_button.pressed.connect(remove_requested.emit)
	port_name_edit.focus_entered.connect(func(): _port_name_undo_value = port_name_edit.text)
	port_name_edit.text_submitted.connect(func(_text): _on_port_name_confirmed())
	port_name_edit.focus_exited.connect(_on_port_name_confirmed)

	condition_editor.property_changed.connect(func(n, v, r): property_changed.emit(n, v, r))
	condition_editor.rebuild_requested.connect(rebuild_requested.emit)


func display_data(p_output_port: ParallelOutputPort) -> void:
	self.output_port = p_output_port
	port_name_edit.text = output_port.port_name
	condition_editor.edit_condition(output_port.condition)


func _on_port_name_confirmed() -> void:
	var new_name = port_name_edit.text
	if is_instance_valid(output_port) and _port_name_undo_value != new_name:
		name_changed.emit(new_name)
