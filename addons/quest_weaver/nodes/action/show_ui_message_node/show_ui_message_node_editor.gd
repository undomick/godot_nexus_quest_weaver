# res://addons/quest_weaver/nodes/action/show_ui_message_node/show_ui_message_node_editor.gd
@tool

extends NodePropertyEditorBase

var _registry_keys: Array[String] = []

var _spinbox_undo_values: Dictionary = {}

@onready var message_type_picker: OptionButton = %MessageTypeEdit

@onready var title_override_edit: LineEdit = %TitleOverrideEdit

@onready var message_override_edit: TextEdit = %MessageOverrideEdit

@onready var wait_checkbox: CheckBox = %WaitForCompletionCheckbox

@onready var anim_in_picker: OptionButton = %AnimationInPicker

@onready var ease_in_picker: OptionButton = %EaseInPicker

@onready var per_character_in_checkbox: CheckBox = %PerCharacterInCheckbox

@onready var anim_out_picker: OptionButton = %AnimationOutPicker

@onready var ease_out_picker: OptionButton = %EaseOutPicker

@onready var per_character_out_checkbox: CheckBox = %PerCharacterOutCheckbox

@onready var duration_in_container: HBoxContainer = %DurationInContainer

@onready var duration_out_container: HBoxContainer = %DurationOutContainer

@onready var character_stagger_container: HBoxContainer = %CharacterStaggerContainer

@onready var delay_title_message_container: HBoxContainer = %DelayTitleMessageContainer

@onready var duration_in_spinbox: SpinBox = %DurationInSpinBox

@onready var duration_out_spinbox: SpinBox = %DurationOutSpinBox

@onready var delay_title_message_spinbox: SpinBox = %DelayTitleMessageSpinBox

@onready var hold_duration_spinbox: SpinBox = %HoldDurationSpinBox

@onready var character_stagger_spinbox: SpinBox = %CharacterStaggerSpinBox

@onready var terminal_checkbox: CheckBox = %TerminalCheckBox


func _ready() -> void:
	_populate_animation_pickers()
	_populate_ease_pickers()

	message_type_picker.item_selected.connect(_on_message_type_selected)
	title_override_edit.focus_exited.connect(_on_title_override_confirmed)
	message_override_edit.focus_exited.connect(_on_message_override_confirmed)
	wait_checkbox.toggled.connect(_on_wait_toggled)

	anim_in_picker.item_selected.connect(_on_anim_in_selected)
	ease_in_picker.item_selected.connect(_on_ease_in_selected)
	per_character_in_checkbox.toggled.connect(_on_per_char_in_toggled)

	anim_out_picker.item_selected.connect(_on_anim_out_selected)
	ease_out_picker.item_selected.connect(_on_ease_out_selected)
	per_character_out_checkbox.toggled.connect(_on_per_char_out_toggled)

	terminal_checkbox.toggled.connect(_on_terminal_toggled)

	_connect_spinbox_signals(duration_in_spinbox, "duration_in")
	_connect_spinbox_signals(duration_out_spinbox, "duration_out")
	_connect_spinbox_signals(delay_title_message_spinbox, "delay_title_message")
	_connect_spinbox_signals(hold_duration_spinbox, "hold_duration")
	_connect_spinbox_signals(character_stagger_spinbox, "character_stagger_ms")


func _connect_spinbox_signals(spinbox: SpinBox, property_name: String) -> void:
	spinbox.value_changed.connect(
		func(new_value: float):
			if not is_instance_valid(edited_node_data):
				return

			var final_value: Variant = new_value
			# Handle the one integer property specifically.
			if property_name == "character_stagger_ms":
				final_value = int(new_value)

			if edited_node_data.get(property_name) != final_value:
				property_update_requested.emit(
					edited_node_data.id, property_name, final_value, null, {}
				)
	)


func set_node_data(node_data: GraphNodeResource) -> void:
	super.set_node_data(node_data)
	if not node_data is ShowUIMessageNodeResource:
		return

	_populate_message_type_picker()

	var current_type_str = str(node_data.message_type)
	var selection_index = _registry_keys.find(current_type_str)
	message_type_picker.select(selection_index)

	title_override_edit.text = node_data.title_override
	message_override_edit.text = node_data.message_override
	wait_checkbox.button_pressed = node_data.wait_for_completion
	anim_in_picker.select(node_data.animation_in)
	ease_in_picker.select(node_data.ease_in)
	per_character_in_checkbox.button_pressed = node_data.per_character_in
	anim_out_picker.select(node_data.animation_out)
	ease_out_picker.select(node_data.ease_out)
	per_character_out_checkbox.button_pressed = node_data.per_character_out
	duration_in_spinbox.set_value_no_signal(node_data.duration_in)
	duration_out_spinbox.set_value_no_signal(node_data.duration_out)
	delay_title_message_spinbox.set_value_no_signal(node_data.delay_title_message)
	hold_duration_spinbox.set_value_no_signal(node_data.hold_duration)
	character_stagger_spinbox.set_value_no_signal(node_data.character_stagger_ms)
	terminal_checkbox.button_pressed = node_data.is_terminal

	_update_ui_visibility()


# --- Handlers for confirmed changes ---


func _on_title_override_confirmed() -> void:
	var new_text = title_override_edit.text
	if is_instance_valid(edited_node_data) and edited_node_data.title_override != new_text:
		property_update_requested.emit(edited_node_data.id, "title_override", new_text, null, {})


func _on_message_override_confirmed() -> void:
	var new_text = message_override_edit.text
	if is_instance_valid(edited_node_data) and edited_node_data.message_override != new_text:
		property_update_requested.emit(
			edited_node_data.id, "message_override", StringName(new_text), null, {}
		)


func _on_wait_toggled(is_pressed: bool) -> void:
	if is_instance_valid(edited_node_data) and edited_node_data.wait_for_completion != is_pressed:
		property_update_requested.emit(
			edited_node_data.id, "wait_for_completion", is_pressed, null, {}
		)


func _on_message_type_selected(index: int):
	if index >= 0 and index < _registry_keys.size():
		var selected_key = StringName(_registry_keys[index])
		if is_instance_valid(edited_node_data) and edited_node_data.message_type != selected_key:
			property_update_requested.emit(
				edited_node_data.id, "message_type", selected_key, null, {}
			)


func _on_anim_in_selected(index: int) -> void:
	if is_instance_valid(edited_node_data) and edited_node_data.animation_in != index:
		property_update_requested.emit(edited_node_data.id, "animation_in", index, null, {})
	_update_ui_visibility()


func _on_ease_in_selected(index: int) -> void:
	if is_instance_valid(edited_node_data) and edited_node_data.ease_in != index:
		property_update_requested.emit(edited_node_data.id, "ease_in", index, null, {})


func _on_per_char_in_toggled(is_pressed: bool) -> void:
	if is_instance_valid(edited_node_data) and edited_node_data.per_character_in != is_pressed:
		property_update_requested.emit(
			edited_node_data.id, "per_character_in", is_pressed, null, {}
		)
	_update_ui_visibility()


func _on_anim_out_selected(index: int) -> void:
	if is_instance_valid(edited_node_data) and edited_node_data.animation_out != index:
		property_update_requested.emit(edited_node_data.id, "animation_out", index, null, {})
	_update_ui_visibility()


func _on_ease_out_selected(index: int) -> void:
	if is_instance_valid(edited_node_data) and edited_node_data.ease_out != index:
		property_update_requested.emit(edited_node_data.id, "ease_out", index, null, {})


func _on_per_char_out_toggled(is_pressed: bool) -> void:
	if is_instance_valid(edited_node_data) and edited_node_data.per_character_out != is_pressed:
		property_update_requested.emit(
			edited_node_data.id, "per_character_out", is_pressed, null, {}
		)
	_update_ui_visibility()


# --- UI Helper functions ---


func _populate_message_type_picker():
	message_type_picker.clear()
	_registry_keys.clear()

	var settings: QuestWeaverSettings = QWConstants.get_settings()
	if is_instance_valid(settings) and ResourceLoader.exists(settings.presentation_registry_path):
		var registry = ResourceLoader.load(settings.presentation_registry_path)
		if is_instance_valid(registry):
			for key in registry.entries.keys():
				var key_str = str(key)
				_registry_keys.append(key_str)
				message_type_picker.add_item(key_str)


func _populate_animation_pickers():
	anim_in_picker.clear()
	anim_out_picker.clear()
	for preset_name in ShowUIMessageNodeResource.AnimationPreset.keys():
		anim_in_picker.add_item(preset_name)
		anim_out_picker.add_item(preset_name)


func _populate_ease_pickers():
	ease_in_picker.clear()
	ease_out_picker.clear()
	var ease_names = ["In", "Out", "In Out", "Out In"]
	for ease_name in ease_names:
		ease_in_picker.add_item(ease_name)
		ease_out_picker.add_item(ease_name)


func _on_terminal_toggled(pressed: bool) -> void:
	if is_instance_valid(edited_node_data) and edited_node_data.is_terminal != pressed:
		property_update_requested.emit(edited_node_data.id, "is_terminal", pressed, null, {})
		edited_node_data.is_terminal = pressed
		edited_node_data._update_ports_from_data()


func _update_ui_visibility():
	if not is_instance_valid(edited_node_data):
		return

	var anim_in_preset = edited_node_data.animation_in
	var anim_out_preset = edited_node_data.animation_out
	var per_char_in = edited_node_data.per_character_in
	var per_char_out = edited_node_data.per_character_out

	var has_in_animation = anim_in_preset != ShowUIMessageNodeResource.AnimationPreset.NONE
	var has_out_animation = anim_out_preset != ShowUIMessageNodeResource.AnimationPreset.NONE

	duration_in_container.visible = has_in_animation
	duration_out_container.visible = has_out_animation
	per_character_in_checkbox.visible = has_in_animation
	per_character_out_checkbox.visible = has_out_animation

	var show_stagger = (per_char_in and has_in_animation) or (per_char_out and has_out_animation)
	character_stagger_container.visible = show_stagger

	delay_title_message_container.visible = has_in_animation
