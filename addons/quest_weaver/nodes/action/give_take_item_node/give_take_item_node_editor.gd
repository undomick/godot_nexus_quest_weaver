# res://addons/quest_weaver/nodes/action/give_take_item_node/give_take_item_node_editor.gd
@tool

extends NodePropertyEditorBase

var _is_setting_up := false

@onready var action_picker: OptionButton = %ActionPicker

@onready var terminal_checkbox: CheckBox = %TerminalCheckBox

@onready var content_container: VBoxContainer = %ItemContainer


func _ready() -> void:
	action_picker.item_selected.connect(_on_action_changed)
	terminal_checkbox.toggled.connect(_on_terminal_toggled)


func set_node_data(node_data: GraphNodeResource) -> void:
	_is_setting_up = true

	super.set_node_data(node_data)
	if not node_data is GiveTakeItemNodeResource:
		_is_setting_up = false
		return

	action_picker.clear()
	for action_name in node_data.Action.keys():
		action_picker.add_item(action_name.capitalize().replace("_", " "))

	action_picker.select(node_data.action)
	terminal_checkbox.button_pressed = node_data.is_terminal

	_rebuild_ui()
	_is_setting_up = false


func _rebuild_ui() -> void:
	if not is_instance_valid(content_container):
		return

	for child in content_container.get_children():
		child.queue_free()

	var node = edited_node_data as GiveTakeItemNodeResource

	# Switch UI based on Action
	match node.action:
		GiveTakeItemNodeResource.Action.REWARD_FROM_QUEST:
			_build_quest_picker_ui(node)

		GiveTakeItemNodeResource.Action.ITEMS_FROM_OBJECTIVE:
			_build_objective_picker_ui(node)
			_add_partial_checkbox(node)
			_add_complete_objective_checkbox(node)

		GiveTakeItemNodeResource.Action.TAKE:
			_build_item_list_ui(node)
			_add_partial_checkbox(node)

		GiveTakeItemNodeResource.Action.GIVE:
			_build_item_list_ui(node)


# --- UI BUILDERS ---


func _build_quest_picker_ui(node: GiveTakeItemNodeResource) -> void:
	var label = Label.new()
	label.text = "Source Quest ID:"
	content_container.add_child(label)

	var quest_edit = QWConstants.AutoCompleteLineEditScene.instantiate()
	QWEditorUtils.populate_quest_id_completer(quest_edit)
	quest_edit.text = str(node.target_quest_id)
	var filter_edit = quest_edit.get_node_or_null("%FilterEdit")
	if is_instance_valid(filter_edit):
		filter_edit.focus_entered.connect(
			func(): QWEditorUtils.refresh_quest_id_completer_from_active_graph(quest_edit)
		)

	quest_edit.text_submitted.connect(
		func(t):
			if _is_setting_up:
				return
			property_update_requested.emit(node.id, "target_quest_id", StringName(t), null, {})
	)

	content_container.add_child(quest_edit)


func _build_objective_picker_ui(node: GiveTakeItemNodeResource) -> void:
	var label = Label.new()
	label.text = "Target Objective ID:"
	content_container.add_child(label)

	var obj_edit = LineEdit.new()
	obj_edit.text = str(node.target_objective_id)
	obj_edit.placeholder_text = "e.g. collect_wood_objective"
	obj_edit.tooltip_text = "The ID of the objective that defines the required items."

	obj_edit.text_submitted.connect(
		func(t):
			if _is_setting_up:
				return
			property_update_requested.emit(node.id, "target_objective_id", StringName(t), null, {})
	)
	obj_edit.focus_exited.connect(
		func():
			if _is_setting_up:
				return
			if str(node.target_objective_id) != obj_edit.text:
				property_update_requested.emit(
					node.id, "target_objective_id", StringName(obj_edit.text), null, {}
				)
	)

	content_container.add_child(obj_edit)


func _add_partial_checkbox(node: GiveTakeItemNodeResource) -> void:
	var cb = CheckBox.new()
	cb.text = "Allow Partial Deposit"
	cb.tooltip_text = "If checked, takes whatever amount the player has (up to the requirement) and updates quest progress."

	cb.set_block_signals(true)
	cb.button_pressed = node.allow_partial_deposit
	cb.set_block_signals(false)

	cb.toggled.connect(
		func(v):
			if _is_setting_up:
				return
			property_update_requested.emit(node.id, "allow_partial_deposit", v, null, {})
	)
	content_container.add_child(cb)


func _add_complete_objective_checkbox(node: GiveTakeItemNodeResource) -> void:
	var cb = CheckBox.new()
	cb.text = "Complete Objective"
	cb.tooltip_text = "When Success output triggers, automatically mark the target objective as completed."

	cb.set_block_signals(true)
	cb.button_pressed = node.complete_objective_on_success
	cb.set_block_signals(false)

	cb.toggled.connect(
		func(v):
			if _is_setting_up:
				return
			property_update_requested.emit(node.id, "complete_objective_on_success", v, null, {})
	)
	content_container.add_child(cb)


func _build_item_list_ui(node: GiveTakeItemNodeResource) -> void:
	var list_container = VBoxContainer.new()
	content_container.add_child(list_container)

	var keys = node.items.keys()
	var sorted_keys = []
	var temp_keys = []

	for k in keys:
		if str(k).begins_with("__new_"):
			temp_keys.append(k)
		else:
			sorted_keys.append(k)

	sorted_keys.sort_custom(func(a, b): return str(a) < str(b))
	sorted_keys.append_array(temp_keys)

	var current_display_index = 0

	for i in range(sorted_keys.size()):
		var key = sorted_keys[i]
		var key_str = str(key)
		var is_temp = false

		if key_str.begins_with("__new_"):
			is_temp = true

		var entry = QWConstants.ItemStackEntryScene.instantiate()
		list_container.add_child(entry)

		entry.setup(current_display_index, key, node.items[key], is_temp)

		if not is_temp:
			current_display_index += 1

		entry.key_changed.connect(_on_item_key_changed)
		entry.value_changed.connect(_on_item_val_changed)
		entry.remove_requested.connect(_on_item_deleted)

	var add_btn = Button.new()
	add_btn.text = "+ Add Item"
	add_btn.pressed.connect(_on_add_item_pressed)
	content_container.add_child(add_btn)


# --- LOGIC HANDLERS ---


func _on_action_changed(index: int) -> void:
	if _is_setting_up:
		return  # GUARD

	if is_instance_valid(edited_node_data):
		property_update_requested.emit(edited_node_data.id, "action", index, null, {})
		(edited_node_data as GiveTakeItemNodeResource).action = index
		_rebuild_ui()


func _on_add_item_pressed() -> void:
	if _is_setting_up:
		return  # GUARD

	var node = edited_node_data as GiveTakeItemNodeResource
	var new_key = StringName("__new_%d" % Time.get_ticks_msec())
	node.items[new_key] = 1

	_emit_items_update()
	_rebuild_ui()

	await get_tree().process_frame
	if not is_instance_valid(content_container):
		return

	var list_container = content_container.get_child(0)
	if list_container.get_child_count() > 0:
		var last_row = list_container.get_child(list_container.get_child_count() - 1)
		if last_row.get_child_count() > 1:
			last_row.get_child(1).grab_focus()


func _on_item_key_changed(old_key: StringName, new_key_text: String):
	if _is_setting_up:
		return  # GUARD
	if new_key_text.is_empty():
		return
	if str(old_key) == new_key_text:
		return

	var node = edited_node_data as GiveTakeItemNodeResource
	var new_key = StringName(new_key_text)

	if not node.items.has(old_key):
		return

	if node.items.has(new_key):
		push_warning("Item '%s' is already in the list." % new_key)
		call_deferred(&"_rebuild_ui")
		return

	var val = node.items[old_key]
	node.items.erase(old_key)
	node.items[new_key] = val

	_emit_items_update()
	call_deferred(&"_rebuild_ui")


func _on_item_val_changed(key, new_val):
	if _is_setting_up:
		return  # GUARD
	var node = edited_node_data as GiveTakeItemNodeResource
	node.items[key] = new_val
	_emit_items_update()


func _on_item_deleted(key):
	if _is_setting_up:
		return  # GUARD
	var node = edited_node_data as GiveTakeItemNodeResource
	node.items.erase(key)
	_emit_items_update()
	call_deferred(&"_rebuild_ui")


func _emit_items_update():
	var node = edited_node_data as GiveTakeItemNodeResource
	property_update_requested.emit(node.id, "items", node.items.duplicate(), null, {})


func _on_terminal_toggled(pressed: bool) -> void:
	if _is_setting_up:
		return  # GUARD

	if is_instance_valid(edited_node_data):
		property_update_requested.emit(edited_node_data.id, "is_terminal", pressed, null, {})
		edited_node_data.is_terminal = pressed
		edited_node_data._update_ports_from_data()
