# res://addons/quest_weaver/editor/quest_weaver_graph.gd
@tool
class_name QuestWeaverGraphController
extends GraphEdit

## SIGNALS ##
signal selection_finished(node_id: StringName)
signal node_selection_requested(node_id: StringName)
signal deletion_requested(node_ids: Array[StringName])
signal connection_to_empty_requested(
	from_node: StringName, from_port: int, release_position: Vector2
)
signal node_moved(node_id: StringName, new_position: Vector2)
signal connection_request_forwarded(
	from_node: StringName, from_port: int, to_node: StringName, to_port: int
)
signal disconnection_request_forwarded(
	from_node: StringName, from_port: int, to_node: StringName, to_port: int
)
signal view_changed(scroll_offset: Vector2, zoom: float)
## Emitted when display_graph has finished rebuilding the visual graph (after async _rebuild_visual_graph).
signal graph_display_completed

## REFERENCES & STATE ##
var node_registry: NodeTypeRegistry
var data_manager: QWGraphData
var editor_scale: float = 1.0
var is_connecting := false
var _connection_start_data: Dictionary
var _is_loading_graph: bool = false
var _is_rebuilding_graph := false
var _nodes_to_be_ready: int = 0
var _graph_resource_for_connection: QuestGraphResource = null

# Debounce flag for GLOBAL rebuilds
var _is_connection_rebuild_scheduled: bool = false

# Backdrop drag: last position per frame for delta calculation when moving inner nodes
var _last_backdrop_positions: Dictionary = {}
# Backdrop drag: only nodes that were inside the frame at drag start move with it (frame_id -> Array[StringName])
var _backdrop_drag_inner_nodes: Dictionary = {}
# Last selection when left-click was released; used so Backdrop menu can use it if right-click cleared selection.
var _last_selected_visual_nodes: Array[GraphElement] = []

## INITIALIZATION ##


func _ready():
	node_selected.connect(_on_view_node_selected)
	delete_nodes_request.connect(_on_view_nodes_deleted)
	connection_to_empty.connect(_on_view_connection_to_empty)
	connection_request.connect(connection_request_forwarded.emit)
	disconnection_request.connect(disconnection_request_forwarded.emit)
	scroll_offset_changed.connect(func(_offset): _emit_view_changed_signal())


func initialize(
	p_node_registry: NodeTypeRegistry, p_data_manager: QWGraphData, p_editor_scale: float
):
	self.node_registry = p_node_registry
	self.data_manager = p_data_manager
	self.editor_scale = p_editor_scale


## PUBLIC API ##


func display_graph(graph_resource: QuestGraphResource):
	_is_loading_graph = true
	_is_connection_rebuild_scheduled = false
	var expected_active_path: String = (
		"" if not is_instance_valid(graph_resource) else data_manager.get_active_graph_path()
	)

	await _rebuild_visual_graph(graph_resource, expected_active_path)

	if is_instance_valid(graph_resource):
		set_zoom(graph_resource.editor_zoom)
		await get_tree().process_frame
		set_scroll_offset(graph_resource.editor_scroll_offset)

	_is_loading_graph = false
	graph_display_completed.emit()


## Converts the current mouse position to the logic graph coordinate system.
func get_mouse_position_in_graph() -> Vector2:
	# 1. Get mouse position relative to the GraphEdit control's top-left corner
	var local_mouse = get_local_mouse_position()

	# 2. Safety: Avoid division by zero
	var current_zoom = zoom
	if current_zoom <= 0.001:
		current_zoom = 1.0

	# 3. Apply GraphEdit Zoom and Scroll logic
	var graph_point = (local_mouse + scroll_offset) / current_zoom

	return graph_point


func clear_backdrop_drag_state() -> void:
	_last_backdrop_positions.clear()
	_backdrop_drag_inner_nodes.clear()


## Clears all visual nodes synchronously. Call before plugin shutdown to break signal lambdas
## that capture node_data (GraphNodeResource), which would otherwise keep ConditionResource alive.
func clear_visual_graph_sync() -> void:
	_is_rebuilding_graph = true
	_graph_resource_for_connection = null
	_last_selected_visual_nodes.clear()
	_last_backdrop_positions.clear()
	_backdrop_drag_inner_nodes.clear()
	clear_connections()
	var to_free: Array[Node] = []
	for child in get_children():
		if child is GraphElement:
			to_free.append(child)
	for node in to_free:
		node.free()
	_is_rebuilding_graph = false


## Sets which nodes are "attached" to this backdrop for the current drag. Only these nodes will move with the backdrop.
func set_backdrop_drag_inner_nodes(frame_id: StringName, inner_ids: Array[StringName]) -> void:
	_backdrop_drag_inner_nodes[frame_id] = inner_ids.duplicate()


## Updates only the visual title font size of a backdrop (e.g. while dragging the slider). Does not change the resource.
func set_backdrop_title_font_size_preview(node_id: StringName, font_size: int) -> void:
	_set_backdrop_title_font_size(node_id, font_size)


## Sets the title font size on a GraphFrame. GraphFrame has no title_font_size theme property; the title Label must be updated directly.
func _set_backdrop_title_font_size(node_id: StringName, font_size: int) -> void:
	var visual_node = get_node_or_null(NodePath(node_id))
	if not (visual_node is GraphFrame):
		return
	var titlebar = visual_node.get_titlebar_hbox()
	if not is_instance_valid(titlebar):
		return
	for child in titlebar.get_children():
		if child is Label:
			child.add_theme_font_size_override("font_size", font_size)
			return


func update_node_ports(graph_resource: QuestGraphResource, node_id: StringName):
	if _is_rebuilding_graph:
		return
	if not is_instance_valid(graph_resource):
		return

	var visual_node: GraphElement = get_node_or_null(NodePath(node_id))
	var node_data = graph_resource.nodes.get(node_id)

	if not (is_instance_valid(visual_node) and is_instance_valid(node_data)):
		return

	if node_data.has_method("_update_ports_from_data"):
		node_data._update_ports_from_data()

	_disconnect_visuals_for_node(node_id)

	if visual_node is GraphNode:
		_build_node_internal_structure(visual_node, node_data)

		if visual_node is QWGraphNode:
			visual_node.summary_text = node_data.get_editor_summary()
			visual_node.queue_redraw()

	_enforce_node_size(visual_node, node_data)

	await get_tree().process_frame

	_restore_connections_for_node(graph_resource, node_id)


# --- LOCALISED CONNECTION LOGIC ---


func _disconnect_visuals_for_node(node_id: StringName):
	var all_connections = get_connection_list()
	for conn in all_connections:
		if conn.from_node == node_id or conn.to_node == node_id:
			disconnect_node(conn.from_node, conn.from_port, conn.to_node, conn.to_port)


func _restore_connections_for_node(graph_resource: QuestGraphResource, node_id: StringName):
	for connection in graph_resource.connections:
		if connection.from_node == node_id or connection.to_node == node_id:
			if _validate_connection_visually(
				connection.from_node, connection.from_port, connection.to_node, connection.to_port
			):
				connect_node(
					connection.from_node,
					connection.from_port,
					connection.to_node,
					connection.to_port
				)


# --- GLOBAL CONNECTION LOGIC (Fallback / Load) ---


func _schedule_connection_rebuild(graph_resource: QuestGraphResource) -> void:
	if _is_connection_rebuild_scheduled:
		return
	_is_connection_rebuild_scheduled = true

	# Debounce: wait for nodes to be ready before rebuilding connections
	await get_tree().process_frame
	await get_tree().process_frame

	if not is_instance_valid(graph_resource) or graph_resource != data_manager.get_active_graph():
		_is_connection_rebuild_scheduled = false
		return

	_rebuild_visual_connections_only(graph_resource)
	_is_connection_rebuild_scheduled = false


func update_visual_node_position(graph_resource: QuestGraphResource, node_id: StringName):
	if not is_instance_valid(graph_resource):
		return
	var visual_node = get_node_or_null(NodePath(node_id))
	var node_data = graph_resource.nodes.get(node_id)
	if is_instance_valid(visual_node) and is_instance_valid(node_data):
		visual_node.position_offset = node_data.graph_position


func update_summary_text(graph_resource: QuestGraphResource, node_id: StringName):
	if _is_rebuilding_graph:
		return
	var visual_node: QWGraphNode = get_node_or_null(NodePath(node_id))
	var node_data = graph_resource.nodes.get(node_id)
	if is_instance_valid(visual_node) and is_instance_valid(node_data):
		visual_node.summary_text = node_data.get_editor_summary()
		visual_node.queue_redraw()


func redraw_node_structure(graph_resource: QuestGraphResource, node_id: StringName):
	update_node_ports(graph_resource, node_id)


func create_single_visual_node(node_data: GraphNodeResource):
	var node_id: StringName = node_data.id
	if not has_node(NodePath(node_id)):
		_create_visual_node(node_data)


func rebuild_connections(graph_resource: QuestGraphResource):
	_schedule_connection_rebuild(graph_resource)


func set_is_connecting(p_is_connecting: bool, from_node: StringName = "", from_port: int = -1):
	self.is_connecting = p_is_connecting
	if is_connecting:
		_connection_start_data = {"from_node": from_node, "from_port": from_port}
	else:
		_connection_start_data.clear()


func get_connection_start_data() -> Dictionary:
	return _connection_start_data


func add_visual_connection(
	from_node: StringName, from_port: int, to_node: StringName, to_port: int
) -> void:
	if _validate_connection_visually(from_node, from_port, to_node, to_port):
		connect_node(from_node, from_port, to_node, to_port)


func remove_visual_connection(
	from_node: StringName, from_port: int, to_node: StringName, to_port: int
) -> void:
	if has_node(NodePath(from_node)) and has_node(NodePath(to_node)):
		disconnect_node(from_node, from_port, to_node, to_port)


func select_visual_node(node_id: StringName) -> void:
	var node = get_node_or_null(NodePath(node_id))
	if node is GraphElement:
		node.selected = true
	for child in get_children():
		if child is GraphElement and child.name != node_id:
			child.selected = false


## Returns currently selected GraphElements. Use for clear_selection, backdrop creation, etc.
func get_selected_graph_elements() -> Array[GraphElement]:
	var result: Array[GraphElement] = []
	for child in get_children():
		if child is GraphElement and child.selected:
			result.append(child)
	return result


## Returns IDs of currently selected nodes. Use for delete, copy, etc.
func get_selected_node_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for child in get_children():
		if child is GraphElement and child.selected:
			result.append(child.name)
	return result


func refresh_from_data(graph_resource: QuestGraphResource):
	if not is_instance_valid(graph_resource):
		display_graph(null)
		return
	_synchronize_visual_graph(graph_resource)


func refresh_single_node_visuals(node_id: StringName) -> void:
	var current_graph = data_manager.get_active_graph()
	if not is_instance_valid(current_graph):
		return
	var node_data = current_graph.nodes.get(node_id)
	var visual_node = get_node_or_null(NodePath(node_id))
	if not (is_instance_valid(node_data) and is_instance_valid(visual_node)):
		return

	if node_data.has_method("_update_ports_from_data"):
		node_data._update_ports_from_data()

	if visual_node is GraphFrame and node_data is BackdropNodeResource:
		var style_copy: StyleBoxFlat = visual_node.get_theme_stylebox("panel").duplicate(true)
		style_copy.bg_color = node_data.color
		visual_node.add_theme_stylebox_override("panel", style_copy)
		visual_node.add_theme_stylebox_override("panel_selected", style_copy)
		_set_backdrop_title_font_size(node_id, node_data.title_font_size)
		visual_node.title = node_data.title
		visual_node.autoshrink_enabled = false
		visual_node.custom_minimum_size = Vector2(120, 80)
		visual_node.update_minimum_size()

	elif visual_node is GraphNode:
		visual_node.theme_type_variation = node_data.category
		visual_node.title = node_registry.get_name_for_script(node_data.get_script())

		if visual_node is QWGraphNode:
			visual_node.summary_text = node_data.get_editor_summary()
			visual_node.queue_redraw()

		_build_node_internal_structure(visual_node, node_data)
		_enforce_node_size(visual_node, node_data)


func clear_visual_connections_from_port(node_id: StringName, port_index: int):
	var connection_list = get_connection_list()
	for connection in connection_list:
		if connection.from_node == node_id and connection.from_port == port_index:
			disconnect_node(
				connection.from_node, connection.from_port, connection.to_node, connection.to_port
			)


func update_node_structure_and_connections(node_id: StringName) -> void:
	if _is_rebuilding_graph:
		return
	var current_graph = data_manager.get_active_graph()
	# This calls the optimized local update now
	update_node_ports(current_graph, node_id)


## PRIVATE DRAWING LOGIC ##


func _synchronize_visual_graph(graph_resource: QuestGraphResource) -> void:
	for node_id in graph_resource.nodes:
		var visual_node = get_node_or_null(NodePath(node_id))

		if is_instance_valid(visual_node):
			refresh_single_node_visuals(node_id)
		else:
			create_single_visual_node(graph_resource.nodes[node_id])

	var visual_nodes_to_remove: Array[Node] = []
	for child in get_children():
		if child is GraphElement and not graph_resource.nodes.has(child.name):
			visual_nodes_to_remove.append(child)
	for node_to_remove in visual_nodes_to_remove:
		node_to_remove.queue_free()

	_schedule_connection_rebuild(graph_resource)


func _gui_input(event: InputEvent) -> void:
	if (
		event is InputEventMouseButton
		and (
			event.button_index == MOUSE_BUTTON_WHEEL_UP
			or event.button_index == MOUSE_BUTTON_WHEEL_DOWN
		)
		and event.is_command_or_control_pressed()
	):
		call_deferred(&"_emit_view_changed_signal")

	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and event.is_released()
	):
		call_deferred(&"_emit_selection_finished")


func _emit_view_changed_signal():
	if _is_loading_graph:
		return
	if is_instance_valid(self):
		view_changed.emit(scroll_offset, zoom)


func _build_node_internal_structure(visual_node: GraphNode, node_data: GraphNodeResource):
	for child in visual_node.get_children():
		if child is Container:
			visual_node.remove_child(child)
			child.queue_free()
	visual_node.clear_all_slots()

	var input_count = node_data.input_ports.size()
	var output_count = node_data.output_ports.size()
	var port_row_count = max(input_count, output_count)

	for i in range(port_row_count):
		var is_input_enabled = i < input_count and not node_data.input_ports[i].is_empty()
		var is_output_enabled = i < output_count and node_data.output_ports[i] != " "

		visual_node.set_slot(
			i,
			is_input_enabled,
			0,
			Color.WHITE if is_input_enabled else Color.GRAY.darkened(0.4),
			is_output_enabled,
			0,
			Color.WHITE if is_output_enabled else Color.GRAY.darkened(0.4)
		)

		var row_container = HBoxContainer.new()
		row_container.custom_minimum_size.y = 24
		visual_node.add_child(row_container)

		var input_label = Label.new()
		if i < input_count:
			input_label.text = node_data.input_ports[i]
			input_label.modulate.a = 1.0 if is_input_enabled else 0.4
		row_container.add_child(input_label)

		var spacer = Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		if node_data is RandomNodeResource or node_data is ParallelNodeResource:
			row_container.show_behind_parent = false
		else:
			row_container.show_behind_parent = true

		row_container.add_child(spacer)

		var output_label = Label.new()
		if i < output_count:
			output_label.text = node_data.output_ports[i]
			output_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			output_label.modulate.a = 1.0 if is_output_enabled else 0.4
		row_container.add_child(output_label)


func _rebuild_visual_graph(graph_resource: QuestGraphResource, expected_active_path: String = ""):
	_is_rebuilding_graph = true
	clear_connections()
	# Remove all graph elements (GraphNode and GraphFrame/Backdrop) so backdrops don't appear in other quests.
	for child in get_children():
		if child is GraphElement:
			child.queue_free()

	_graph_resource_for_connection = null
	_nodes_to_be_ready = 0

	if not is_instance_valid(graph_resource) or graph_resource.nodes.is_empty():
		_is_rebuilding_graph = false
		return

	await get_tree().process_frame
	# Abort if active graph changed during await (e.g. "Close All" fired multiple display_graph calls)
	if data_manager.get_active_graph_path() != expected_active_path:
		_is_rebuilding_graph = false
		return

	_nodes_to_be_ready = graph_resource.nodes.size()
	_graph_resource_for_connection = graph_resource

	for node_id in graph_resource.nodes:
		var node_data: GraphNodeResource = graph_resource.nodes[node_id]
		_create_visual_node(node_data, true)


func _create_visual_node(
	node_data: GraphNodeResource, is_part_of_full_rebuild: bool = false
) -> GraphElement:
	if not is_instance_valid(node_registry):
		push_warning("GraphController: Node Registry not initialized, cannot create visual node.")
		return null

	var visual_node: GraphElement

	# Node creation logic
	if node_data is BackdropNodeResource:
		var frame = GraphFrame.new()
		frame.mouse_filter = Control.MOUSE_FILTER_PASS
		frame.resizable = true
		frame.autoshrink_enabled = false
		frame.custom_minimum_size = Vector2(120, 80)
		frame.size = node_data.node_size
		frame.resize_request.connect(
			func(new_size: Vector2):
				frame.size = new_size
				node_data.node_size = new_size
		)
		frame.resize_end.connect(
			func(new_size: Vector2):
				frame.size = new_size
				node_data.node_size = new_size
		)
		visual_node = frame

	elif node_data is CommentNodeResource:
		var g_node = QWGraphNode.new()
		g_node.resizable = true
		g_node.custom_minimum_size = Vector2(150, 100)
		g_node.size = node_data.node_size
		g_node.summary_text = node_data.get_editor_summary()
		g_node.resize_end.connect(func(new_size: Vector2): node_data.node_size = new_size)
		visual_node = g_node

	else:
		var g_node = QWGraphNode.new()
		g_node.resizable = false
		g_node.summary_text = node_data.get_editor_summary()
		visual_node = g_node

	visual_node.name = node_data.id
	if is_part_of_full_rebuild:
		visual_node.ready.connect(_on_visual_node_ready, CONNECT_ONE_SHOT)
	visual_node.position_offset = node_data.graph_position
	visual_node.position_offset_changed.connect(_on_view_node_moved.bind(visual_node.name))

	add_child(visual_node)

	_apply_node_decorations(visual_node, node_data)

	_enforce_node_size(visual_node, node_data)
	return visual_node


func _on_visual_node_ready():
	_nodes_to_be_ready -= 1
	if _nodes_to_be_ready <= 0:
		if is_instance_valid(_graph_resource_for_connection):
			_schedule_connection_rebuild(_graph_resource_for_connection)  # GLOBAL INIT
			_graph_resource_for_connection = null
		_is_rebuilding_graph = false


func _rebuild_visual_connections_only(graph_resource: QuestGraphResource):
	if not is_instance_valid(graph_resource):
		return

	clear_connections()

	for connection in graph_resource.connections:
		if connection.has_all(["from_node", "from_port", "to_node", "to_port"]):
			if _validate_connection_visually(
				connection.from_node, connection.from_port, connection.to_node, connection.to_port
			):
				connect_node(
					connection.from_node,
					connection.from_port,
					connection.to_node,
					connection.to_port
				)


func _validate_connection_visually(
	from_node: StringName, from_port: int, to_node: StringName, to_port: int
) -> bool:
	var from_path = NodePath(from_node)
	var to_path = NodePath(to_node)

	if not has_node(from_path) or not has_node(to_path):
		return false

	var from_visual = get_node(from_path)
	var to_visual = get_node(to_path)

	if not (from_visual is GraphNode and to_visual is GraphNode):
		return false

	if from_visual.get_output_port_count() <= from_port:
		return false
	if to_visual.get_input_port_count() <= to_port:
		return false

	return true


func _apply_node_decorations(visual_node: GraphElement, node_data: GraphNodeResource) -> void:
	if not is_instance_valid(visual_node) or not is_instance_valid(node_data):
		return

	var category_resource = QWConstants.get_graph_node_category()
	var category_color: Color = Color.DARK_GRAY

	if category_resource and category_resource.categories.has(node_data.category):
		category_color = category_resource.categories[node_data.category]

	if visual_node is GraphFrame and node_data is BackdropNodeResource:
		var style_copy: StyleBoxFlat = visual_node.get_theme_stylebox("panel").duplicate(true)
		style_copy.bg_color = node_data.color

		visual_node.add_theme_stylebox_override("panel", style_copy)
		visual_node.add_theme_stylebox_override("panel_selected", style_copy)
		_set_backdrop_title_font_size(visual_node.name, node_data.title_font_size)
		visual_node.title = node_data.title
		visual_node.resizable = true
		visual_node.autoshrink_enabled = false
		visual_node.custom_minimum_size = Vector2(120, 80)

		var resizer_icon = get_theme_icon("resizer", "GraphNode")
		visual_node.add_theme_icon_override("resizer", resizer_icon)
		return

	if visual_node is GraphNode:
		visual_node.title = node_registry.get_name_for_script(node_data.get_script())

		var base_style = visual_node.get_theme_stylebox("titlebar", "GraphNode")
		var title_style: StyleBoxFlat

		if base_style is StyleBoxFlat:
			title_style = base_style.duplicate()
		else:
			title_style = StyleBoxFlat.new()
			title_style.corner_radius_top_left = 3
			title_style.corner_radius_top_right = 3
			title_style.content_margin_left = 12
			title_style.content_margin_right = 12
			title_style.content_margin_top = 4
			title_style.content_margin_bottom = 4

		title_style.bg_color = category_color
		visual_node.add_theme_stylebox_override("titlebar", title_style)

		var title_style_selected = title_style.duplicate()
		title_style_selected.bg_color = category_color.lightened(0.2)
		visual_node.add_theme_stylebox_override("titlebar_selected", title_style_selected)

		var icon_texture = node_data.get_icon()
		var titlebar_hbox = visual_node.get_titlebar_hbox()

		if is_instance_valid(titlebar_hbox):
			var existing_icon = titlebar_hbox.get_node_or_null("QWHeaderIcon")
			if existing_icon:
				existing_icon.queue_free()

			if icon_texture:
				var icon_rect = TextureRect.new()
				icon_rect.name = "QWHeaderIcon"
				icon_rect.texture = icon_texture
				icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				icon_rect.custom_minimum_size = Vector2(24, 24)

				titlebar_hbox.add_child(icon_rect)
				titlebar_hbox.move_child(icon_rect, 0)

		_build_node_internal_structure(visual_node, node_data)


func _enforce_node_size(visual_node: GraphElement, node_data: GraphNodeResource):
	if node_data is CommentNodeResource or node_data is BackdropNodeResource:
		return

	var type_info: NodeTypeInfo = node_registry.get_info_for_script(node_data.get_script())
	if is_instance_valid(type_info):
		var size_enum = type_info.default_size
		var standard_size = QWNodeSizes.get_vector_for_size(size_enum)

		visual_node.custom_minimum_size = standard_size
		visual_node.set_size(standard_size)

		visual_node.update_minimum_size()


func get_nodes_inside_frame(frame_id: StringName) -> Array[StringName]:
	var frame = get_node_or_null(NodePath(frame_id))
	if not (frame is GraphFrame):
		return []
	return _get_nodes_inside_frame(frame)


func _get_nodes_inside_frame(frame: GraphFrame) -> Array[StringName]:
	var result: Array[StringName] = []
	var frame_rect = Rect2(frame.position_offset, frame.size)
	for child in get_children():
		# GraphFrames must not move other GraphFrames along with them
		if child is GraphFrame:
			continue
		if child is GraphElement and child != frame:
			var elem: GraphElement = child
			var center = elem.position_offset + elem.size / 2
			if frame_rect.has_point(center):
				result.append(child.name)
	return result


func _on_view_node_moved(node_id: StringName):
	var node_path = NodePath(node_id)
	if not has_node(node_path):
		return
	var visual_node: GraphElement = get_node(node_path)
	# When a backdrop (GraphFrame) is moved, move only nodes that were inside it at drag start
	if visual_node is GraphFrame:
		var new_pos = visual_node.position_offset
		var last_pos = _last_backdrop_positions.get(node_id, new_pos)
		_last_backdrop_positions[node_id] = new_pos
		var delta = new_pos - last_pos
		if delta != Vector2.ZERO:
			var inner_ids: Array = _backdrop_drag_inner_nodes.get(node_id, [])
			for inner_id in inner_ids:
				var inner_node: GraphElement = get_node_or_null(NodePath(inner_id))
				if is_instance_valid(inner_node):
					inner_node.position_offset += delta
	node_moved.emit(node_id, visual_node.position_offset)


func _on_view_node_selected(p_visual_node: Node):
	if p_visual_node is GraphElement:
		node_selection_requested.emit(p_visual_node.name)
	# Store current selection so Backdrop menu can use it if right-click clears it.
	call_deferred(&"_store_current_selection")


func _store_current_selection() -> void:
	_last_selected_visual_nodes.clear()
	for child in get_children():
		if child is GraphElement and child.selected:
			_last_selected_visual_nodes.append(child)


func _on_view_nodes_deleted(nodes: Array[StringName]):
	var nodes_to_process_set: Dictionary = {}
	for n in nodes:
		nodes_to_process_set[n] = true
	for child in get_children():
		if child is GraphFrame and child.selected:
			nodes_to_process_set[child.name] = true

	var final_deletion_list: Array[StringName] = []
	var current_graph = data_manager.get_active_graph()

	for node_name in nodes_to_process_set:
		var node_id = String(node_name)
		var is_protected = false

		if is_instance_valid(current_graph) and current_graph.nodes.has(node_id):
			var node_data = current_graph.nodes[node_id]

			if node_data is StartNodeResource:
				is_protected = true
				push_warning("QuestWeaver: The Start Node cannot be deleted.")

		if not is_protected:
			final_deletion_list.append(node_name)

	if not final_deletion_list.is_empty():
		deletion_requested.emit(final_deletion_list)


func _on_view_connection_to_empty(from_node: StringName, from_port: int, release_position: Vector2):
	connection_to_empty_requested.emit(from_node, from_port, release_position)


func _emit_selection_finished() -> void:
	var selected_nodes: Array[GraphElement] = []
	for child in get_children():
		if child is GraphElement and child.selected:
			selected_nodes.append(child)
	_last_selected_visual_nodes = selected_nodes

	if selected_nodes.size() == 1:
		var single_node: GraphElement = selected_nodes[0]
		if is_instance_valid(single_node):
			selection_finished.emit(single_node.name)


## Returns the last stored selection (when left-click was released). Used so Backdrop creation can use it if right-click cleared selection.
func get_last_selected_visual_nodes() -> Array[GraphElement]:
	return _last_selected_visual_nodes.duplicate()
