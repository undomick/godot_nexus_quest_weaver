# res://addons/quest_weaver/nodes/action/event_node/event_node_editor.gd
@tool

class_name EventNodeEditor

extends NodePropertyEditorBase

var _is_setting_up := false

@onready var event_name_edit: LineEdit = %SignalNameEdit

@onready var payload_list_container: VBoxContainer = %PayloadListContainer

@onready var add_payload_button: Button = %AddPayloadButton

@onready var terminal_checkbox: CheckBox = %TerminalCheckBox


func _ready() -> void:
	var old_payload_edit = get_node_or_null("%PayloadEdit")
	if is_instance_valid(old_payload_edit):
		old_payload_edit.queue_free()

	event_name_edit.text_submitted.connect(func(_text): _on_event_name_confirmed())
	event_name_edit.focus_exited.connect(_on_event_name_confirmed)
	add_payload_button.pressed.connect(_on_add_payload_pressed)
	terminal_checkbox.toggled.connect(_on_terminal_toggled)


func set_node_data(node_data: GraphNodeResource) -> void:
	super.set_node_data(node_data)
	if not node_data is EventNodeResource:
		return

	_is_setting_up = true
	event_name_edit.text = node_data.event_name

	terminal_checkbox.button_pressed = node_data.is_terminal

	call_deferred(&"_rebuild_payload_list")

	_is_setting_up = false


func _rebuild_payload_list() -> void:
	for child in payload_list_container.get_children():
		child.queue_free()

	var event_node: EventNodeResource = edited_node_data
	if not is_instance_valid(event_node):
		return

	for i in range(event_node.payload_entries.size()):
		var entry = event_node.payload_entries[i]
		_add_payload_entry_ui(entry, i)


func _add_payload_entry_ui(entry: EventNodeResource.PayloadEntry, index: int) -> void:
	var hbox = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var payload_extra := {"payload_index": index}

	# 1. Key (LineEdit)
	var key_edit = LineEdit.new()
	key_edit.text = entry.key
	key_edit.placeholder_text = "Key/Name"
	key_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key_edit.custom_minimum_size.x = 100
	key_edit.focus_exited.connect(
		func(): _on_entry_key_confirmed(key_edit.text, entry, payload_extra)
	)
	hbox.add_child(key_edit)

	# 2. Type Picker (OptionButton)
	var type_picker = OptionButton.new()
	for type_name in EventNodeResource.PayloadEntry.Type.keys():
		type_picker.add_item(type_name)
	type_picker.select(entry.value_type)
	type_picker.item_selected.connect(func(idx): _on_entry_type_changed(idx, entry, payload_extra))
	hbox.add_child(type_picker)

	# 3. Value (LineEdit)
	var value_edit = LineEdit.new()
	value_edit.text = entry.value_string
	value_edit.placeholder_text = "Value"
	value_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_edit.focus_exited.connect(
		func(): _on_entry_value_confirmed(value_edit.text, entry, payload_extra)
	)
	hbox.add_child(value_edit)

	# 4. Remove Button
	var remove_button = Button.new()
	remove_button.text = "X"
	remove_button.flat = true
	remove_button.pressed.connect(_on_remove_payload_pressed.bind(index))
	hbox.add_child(remove_button)

	payload_list_container.add_child(hbox)


# --- Signal Handlers for the new UI ---


func _on_event_name_confirmed() -> void:
	var current_text = event_name_edit.text
	if is_instance_valid(edited_node_data) and edited_node_data.event_name != current_text:
		property_update_requested.emit(
			edited_node_data.id, "event_name", StringName(current_text), null, {}
		)


func _on_add_payload_pressed() -> void:
	if not is_instance_valid(edited_node_data) or _is_setting_up:
		return

	complex_action_requested.emit(edited_node_data.id, "add_payload_entry", {})


func _on_remove_payload_pressed(index: int) -> void:
	if not is_instance_valid(edited_node_data) or _is_setting_up:
		return

	var event_node: EventNodeResource = edited_node_data
	var entry_to_remove = event_node.payload_entries[index]

	var payload = {"entry": entry_to_remove, "index": index}
	complex_action_requested.emit(edited_node_data.id, "remove_payload_entry", payload)


func _on_entry_key_confirmed(
	new_key: String, entry: EventNodeResource.PayloadEntry, extra: Dictionary
) -> void:
	if _is_setting_up:
		return
	if entry.key != new_key:
		property_update_requested.emit(edited_node_data.id, "key", new_key, entry, extra)


func _on_entry_value_confirmed(
	new_value_string: String, entry: EventNodeResource.PayloadEntry, extra: Dictionary
) -> void:
	if _is_setting_up:
		return
	if entry.value_string != new_value_string:
		property_update_requested.emit(
			edited_node_data.id, "value_string", new_value_string, entry, extra
		)


func _on_entry_type_changed(
	new_type_index: int, entry: EventNodeResource.PayloadEntry, extra: Dictionary
) -> void:
	if _is_setting_up:
		return
	if entry.value_type != new_type_index:
		property_update_requested.emit(
			edited_node_data.id, "value_type", new_type_index, entry, extra
		)


func _on_terminal_toggled(pressed: bool) -> void:
	if is_instance_valid(edited_node_data) and edited_node_data.is_terminal != pressed:
		property_update_requested.emit(edited_node_data.id, "is_terminal", pressed, null, {})
