# res://addons/quest_weaver/editor/components/random_output_editor_entry.gd
@tool

class_name RandomOutputEditorEntry

extends HBoxContainer

signal name_changed(new_name: String)

signal weight_changed(new_weight: int)

signal remove_requested

var _weight_undo_value: int = 0

var _port_name_undo_value: String = ""

@onready var port_name_edit: LineEdit = %PortNameEdit

@onready var weight_spinbox: SpinBox = %WeightSpinBox

@onready var remove_button: Button = %RemoveButton


func _ready() -> void:
	port_name_edit.focus_entered.connect(func(): _port_name_undo_value = port_name_edit.text)
	port_name_edit.text_submitted.connect(func(_text): _on_port_name_confirmed())
	port_name_edit.focus_exited.connect(_on_port_name_confirmed)

	weight_spinbox.focus_entered.connect(_on_weight_edit_started)
	weight_spinbox.focus_exited.connect(_on_weight_edit_finished)

	remove_button.pressed.connect(remove_requested.emit)


func display_data(output_port: RandomOutputPort) -> void:
	port_name_edit.text = output_port.port_name
	weight_spinbox.value = output_port.weight


func _on_port_name_confirmed() -> void:
	var new_name = port_name_edit.text
	if _port_name_undo_value != new_name:
		name_changed.emit(new_name)


func _on_weight_edit_started() -> void:
	_weight_undo_value = int(weight_spinbox.value)


func _on_weight_edit_finished() -> void:
	var new_weight = int(weight_spinbox.value)
	if _weight_undo_value != new_weight:
		weight_changed.emit(new_weight)
