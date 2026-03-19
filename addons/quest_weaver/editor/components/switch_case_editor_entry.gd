@tool

class_name SwitchCaseEditorEntry

extends HBoxContainer

signal value_changed(new_value: String)

signal port_name_changed(new_name: String)

signal remove_requested

@onready var remove_button: Button = %RemoveButton

@onready var value_edit: LineEdit = %ValueEdit

@onready var port_name_edit: LineEdit = %PortNameEdit


func _ready() -> void:
	remove_button.pressed.connect(remove_requested.emit)
	value_edit.text_submitted.connect(func(_t): value_changed.emit(value_edit.text))
	value_edit.focus_exited.connect(func(): value_changed.emit(value_edit.text))
	port_name_edit.text_submitted.connect(func(_t): port_name_changed.emit(port_name_edit.text))
	port_name_edit.focus_exited.connect(func(): port_name_changed.emit(port_name_edit.text))


func display_data(case_port: SwitchCasePort) -> void:
	if is_instance_valid(case_port):
		value_edit.text = case_port.value_string
		port_name_edit.text = case_port.port_name
