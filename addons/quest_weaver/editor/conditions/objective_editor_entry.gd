# res://addons/quest_weaver/editor/conditions/objective_editor_entry.gd
@tool

class_name ObjectiveEditorEntry

extends PanelContainer

# --- SIGNALS ---
signal description_changed(new_description: String)

signal trigger_type_changed(new_trigger_type: int)

signal trigger_param_changed(param_name: String, new_value: Variant)

signal delete_requested

signal direct_property_changed(property_name: String, new_value: Variant)

signal id_changed(new_id: String)

signal requirements_changed(new_requirements: Dictionary)

signal move_up_requested

signal move_down_requested

var objective_resource: ObjectiveResource

var _is_setting_up := false

# --- UI REFERENCES ---
@onready var description_edit: LineEdit = %DescriptionEdit

@onready var delete_button: Button = %DeleteButton

@onready var trigger_type_picker: OptionButton = %TriggerTypePicker

@onready var counter_checkbox: CheckBox = %CounterCheckBox

@onready var track_progress_checkbox: CheckBox = %TrackProgressCheckbox

@onready var complete_on_delivery_checkbox: CheckBox = %CompleteOnDeliveryCheckbox

@onready var optional_checkbox: CheckBox = %OptionalCheckBox

@onready var hidden_checkbox: CheckBox = %HiddenCheckBox

@onready var trigger_params_container: VBoxContainer = %TriggerParamsContainer

@onready var id_line_edit: LineEdit = %IdLineEdit

@onready var copy_id_button: Button = %CopyIdButton

@onready var sort_editor: QWSortEditor = find_child("SortEditor", true, false)


func _ready() -> void:
	if is_instance_valid(sort_editor):
		sort_editor.move_up_requested.connect(move_up_requested.emit)
		sort_editor.move_down_requested.connect(move_down_requested.emit)

	# Text Inputs
	description_edit.text_submitted.connect(func(_text): description_edit.release_focus())
	description_edit.focus_exited.connect(func(): _on_description_changed(description_edit.text))

	id_line_edit.text_submitted.connect(func(_text): id_line_edit.release_focus())
	id_line_edit.focus_exited.connect(func(): _on_id_submitted(id_line_edit.text))

	# Buttons & Pickers
	delete_button.pressed.connect(delete_requested.emit)
	trigger_type_picker.item_selected.connect(_on_trigger_type_selected)
	copy_id_button.icon = get_theme_icon("Duplicate", "EditorIcons")
	copy_id_button.pressed.connect(_on_copy_id_pressed)

	# Checkboxes
	counter_checkbox.toggled.connect(_on_counter_toggled)
	track_progress_checkbox.toggled.connect(_on_track_progress_toggled)
	complete_on_delivery_checkbox.toggled.connect(_on_complete_on_delivery_toggled)
	optional_checkbox.toggled.connect(_on_optional_toggled)
	hidden_checkbox.toggled.connect(_on_hidden_toggled)

	# Setup Trigger Types
	trigger_type_picker.clear()
	for type_name in ObjectiveResource.TriggerType.keys():
		trigger_type_picker.add_item(type_name)


func set_objective(obj_res: ObjectiveResource) -> void:
	_is_setting_up = true
	self.objective_resource = obj_res

	id_line_edit.text = obj_res.id
	description_edit.text = obj_res.description
	trigger_type_picker.select(obj_res.trigger_type)
	track_progress_checkbox.button_pressed = obj_res.track_progress_since_activation
	if is_instance_valid(counter_checkbox):
		counter_checkbox.button_pressed = obj_res.show_counter

	if is_instance_valid(optional_checkbox):
		optional_checkbox.button_pressed = obj_res.is_optional

	if is_instance_valid(hidden_checkbox):
		hidden_checkbox.button_pressed = obj_res.is_hidden

	if is_instance_valid(complete_on_delivery_checkbox):
		complete_on_delivery_checkbox.button_pressed = obj_res.complete_on_delivery

	# Defer complex UI building to ensure safe node state
	call_deferred(&"_rebuild_trigger_param_ui")
	call_deferred(&"_finish_setup")


func update_sort_index(index: int, total_count: int) -> void:
	if is_instance_valid(sort_editor):
		sort_editor.set_index(index, total_count)


func _finish_setup() -> void:
	_is_setting_up = false


func _rebuild_trigger_param_ui():
	for child in trigger_params_container.get_children():
		child.queue_free()
	if not is_instance_valid(objective_resource):
		return

	var type = objective_resource.trigger_type

	# CASE A: LIST BASED (Requirements Dictionary)
	if (
		type == ObjectiveResource.TriggerType.ITEM_COLLECT
		or type == ObjectiveResource.TriggerType.KILL
	):
		_build_requirements_list_ui()
		# Track progress since activation: for ITEM_COLLECT (inventory snapshot) and KILL (future kill-adapter parity)
		track_progress_checkbox.visible = (
			type == ObjectiveResource.TriggerType.ITEM_COLLECT
			or type == ObjectiveResource.TriggerType.KILL
		)
		complete_on_delivery_checkbox.visible = (type == ObjectiveResource.TriggerType.ITEM_COLLECT)
		counter_checkbox.visible = true
	# CASE B: SINGLE PARAMETER (Legacy Trigger Params)
	else:
		_build_singular_param_ui()
		track_progress_checkbox.visible = false
		complete_on_delivery_checkbox.visible = false
		counter_checkbox.visible = false


# --- LIST BUILDER (ITEM / KILL) ---
func _build_requirements_list_ui():
	var dict = objective_resource.requirements

	# 1. Sort Keys (Real keys A-Z first, then Temp keys)
	var keys = dict.keys()
	var sorted_keys = []
	var temp_keys = []

	for k in keys:
		if str(k).begins_with("new_target_"):
			temp_keys.append(k)
		else:
			sorted_keys.append(k)

	# Explicit string comparison for StringNames
	sorted_keys.sort_custom(func(a, b): return str(a) < str(b))
	sorted_keys.append_array(temp_keys)

	var current_index = 0

	for key in sorted_keys:
		var row = HBoxContainer.new()

		var key_str = str(key)
		var is_temp = false

		# Logic to hide internal placeholder keys
		if key_str.begins_with("new_target_"):
			key_str = ""
			is_temp = true

		# 0. INDEX LABEL (UX Consistency)
		var index_lbl = Label.new()
		if is_temp:
			index_lbl.text = "[+]"
			index_lbl.modulate = Color(1, 1, 1, 0.5)
		else:
			index_lbl.text = "[%d]" % current_index
			index_lbl.modulate = Color(1, 1, 1, 0.5)
			current_index += 1

		row.add_child(index_lbl)

		# 1. KEY FIELD (ID)
		var key_edit = QWConstants.AutoCompleteLineEditScene.instantiate()

		if objective_resource.trigger_type == ObjectiveResource.TriggerType.ITEM_COLLECT:
			QWEditorUtils.populate_item_completer(key_edit)
			key_edit.tooltip_text = "Item ID"
		else:
			key_edit.tooltip_text = "Enemy ID"

		key_edit.text = key_str
		key_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		key_edit.size_flags_stretch_ratio = 2.0

		# Update Logic
		key_edit.text_submitted.connect(func(nk): _on_req_key_changed(key, nk))
		row.add_child(key_edit)

		# 2. VALUE FIELD (Amount)
		var val_spin = SpinBox.new()
		val_spin.min_value = 1
		val_spin.allow_greater = true
		val_spin.value = dict[key]
		val_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		val_spin.size_flags_stretch_ratio = 1.0

		val_spin.value_changed.connect(func(v): _on_req_val_changed(key, int(v)))
		row.add_child(val_spin)

		# 3. DELETE BUTTON
		var del_btn = Button.new()
		del_btn.text = "X"
		del_btn.flat = true
		del_btn.pressed.connect(func(): _on_req_deleted(key))
		row.add_child(del_btn)

		trigger_params_container.add_child(row)

	# Add Button
	var add_btn = Button.new()
	var type_label = (
		"Item"
		if objective_resource.trigger_type == ObjectiveResource.TriggerType.ITEM_COLLECT
		else "Enemy"
	)
	add_btn.text = "+ Add %s" % type_label
	add_btn.pressed.connect(_on_req_add_pressed)
	trigger_params_container.add_child(add_btn)


# --- SINGULAR BUILDER (LOCATION / INTERACT) ---
func _build_singular_param_ui():
	var key_map = {
		ObjectiveResource.TriggerType.LOCATION_ENTER: "location_id",
		ObjectiveResource.TriggerType.INTERACT: "target_path"
	}
	var param_key = key_map.get(objective_resource.trigger_type, "")
	if param_key == "":
		return  # Manual?

	var param_edit = LineEdit.new()
	param_edit.text = str(objective_resource.trigger_params.get(param_key, ""))
	param_edit.text_submitted.connect(func(t): trigger_param_changed.emit(param_key, t))
	param_edit.focus_exited.connect(func(): trigger_param_changed.emit(param_key, param_edit.text))

	add_param_row(param_key.replace("_", " ").capitalize(), param_edit)


# --- REQUIREMENTS HANDLERS ---


func _on_req_add_pressed():
	# Create unique temp key
	var new_key = StringName("new_target_%d" % Time.get_ticks_msec())
	objective_resource.requirements[new_key] = 1

	_emit_req_update()
	_rebuild_trigger_param_ui()

	# Set focus to the new field
	await get_tree().process_frame
	if not is_instance_valid(trigger_params_container):
		return

	if trigger_params_container.get_child_count() > 1:
		var last_row = trigger_params_container.get_child(
			trigger_params_container.get_child_count() - 2
		)
		if last_row is HBoxContainer and last_row.get_child_count() > 1:
			last_row.get_child(1).grab_focus()


func _on_req_key_changed(old_key, new_key_text):
	if new_key_text.is_empty():
		return
	if str(old_key) == new_key_text:
		return

	# FIX: Ensure old key still exists before modification
	if not objective_resource.requirements.has(old_key):
		return

	var new_key = StringName(new_key_text)

	if objective_resource.requirements.has(new_key):
		push_warning("Requirement '%s' is already in the list." % new_key)
		call_deferred(&"_rebuild_trigger_param_ui")
		return

	var val = objective_resource.requirements[old_key]
	objective_resource.requirements.erase(old_key)
	objective_resource.requirements[new_key] = val

	_emit_req_update()
	call_deferred(&"_rebuild_trigger_param_ui")


func _on_req_val_changed(key, new_val):
	objective_resource.requirements[key] = new_val
	_emit_req_update()


func _on_req_deleted(key):
	objective_resource.requirements.erase(key)
	_emit_req_update()
	call_deferred(&"_rebuild_trigger_param_ui")


func _emit_req_update():
	requirements_changed.emit(objective_resource.requirements.duplicate())


# --- Signal Handlers ---


func _on_description_changed(new_text: String):
	if _is_setting_up:
		return
	if is_instance_valid(objective_resource) and objective_resource.description != new_text:
		description_changed.emit(new_text)


func _on_id_submitted(new_text: String) -> void:
	if _is_setting_up:
		return
	if is_instance_valid(objective_resource) and String(objective_resource.id) != new_text:
		id_changed.emit(new_text)


func _on_trigger_type_selected(index: int):
	if _is_setting_up:
		return
	if is_instance_valid(objective_resource) and objective_resource.trigger_type != index:
		trigger_type_changed.emit(index)


func _on_counter_toggled(is_pressed: bool):
	if _is_setting_up:
		return
	if is_instance_valid(objective_resource) and objective_resource.show_counter != is_pressed:
		direct_property_changed.emit("show_counter", is_pressed)


func _on_track_progress_toggled(is_pressed: bool):
	if _is_setting_up:
		return
	if (
		is_instance_valid(objective_resource)
		and objective_resource.track_progress_since_activation != is_pressed
	):
		direct_property_changed.emit("track_progress_since_activation", is_pressed)


func _on_complete_on_delivery_toggled(is_pressed: bool):
	if _is_setting_up:
		return
	if (
		is_instance_valid(objective_resource)
		and objective_resource.complete_on_delivery != is_pressed
	):
		direct_property_changed.emit("complete_on_delivery", is_pressed)


func _on_optional_toggled(is_pressed: bool):
	if _is_setting_up:
		return
	if is_instance_valid(objective_resource) and objective_resource.is_optional != is_pressed:
		direct_property_changed.emit("is_optional", is_pressed)


func _on_hidden_toggled(is_pressed: bool):
	if _is_setting_up:
		return
	if is_instance_valid(objective_resource) and objective_resource.is_hidden != is_pressed:
		direct_property_changed.emit("is_hidden", is_pressed)


func _on_copy_id_pressed():
	DisplayServer.clipboard_set(id_line_edit.text)


func add_param_row(label_text: String, control: Control) -> void:
	var row = HBoxContainer.new()
	var label = Label.new()
	label.text = label_text + ":"
	label.custom_minimum_size.x = 80
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	trigger_params_container.add_child(row)
