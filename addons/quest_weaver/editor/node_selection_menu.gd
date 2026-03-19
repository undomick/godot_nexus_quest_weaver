# res://addons/quest_weaver/editor/node_selection_menu.gd
@tool

class_name NodeSelectionMenu

extends PopupPanel

signal node_selected(type_name: StringName)

var _all_node_types: Array[NodeTypeInfo] = []

var _filtered_indices: Array[int] = []  # Maps list index to original array index

@onready var filter_edit: LineEdit = %FilterEdit

@onready var node_list: ItemList = %NodeList


func _ready() -> void:
	filter_edit.text_changed.connect(_on_filter_text_changed)
	# Confirm selection via Enter key in text field
	filter_edit.text_submitted.connect(_on_text_submitted)
	# Forward navigation keys from text field to the list
	filter_edit.gui_input.connect(_on_filter_gui_input)

	node_list.item_activated.connect(_on_list_item_activated)

	# Fix: Only trigger selection on left click to allow scrolling with the mouse wheel
	node_list.item_clicked.connect(
		func(index, _at_pos, mouse_btn_index):
			if mouse_btn_index == MOUSE_BUTTON_LEFT:
				_on_list_item_activated(index)
	)

	about_to_popup.connect(_on_about_to_popup)


func set_available_nodes(node_types: Array[NodeTypeInfo]) -> void:
	# Sort: Category first, then Name (duplicate to avoid mutating caller's array)
	var sorted = node_types.duplicate()
	sorted.sort_custom(
		func(a, b):
			if a.category != b.category:
				return a.category < b.category
			return a.node_name < b.node_name
	)
	_all_node_types = sorted
	_refresh_list("")


func _refresh_list(filter: String) -> void:
	node_list.clear()
	_filtered_indices.clear()

	var filter_lower = filter.to_lower()
	var category_resource = QWConstants.get_graph_node_category()
	var icon_size = Vector2i(16, 16)

	for i in range(_all_node_types.size()):
		var info = _all_node_types[i]

		# Filter logic
		if not filter_lower.is_empty() and not info.node_name.to_lower().contains(filter_lower):
			continue

		var display_text = info.node_name

		# 1. Determine category color
		var category_color = Color.GRAY  # Standard fallback
		if category_resource and category_resource.categories.has(info.category):
			category_color = category_resource.categories[info.category]

		# 2. Icon Logic
		var item_icon: Texture2D
		var use_modulate = false

		if info.icon:
			item_icon = info.icon
			use_modulate = true
		else:
			# Fallback: Generated square (color is baked in)
			var img = Image.create(icon_size.x, icon_size.y, false, Image.FORMAT_RGBA8)
			img.fill(category_color)
			item_icon = ImageTexture.create_from_image(img)
			use_modulate = false  # Do not tint again

		var item_idx = node_list.add_item(display_text, item_icon)

		# 3. Apply color tint
		if use_modulate:
			# Slightly brighten the color for better visibility against dark editor backgrounds
			node_list.set_item_icon_modulate(item_idx, category_color + Color(0.2, 0.2, 0.2))

		# 4. Tooltip
		if not info.description.is_empty():
			node_list.set_item_tooltip(item_idx, info.description)

		_filtered_indices.append(i)

	# Automatically select the first item to allow immediate "Enter" key confirmation
	if node_list.item_count > 0:
		node_list.select(0)


func _on_filter_text_changed(new_text: String) -> void:
	_refresh_list(new_text)


func _on_text_submitted(_text: String) -> void:
	if node_list.item_count > 0:
		var selected_items = node_list.get_selected_items()
		if selected_items.size() > 0:
			_on_list_item_activated(selected_items[0])
		else:
			_on_list_item_activated(0)


func _on_list_item_activated(index: int) -> void:
	var original_index = _filtered_indices[index]
	var info = _all_node_types[original_index]
	node_selected.emit(StringName(info.node_name))
	hide()


func _on_about_to_popup() -> void:
	filter_edit.clear()
	_refresh_list("")
	# Set focus to search field immediately
	filter_edit.call_deferred(&"grab_focus")


func _on_filter_gui_input(event: InputEvent) -> void:
	# Allows arrow key navigation in the list while typing in the text field
	if event is InputEventKey and event.is_pressed():
		var selected = node_list.get_selected_items()
		var current_selection = selected[0] if selected.size() > 0 else 0

		if event.keycode == KEY_DOWN:
			if current_selection < node_list.item_count - 1:
				node_list.select(current_selection + 1)
				node_list.ensure_current_is_visible()
			get_viewport().set_input_as_handled()

		elif event.keycode == KEY_UP:
			if current_selection > 0:
				node_list.select(current_selection - 1)
				node_list.ensure_current_is_visible()
			get_viewport().set_input_as_handled()
