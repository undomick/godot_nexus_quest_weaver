# res://addons/quest_weaver/editor/components/reward_entry.gd
@tool

class_name RewardEditorEntry

extends VBoxContainer

signal remove_requested

signal data_changed

var _reward_data: Dictionary

var _is_setup: bool = false

var _is_temp_display := false

@onready var index_label: Label = %IndexLabel

@onready var auto_complete: Control = %AutoComplete

@onready var amount_spinbox: SpinBox = %AmountSpinBox

@onready var optional_checkbox: CheckBox = %OptionalCheckbox

@onready var objective_container: HBoxContainer = %ObjectiveContainer

@onready var objective_edit: LineEdit = %ObjectiveEdit

@onready var delete_button: Button = %DeleteButton


func _ready() -> void:
	if is_instance_valid(auto_complete):
		auto_complete.text_submitted.connect(_on_id_submitted)
		QWEditorUtils.populate_item_completer(auto_complete)

		if _is_temp_display:
			auto_complete.text = ""
		elif _reward_data:
			auto_complete.text = str(_reward_data.get("id", ""))

	amount_spinbox.value_changed.connect(_on_amount_changed)

	objective_edit.text_submitted.connect(func(_t): objective_edit.release_focus())
	objective_edit.focus_exited.connect(_on_objective_changed)
	optional_checkbox.toggled.connect(_on_optional_toggled)
	delete_button.pressed.connect(func(): remove_requested.emit())


func setup(data: Dictionary, index: int, is_temp: bool = false) -> void:
	_is_setup = true
	_reward_data = data
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
			auto_complete.text = str(data.get("id", ""))

	if is_instance_valid(amount_spinbox):
		amount_spinbox.set_value_no_signal(data.get("amount", 100))

	var linked_obj = str(data.get("linked_objective_id", ""))
	var has_objective = not linked_obj.is_empty()

	if is_instance_valid(optional_checkbox):
		optional_checkbox.set_pressed_no_signal(has_objective)

	if is_instance_valid(objective_edit):
		objective_edit.text = linked_obj
		objective_container.visible = has_objective

	_is_setup = false


func _on_id_submitted(new_text: String) -> void:
	if _is_setup:
		return

	if _is_temp_display and new_text.is_empty():
		return

	_reward_data["id"] = StringName(new_text)
	_is_temp_display = false
	data_changed.emit()


func _on_amount_changed(new_val: float) -> void:
	if _is_setup:
		return
	_reward_data["amount"] = int(new_val)
	data_changed.emit()


func _on_optional_toggled(toggled_on: bool) -> void:
	if not is_instance_valid(objective_edit):
		return

	objective_container.visible = toggled_on

	if toggled_on:
		objective_edit.grab_focus()
	else:
		objective_edit.text = ""
		if not _is_setup:
			_reward_data["linked_objective_id"] = &""
			data_changed.emit()


func _on_objective_changed() -> void:
	if _is_setup:
		return
	var new_text = objective_edit.text
	if _reward_data.get("linked_objective_id", "") != new_text:
		_reward_data["linked_objective_id"] = StringName(new_text)
		data_changed.emit()
