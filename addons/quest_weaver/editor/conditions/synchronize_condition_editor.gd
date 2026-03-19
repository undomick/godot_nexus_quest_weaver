# res://addons/quest_weaver/editor/conditions/synchronize_condition_editor.gd
@tool

extends VBoxContainer

# This editor is specialized and only emits property changes.
# It doesn't need a 'rebuild_requested' signal as its structure is static.
signal property_changed(property_name: String, new_value: Variant)

var edited_condition: ConditionResource

var _value_undo_value: int = 0

@onready var check_type_picker: OptionButton = %CheckTypePicker

@onready var value_spinbox: SpinBox = %ValueSpinBox


func _ready() -> void:
	check_type_picker.clear()
	for type_name in ConditionResource.CheckType.keys():
		check_type_picker.add_item(type_name.replace("_", " ").capitalize())

	check_type_picker.item_selected.connect(_on_check_type_selected)

	# Use the robust focus-based logic for the SpinBox
	value_spinbox.focus_entered.connect(_on_value_spinbox_focus_entered)
	value_spinbox.focus_exited.connect(_on_value_spinbox_focus_exited)
	var line_edit = value_spinbox.get_line_edit()
	if is_instance_valid(line_edit):
		line_edit.text_submitted.connect(func(_text): _on_value_spinbox_focus_exited())


func edit_condition(condition_res: ConditionResource) -> void:
	self.edited_condition = condition_res

	## Context-specific fix: This editor only handles CHECK_SYNCHRONIZER. If the condition
	## was another type (e.g. from a template), we coerce it silently without emitting
	## property_changed to avoid Undo noise. Callers use this editor only for sync conditions.
	if edited_condition.type != ConditionResource.ConditionType.CHECK_SYNCHRONIZER:
		edited_condition.type = ConditionResource.ConditionType.CHECK_SYNCHRONIZER

	check_type_picker.select(edited_condition.check_type)
	value_spinbox.min_value = 0
	value_spinbox.max_value = 100
	value_spinbox.step = 1
	value_spinbox.set_value_no_signal(edited_condition.sync_value)


func _on_check_type_selected(index: int) -> void:
	if is_instance_valid(edited_condition) and edited_condition.check_type != index:
		property_changed.emit("check_type", index)


func _on_value_spinbox_focus_entered() -> void:
	if is_instance_valid(edited_condition):
		_value_undo_value = edited_condition.sync_value


func _on_value_spinbox_focus_exited() -> void:
	if not is_instance_valid(edited_condition):
		return

	var new_value = int(value_spinbox.value)
	if _value_undo_value != new_value:
		property_changed.emit("sync_value", new_value)
