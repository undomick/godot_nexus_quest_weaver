# res://addons/quest_weaver/editor/components/auto_complete_line_edit.gd
@tool

class_name AutoCompleteLineEdit

extends VBoxContainer

signal text_changed(new_text: String)

signal text_submitted(final_text: String)

var text: String:
	get:
		return filter_edit.text if is_instance_valid(filter_edit) else ""
	set(value):
		if is_instance_valid(filter_edit):
			filter_edit.text = value
		else:
			call_deferred(&"set", "text", value)

var _all_items: Array[String] = []

# Tracks if the mouse is currently hovering over the popup list.
# Essential to distinguish between "clicking a list item" and "clicking outside".
var _mouse_is_over_popup := false

@onready var filter_edit: LineEdit = %FilterEdit

@onready var popup_container: PanelContainer = %PopupContainer

@onready var result_list: ItemList = %ResultList


func _ready() -> void:
	result_list.focus_mode = Control.FOCUS_NONE

	# Make popup independent of parent layout
	popup_container.set_as_top_level(true)
	popup_container.hide()

	filter_edit.text_changed.connect(_on_internal_text_changed)
	filter_edit.text_submitted.connect(_on_internal_text_submitted)
	filter_edit.focus_entered.connect(_refilter_and_show_popup)
	filter_edit.focus_exited.connect(_on_focus_exited)
	filter_edit.item_rect_changed.connect(_update_popup_position)

	result_list.item_activated.connect(_on_item_confirmed)
	result_list.item_clicked.connect(
		func(index, _at_pos, mouse_btn):
			if mouse_btn == MOUSE_BUTTON_LEFT:
				_on_item_confirmed(index)
	)

	# Connect mouse events to track hover state.
	popup_container.mouse_entered.connect(func(): _mouse_is_over_popup = true)
	popup_container.mouse_exited.connect(func(): _mouse_is_over_popup = false)


func set_items(items_array: Array[String]) -> void:
	_all_items = items_array
	_all_items.sort()


func _on_internal_text_changed(new_text: String) -> void:
	text_changed.emit(new_text)
	_refilter_and_show_popup()


func _on_internal_text_submitted(final_text: String) -> void:
	popup_container.hide()
	text_submitted.emit(final_text)


# ==============================================================================
# ============================== CORE LOGIC ====================================
# ==============================================================================


func _on_focus_exited() -> void:
	# If the mouse is over the popup list, the focus loss was caused by
	# clicking a list item. In this case, `_on_item_confirmed` handles the logic.
	# We do nothing here to prevent submitting the incomplete/old text.
	if _mouse_is_over_popup:
		return

	# If the mouse is NOT over the list, the user clicked somewhere else.
	# It is safe to commit the current value immediately.
	popup_container.hide()
	_emit_text_submitted()


func _emit_text_submitted() -> void:
	if is_instance_valid(filter_edit):
		text_submitted.emit(filter_edit.text)


func _on_item_confirmed(index: int) -> void:
	# Since interaction is complete, reset the flag.
	_mouse_is_over_popup = false

	var selected_text: String = result_list.get_item_text(index)
	filter_edit.text = selected_text
	popup_container.hide()

	# Emit final value.
	text_submitted.emit(selected_text)


func _is_fuzzy_match(item_name: String, query: String) -> bool:
	if query.is_empty():
		return true

	var query_idx: int = 0
	for char in item_name:
		if query_idx < query.length() and char.to_lower() == query[query_idx].to_lower():
			query_idx += 1

	return query_idx == query.length()


func _refilter_and_show_popup() -> void:
	var query: String = filter_edit.text
	result_list.clear()

	for item in _all_items:
		if _is_fuzzy_match(item, query):
			result_list.add_item(item)

	if result_list.get_item_count() > 0:
		var popup_height: float = min(result_list.get_item_count() * 28 + 10, 250)
		popup_container.size = Vector2(filter_edit.size.x, popup_height)

		# Update position before showing
		popup_container.show()
		_update_popup_position()
	else:
		popup_container.hide()


func _update_popup_position() -> void:
	if not popup_container.visible or not is_instance_valid(filter_edit):
		return

	var global_pos = filter_edit.get_global_position()
	var size = filter_edit.get_size()

	# Place exactly below the line edit
	popup_container.position = Vector2(global_pos.x, global_pos.y + size.y)
	# Match width
	popup_container.size.x = size.x


# ==============================================================================
# FOCUS PROXYING
# ==============================================================================


func grab_focus(_hide_focus: bool = false) -> void:
	if is_instance_valid(filter_edit):
		filter_edit.grab_focus()


func has_focus(_ignore_hidden_focus: bool = false) -> bool:
	if is_instance_valid(filter_edit):
		return filter_edit.has_focus()
	return false
