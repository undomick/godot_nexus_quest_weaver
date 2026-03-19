# res://addons/quest_weaver/editor/components/sort_editor.gd
@tool
class_name QWSortEditor
extends VBoxContainer

signal move_up_requested
signal move_down_requested

@onready var up_button: Button = %Up
@onready var down_button: Button = %Down
@onready var index_label: Label = %Index


func _ready() -> void:
	up_button.pressed.connect(move_up_requested.emit)
	down_button.pressed.connect(move_down_requested.emit)


func set_index(index: int, total_count: int) -> void:
	index_label.text = str(index + 1)  # Display as 1-based index

	# Disable buttons if at boundaries
	up_button.disabled = (index == 0)
	down_button.disabled = (index >= total_count - 1)

	# Visual hint: dim disabled buttons
	up_button.modulate.a = 0.3 if up_button.disabled else 1.0
	down_button.modulate.a = 0.3 if down_button.disabled else 1.0
