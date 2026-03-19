# res://addons/quest_weaver/editor/components/synchronize_input_editor_entry.gd
@tool

class_name SynchronizeInputEditorEntry

extends VBoxContainer

signal name_changed(new_name: String)

signal remove_requested

var _port_name_undo_value: String = ""

@onready var port_name_edit: LineEdit = %PortNameEdit

@onready var remove_button: Button = %RemoveButton


func _ready() -> void:
	port_name_edit.focus_entered.connect(func(): _port_name_undo_value = port_name_edit.text)
	port_name_edit.text_submitted.connect(func(_text): _on_port_name_confirmed())
	port_name_edit.focus_exited.connect(_on_port_name_confirmed)

	remove_button.pressed.connect(remove_requested.emit)


func set_input_port(input_port: SynchronizeInputPort) -> void:
	port_name_edit.text = input_port.port_name


func _on_port_name_confirmed() -> void:
	var new_name = port_name_edit.text
	if _port_name_undo_value != new_name:
		name_changed.emit(new_name)
