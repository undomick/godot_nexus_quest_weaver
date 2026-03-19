# res://addons/quest_weaver/editor/components/item_stack_entry.gd
@tool

class_name ItemStackEntry

extends HBoxContainer

signal key_changed(old_key: StringName, new_key: StringName)

signal value_changed(key: StringName, new_amount: int)

signal remove_requested(key: StringName)

var _current_key: StringName = &""

var _is_setup := false

var _is_temp_display := false

@onready var index_label: Label = %IndexLabel

@onready var auto_complete: Control = %AutoComplete

@onready var amount_spinbox: SpinBox = %AmountSpinBox

@onready var delete_button: Button = %DeleteButton


func _ready() -> void:
	if is_instance_valid(auto_complete):
		auto_complete.text_submitted.connect(_on_id_submitted)
		QWEditorUtils.populate_item_completer(auto_complete)

		if _is_temp_display:
			auto_complete.text = ""
		elif not str(_current_key).is_empty():
			auto_complete.text = str(_current_key)

	amount_spinbox.value_changed.connect(_on_amount_changed)
	delete_button.pressed.connect(func(): remove_requested.emit(_current_key))


func setup(index: int, item_id: StringName, amount: int, is_temp: bool = false) -> void:
	_is_setup = true
	_current_key = item_id
	_is_temp_display = is_temp

	if is_instance_valid(index_label):
		if is_temp:
			index_label.text = "[+]"
			index_label.modulate = Color(1, 1, 1, 0.5)
		else:
			index_label.text = "[%d]" % (index + 1)
			index_label.modulate = Color(1, 1, 1, 1.0)

	if is_instance_valid(auto_complete):
		if is_temp:
			auto_complete.text = ""
		else:
			auto_complete.text = str(item_id)

	if is_instance_valid(amount_spinbox):
		amount_spinbox.set_value_no_signal(amount)

	_is_setup = false


func _on_id_submitted(new_text: String) -> void:
	if _is_setup:
		return

	if _is_temp_display and new_text.is_empty():
		return

	var new_key = StringName(new_text)
	if new_key != _current_key:
		key_changed.emit(_current_key, new_key)
		_current_key = new_key
		_is_temp_display = false


func _on_amount_changed(new_val: float) -> void:
	if _is_setup:
		return
	value_changed.emit(_current_key, int(new_val))
