# res://addons/quest_weaver/editor/quest_weaver_editor.gd
@tool
class_name QuestWeaverEditor
extends Control

signal validation_finished(results: Array[ValidationResult])

var node_registry: NodeTypeRegistry
var editor_plugin_instance
var editor_session_data: QuestEditorData
var validator: QuestValidator

var _input_handler: QWInputHandler
var _history: QWEditorHistory
var _clipboard: QWClipboard
var _action_handler: QWActionHandler
var _node_factory: QWNodeFactory
var _editor_interface
var _pending_node_creation_pos: Vector2
var _pending_connection_data: Dictionary
var _live_debugging_active := false
var _live_node_ids: Dictionary = {}
var _active_debug_nodes: Dictionary = {}
var _completed_node_ids: Dictionary = {}  # { "node_id": true }
var _failed_node_ids: Dictionary = {}  # { "node_id": true }
var _live_stylebox: StyleBoxFlat
var _completed_stylebox: StyleBoxFlat
var _failed_stylebox: StyleBoxFlat

@onready var graph_controller: QuestWeaverGraphController = %GraphEdit
@onready var properties_panel: PanelContainer = %PropertiesPanel
@onready var side_panel: VBoxContainer = %SidePanel
@onready var add_node_menu: NodeSelectionMenu = %AddNodeMenu
@onready var version_label: Label = %VersionLabel
@onready var data_manager: QWGraphData = %DataManager


func initialize(plugin, p_session_data: QuestEditorData, p_editor_interface) -> void:
	self.editor_plugin_instance = plugin
	self.editor_session_data = p_session_data
	self._editor_interface = p_editor_interface

	node_registry = NodeTypeRegistry.new()
	node_registry._build_lookup_tables()
	node_registry.validate_registry()

	_history = QWEditorHistory.new()
	_clipboard = QWClipboard.new()
	validator = QuestValidator.new()
	_action_handler = QWActionHandler.new()
	_action_handler.name = "ActionHandler"
	add_child(_action_handler)
	_node_factory = QWNodeFactory.new()
	_node_factory.name = "NodeFactory"
	add_child(_node_factory)
	_input_handler = QWInputHandler.new()
	_input_handler.name = "InputHandler"
	add_child(_input_handler)

	_history.initialize(self)
	_clipboard.initialize(node_registry)
	_action_handler.initialize(
		self, _history, data_manager, properties_panel, graph_controller, _clipboard
	)
	_node_factory.initialize(
		self, node_registry, data_manager, _history, graph_controller, add_node_menu
	)
	_input_handler.initialize(self, _history, _action_handler, graph_controller, _editor_interface)
	properties_panel.initialize(node_registry, data_manager, editor_plugin_instance)
	graph_controller.initialize(node_registry, data_manager, 1.0)
	side_panel.initialize(data_manager, p_editor_interface)
	QWEditorUtils.set_active_graph_callback(data_manager.get_active_graph)

	version_label.text = "v%s" % editor_plugin_instance.get_version()
	_init_debug_styles()
	_connect_signals()
	_history.version_changed.connect(_on_history_changed)
	_load_session_data()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		if is_visible_in_tree():
			if is_instance_valid(properties_panel):
				properties_panel.visible = true
	elif what == NOTIFICATION_PREDELETE:
		if is_instance_valid(_clipboard):
			_clipboard.clear()
		if is_instance_valid(validator):
			validator.free()
			validator = null
		if is_instance_valid(_history):
			_history.cleanup()


func _connect_signals() -> void:
	properties_panel.property_update_requested.connect(
		_action_handler.on_node_property_update_requested
	)
	properties_panel.property_preview_requested.connect(_on_property_preview_requested)
	properties_panel.complex_action_requested.connect(_action_handler.on_complex_action_requested)
	properties_panel.dive_in_requested.connect(edit_graph)
	properties_panel.node_ports_changed.connect(_on_node_ports_changed)

	side_panel.create_new_file_at_path.connect(_on_create_new_file_at_path)
	side_panel.open_file_requested.connect(edit_graph)
	side_panel.bookmark_selected.connect(_on_bookmark_selected)
	side_panel.close_bookmark_requested.connect(_on_close_bookmark_requested)
	side_panel.close_all_requested.connect(_on_close_all_requested)
	side_panel.save_active_graph_requested.connect(data_manager.save_active_graph)
	side_panel.save_single_file_requested.connect(save_single_file)
	side_panel.save_all_files_requested.connect(_action_handler.save_all_modified_graphs)

	graph_controller.begin_node_move.connect(_action_handler.on_begin_node_move)
	graph_controller.end_node_move.connect(_action_handler.on_end_node_move)
	graph_controller.node_selection_requested.connect(select_and_inspect_node)
	graph_controller.selection_finished.connect(_on_selection_finished_and_popup)
	graph_controller.deletion_requested.connect(_action_handler.on_nodes_deleted)
	graph_controller.connection_to_empty.connect(_on_connection_to_empty)
	graph_controller.connection_request_forwarded.connect(_action_handler.on_connection_request)
	graph_controller.disconnection_request_forwarded.connect(
		_action_handler.on_disconnection_request
	)
	graph_controller.view_changed.connect(_on_graph_view_changed)
	graph_controller.gui_input.connect(_on_graph_editor_gui_input)

	data_manager.active_graph_changed.connect(_on_active_graph_changed)
	data_manager.graph_dirty_status_changed.connect(side_panel.mark_file_as_unsaved)
	data_manager.graph_was_saved.connect(_on_graph_was_saved)

	_action_handler.node_data_changed.connect(_on_node_data_changed)
	_node_factory.create_backdrop_requested.connect(_create_backdrop_from_selection)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _input_handler.handle_event(event):
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and event.is_pressed()
	):
		if not get_global_rect().has_point(get_global_mouse_position()):
			return
		if not graph_controller.get_global_rect().has_point(get_global_mouse_position()):
			clear_graph_selection()


func get_history() -> QWEditorHistory:
	return _history


func get_action_handler() -> QWActionHandler:
	return _action_handler


func set_editor_scale(scale: float) -> void:
	if is_instance_valid(graph_controller):
		graph_controller.editor_scale = scale


func cancel_any_active_drags() -> void:
	if is_instance_valid(_action_handler) and _action_handler.has_method(&"on_end_node_move"):
		_action_handler.on_end_node_move()


func edit_graph(path: String) -> void:
	side_panel.add_file_to_open_list(path)
	data_manager.set_active_graph(path)


func select_and_inspect_node(node_id: StringName) -> void:
	var current_graph = data_manager.get_active_graph()
	if not is_instance_valid(current_graph):
		return

	var node_data = current_graph.nodes.get(node_id)
	if is_instance_valid(node_data):
		properties_panel.inspect_node(node_data)


func clear_graph_selection() -> void:
	if not is_instance_valid(graph_controller):
		return
	for node in graph_controller.get_selected_graph_elements():
		node.selected = false
	properties_panel.clear_inspection()


func save_single_file(path: String) -> void:
	if path == data_manager.get_active_graph_path():
		data_manager.save_active_graph()
	else:
		data_manager.save_graph(path)


func validate_open_files_exist() -> void:
	if not is_instance_valid(side_panel):
		return

	side_panel.check_for_moved_files_via_uid()

	var files_to_close: Array[String] = []
	var open_files = side_panel.get_open_files()

	for path in open_files:
		if not FileAccess.file_exists(path):
			if not side_panel.is_uid_valid_for_path(path):
				files_to_close.append(path)

	if not files_to_close.is_empty():
		for path_to_close in files_to_close:
			_handle_bookmark_closure(path_to_close)


func _on_history_changed() -> void:
	var current_graph = data_manager.get_active_graph()
	if not is_instance_valid(current_graph):
		return

	graph_controller.refresh_from_data(current_graph)
	data_manager.notify_dirty_status_if_unsaved()

	if properties_panel.is_visible():
		properties_panel.call_deferred(&"refresh_inspected_node")


func _on_selection_finished_and_popup(node_id: StringName) -> void:
	select_and_inspect_node(node_id)


func _on_graph_editor_gui_input(event: InputEvent) -> void:
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_RIGHT
		and event.is_pressed()
	):
		var graph_pos = graph_controller.get_mouse_position_in_graph()

		_node_factory.show_add_node_menu(graph_pos)
		get_viewport().set_input_as_handled()


func _on_connection_to_empty(
	from_node: StringName, from_port: int, _release_position: Vector2
) -> void:
	var connect_data = {"from_node": from_node, "from_port": from_port}
	var graph_pos = graph_controller.get_mouse_position_in_graph()

	_node_factory.show_add_node_menu(graph_pos, connect_data)


func _on_node_type_selected_from_menu(type_name: String) -> void:
	call_deferred(&"_on_node_type_selected_for_creation", type_name)


func _on_node_ports_changed(node_id: StringName) -> void:
	var current_graph = data_manager.get_active_graph()
	if is_instance_valid(current_graph):
		graph_controller.update_node_ports(current_graph, node_id)


func _create_backdrop_from_selection() -> void:
	var editable_graph = data_manager.make_active_graph_editable()
	if not is_instance_valid(editable_graph):
		return

	var selected_visual_nodes: Array[GraphElement] = graph_controller.get_selected_graph_elements()
	var creation_position = graph_controller.get_mouse_position_in_graph()
	var command = CreateBackdropCommand.new(
		editable_graph, selected_visual_nodes, creation_position
	)
	_history.execute_command(command)


func _on_active_graph_changed(new_graph_resource: QuestGraphResource) -> void:
	_stop_all_debug_tweens()
	graph_controller.display_graph(new_graph_resource)
	side_panel.update_selection(data_manager.get_active_graph_path())
	QWEditorUtils.refresh_quest_id_cache_for_graph(new_graph_resource)

	if is_instance_valid(properties_panel):
		properties_panel.clear_inspection()

	# Restore highlights if live session is active
	if _live_debugging_active:
		_wait_and_restore_highlights()


func _wait_and_restore_highlights() -> void:
	const HIGHLIGHT_RESTORE_FRAME_DELAY := 3
	for i in HIGHLIGHT_RESTORE_FRAME_DELAY:
		await get_tree().process_frame

	_restore_highlights_on_graph_change()


func _on_create_new_file_at_path(path: String) -> void:
	if not Engine.is_editor_hint():
		return
	call_deferred(&"_scan_and_edit_new_graph", path)


func _on_bookmark_selected(path: String) -> void:
	data_manager.set_active_graph(path)


func _on_close_bookmark_requested(path: String) -> void:
	if data_manager.has_unsaved_changes(path):
		var dialog = QWConstants.QuestConfirmationDialogScene.instantiate()
		get_tree().root.add_child(dialog)
		dialog.save_requested.connect(
			func():
				save_single_file(path)
				_handle_bookmark_closure(path)
		)
		dialog.discard_requested.connect(
			func():
				data_manager.discard_changes(path)
				_handle_bookmark_closure(path)
		)
		dialog.prompt(
			"Unsaved Changes",
			"Graph '%s' has unsaved changes. Save before closing?" % path.get_file()
		)
	else:
		_handle_bookmark_closure(path)


func _handle_bookmark_closure(closed_path: String) -> void:
	var was_active = data_manager.get_active_graph_path() == closed_path
	data_manager.close_graph(closed_path)
	side_panel.remove_file_from_open_list(closed_path)

	if was_active:
		var remaining_files = side_panel.get_open_files()
		if not remaining_files.is_empty():
			edit_graph(remaining_files[0])
		else:
			data_manager.set_active_graph("")


func _on_close_all_requested() -> void:
	var open_files: Array[String] = side_panel.get_open_files()
	if open_files.is_empty():
		return

	var unsaved_paths: Array[String] = []
	for path in open_files:
		if data_manager.has_unsaved_changes(path):
			unsaved_paths.append(path)

	if not unsaved_paths.is_empty():
		var dialog = QWConstants.QuestConfirmationDialogScene.instantiate()
		get_tree().root.add_child(dialog)
		dialog.save_requested.connect(
			func():
				_action_handler.save_all_modified_graphs()
				_close_all_files_now()
		)
		dialog.discard_requested.connect(
			func():
				for path in unsaved_paths:
					data_manager.discard_changes(path)
				_close_all_files_now()
		)
		dialog.prompt(
			"Unsaved Changes",
			"%d file(s) have unsaved changes. Save all before closing?" % unsaved_paths.size()
		)
	else:
		_close_all_files_now()


func _close_all_files_now() -> void:
	# get_open_files() returns a copy; iterate over it to safely close all
	var paths_to_close: Array[String] = side_panel.get_open_files()
	for path in paths_to_close:
		data_manager.close_graph(path)
		side_panel.remove_file_from_open_list(path)
	data_manager.set_active_graph("")


func _on_graph_view_changed(scroll_offset: Vector2, zoom: float) -> void:
	data_manager.update_view_state(data_manager.get_active_graph_path(), scroll_offset, zoom)


func _on_graph_was_saved(_path: String) -> void:
	call_deferred(&"_update_quest_registry")
	QWEditorUtils.clear_cache()

	if is_instance_valid(side_panel):
		side_panel.refresh_category_for_path(_path)

	if Engine.is_editor_hint():
		call_deferred(&"_runtime_scan_filesystem")


func _load_session_data() -> void:
	if not is_instance_valid(editor_session_data) or not is_instance_valid(side_panel):
		return

	for path in editor_session_data.open_files:
		if FileAccess.file_exists(path):
			side_panel.add_file_to_open_list(path)

	var last_file = editor_session_data.last_focused_file
	if FileAccess.file_exists(last_file):
		edit_graph(last_file)
	elif not editor_session_data.open_files.is_empty():
		for path in editor_session_data.open_files:
			if FileAccess.file_exists(path):
				edit_graph(path)
				break


func _update_quest_registry() -> void:
	if (
		QWConstants.get_settings().quest_registry_path.is_empty()
		or QWConstants.get_settings().quest_scan_folder.is_empty()
	):
		return

	var registry: QuestRegistry = ResourceLoader.load(
		QWConstants.get_settings().quest_registry_path, "", ResourceLoader.CACHE_MODE_REPLACE
	)
	if not is_instance_valid(registry):
		return

	QuestRegistrar.update_registry_from_project(
		registry, QWConstants.get_settings().quest_scan_folder
	)


func add_visual_node(node_data: GraphNodeResource) -> void:
	if is_instance_valid(graph_controller):
		graph_controller.create_single_visual_node(node_data)


func remove_visual_node(node_id: StringName) -> void:
	if is_instance_valid(graph_controller):
		var node_to_remove = graph_controller.get_node_or_null(NodePath(node_id))
		if is_instance_valid(node_to_remove):
			node_to_remove.queue_free()


func add_visual_connection(
	from_node: StringName, from_port: int, to_node: StringName, to_port: int
) -> void:
	if is_instance_valid(graph_controller):
		graph_controller.add_visual_connection(from_node, from_port, to_node, to_port)


func remove_visual_connection(
	from_node: StringName, from_port: int, to_node: StringName, to_port: int
) -> void:
	if is_instance_valid(graph_controller):
		graph_controller.remove_visual_connection(from_node, from_port, to_node, to_port)


func _on_property_preview_requested(
	node_id: StringName, property_name: String, value: Variant
) -> void:
	if property_name == "title_font_size" and value is int:
		graph_controller.set_backdrop_title_font_size_preview(node_id, value)


# This function is called whenever the ActionHandler confirms that node data has changed.
func _on_node_data_changed(node_id: StringName, action: String) -> void:
	# 1. Full Rebuild Actions (HEAVY)
	var full_rebuild_actions: Array[String] = []

	# 2. Local Structure Actions (Optimized)
	var local_structure_actions = [
		"is_terminal",
		"allow_partial_deposit",
		"add_parallel_output",
		"remove_parallel_output",
		"update_parallel_port_name",
		"add_random_output",
		"remove_random_output",
		"update_random_output_name",
		"add_switch_case",
		"remove_switch_case",
		"update_switch_case_name",
		"add_sync_input",
		"remove_sync_input",
		"update_sync_input_name",
		"add_sync_output",
		"remove_sync_output",
		"update_sync_output_name"
	]

	var current_graph = data_manager.get_active_graph()

	if action in full_rebuild_actions:
		graph_controller.display_graph(current_graph)

	elif action in local_structure_actions:
		graph_controller.update_node_structure_and_connections(node_id)

	else:
		graph_controller.refresh_single_node_visuals(node_id)

	if properties_panel.visible and properties_panel.get_inspected_node_id() == node_id:
		properties_panel.call_deferred(&"refresh_inspected_node")


func _on_validation_requested() -> void:
	var current_graph = data_manager.get_active_graph()
	if not is_instance_valid(current_graph):
		validation_finished.emit([])
		return

	var results: Array[ValidationResult] = validator.validate_graph(current_graph)
	var active_path = data_manager.get_active_graph_path()
	for r in results:
		r.source_quest_path = active_path
	validation_finished.emit(results)


func _on_validation_result_selected(node_id: StringName, source_quest_path: String = "") -> void:
	if node_id.is_empty():
		return

	var need_switch := false
	var active_path = data_manager.get_active_graph_path()
	var source_norm = source_quest_path.simplify_path() if not source_quest_path.is_empty() else ""
	var active_norm = active_path.simplify_path() if not active_path.is_empty() else ""
	if (
		not source_norm.is_empty()
		and source_norm != active_norm
		and FileAccess.file_exists(source_quest_path)
	):
		need_switch = true
		if (
			is_instance_valid(editor_plugin_instance)
			and editor_plugin_instance.has_method(&"make_visible")
		):
			editor_plugin_instance.make_visible(true)
		edit_graph(source_quest_path)
		var node_id_to_focus := node_id
		var expected_path := source_quest_path.simplify_path()
		graph_controller.graph_display_completed.connect(
			_on_graph_display_completed_for_validation.bind(expected_path, node_id_to_focus),
			CONNECT_ONE_SHOT
		)
		return

	var node_to_select = graph_controller.get_node_or_null(NodePath(node_id))
	if not is_instance_valid(node_to_select):
		push_warning("QuestWeaver: Node '%s' not found in current graph." % node_id)
		return

	_focus_validation_result_node(node_id)


func _on_graph_display_completed_for_validation(expected_path: String, node_id: StringName) -> void:
	if data_manager.get_active_graph_path().simplify_path() == expected_path:
		_focus_validation_result_node_with_retry(node_id, 0)


func _focus_validation_result_node(node_id: StringName) -> void:
	_focus_validation_result_node_with_retry(node_id, 0)


## Retries up to 5 times when switching graphs (display_graph is async; nodes may not exist immediately).
func _focus_validation_result_node_with_retry(node_id: String, attempt: int = 0) -> void:
	var node_to_select = graph_controller.get_node_or_null(NodePath(node_id))
	if not is_instance_valid(node_to_select):
		if attempt < 5:
			call_deferred(&"_focus_validation_result_node_with_retry", node_id, attempt + 1)
		else:
			push_warning(
				(
					"QuestWeaver: Node '%s' not found in current graph after %d attempts."
					% [node_id, attempt + 1]
				)
			)
		return

	clear_graph_selection()
	node_to_select.selected = true

	var target_zoom: float = 1.0
	graph_controller.zoom = target_zoom

	var node_center: Vector2 = node_to_select.position_offset + (node_to_select.size / 2.0)
	var viewport_pixel_size: Vector2 = graph_controller.size
	var viewport_graph_size: Vector2 = viewport_pixel_size / target_zoom
	var final_offset: Vector2 = node_center - (viewport_graph_size / 2.0)

	graph_controller.scroll_offset = final_offset


# ==============================================================================
# LIVE DEBUGGING LOGIC
# ==============================================================================


func _init_debug_styles() -> void:
	# ACTIVE (Orange/Gold)
	_live_stylebox = StyleBoxFlat.new()
	_live_stylebox.bg_color = Color(1, 0.6, 0.0, 0.15)
	_live_stylebox.border_color = Color(1, 0.6, 0.0, 1.0)
	_live_stylebox.set_border_width_all(4)
	_live_stylebox.set_corner_radius_all(4)
	_live_stylebox.set_expand_margin_all(4)

	# COMPLETED (Green)
	_completed_stylebox = StyleBoxFlat.new()
	_completed_stylebox.bg_color = Color(0.2, 0.8, 0.2, 0.1)
	_completed_stylebox.border_color = Color(0.2, 0.8, 0.2, 0.8)
	_completed_stylebox.set_border_width_all(2)
	_completed_stylebox.set_corner_radius_all(4)
	_completed_stylebox.set_expand_margin_all(2)

	# FAILED (Red)
	_failed_stylebox = StyleBoxFlat.new()
	_failed_stylebox.bg_color = Color(0.8, 0.2, 0.2, 0.1)
	_failed_stylebox.border_color = Color(0.8, 0.2, 0.2, 0.8)
	_failed_stylebox.set_border_width_all(2)
	_failed_stylebox.set_corner_radius_all(4)
	_failed_stylebox.set_expand_margin_all(2)


func _stop_all_debug_tweens() -> void:
	for t in _active_debug_nodes.values():
		if is_instance_valid(t):
			t.kill()
	_active_debug_nodes.clear()


func _on_debug_session_started():
	_live_debugging_active = true
	_clear_all_highlights()
	_completed_node_ids.clear()
	_failed_node_ids.clear()
	_live_node_ids.clear()
	_stop_all_debug_tweens()


func _on_debug_session_ended():
	_live_debugging_active = false
	_clear_all_highlights()
	_live_node_ids.clear()
	_stop_all_debug_tweens()


func _on_debug_node_activated(node_id: StringName):
	if not _live_debugging_active:
		return
	if _completed_node_ids.has(node_id):
		_completed_node_ids.erase(node_id)

	_live_node_ids[node_id] = true  # remember state

	# Visuals
	_update_node_style(node_id, _live_stylebox)
	_pulse_live_node(node_id)


func _on_debug_node_completed(node_id: StringName):
	if not _live_debugging_active:
		return

	# Stop pulsing tween
	if _active_debug_nodes.has(node_id):
		var t = _active_debug_nodes[node_id]
		if is_instance_valid(t):
			t.kill()
		_active_debug_nodes.erase(node_id)

	if _live_node_ids.has(node_id):
		_live_node_ids.erase(node_id)  # erase from list

	# Mark as completed
	_completed_node_ids[node_id] = true
	_update_node_style(node_id, _completed_stylebox)


func _on_debug_node_failed(node_id: StringName):
	if not _live_debugging_active:
		return

	if _active_debug_nodes.has(node_id):
		var t = _active_debug_nodes[node_id]
		if is_instance_valid(t):
			t.kill()
		_active_debug_nodes.erase(node_id)

	if _live_node_ids.has(node_id):
		_live_node_ids.erase(node_id)

	_failed_node_ids[node_id] = true
	_update_node_style(node_id, _failed_stylebox)


func _on_debug_instance_updated(payload: Dictionary) -> void:
	if not _live_debugging_active:
		return
	var active_path = data_manager.get_active_graph_path()
	if active_path.is_empty():
		return
	var displayed_file_id = StringName(active_path.get_file().get_basename())
	var payload_file_id = str(payload.get("file_id", ""))
	if displayed_file_id != StringName(payload_file_id):
		return
	var active_node_ids: Array = payload.get("active_node_ids", [])
	var new_active_set: Dictionary = {}
	for node_id_str in active_node_ids:
		new_active_set[StringName(node_id_str)] = true
	for node_id in _live_node_ids.keys():
		if not new_active_set.has(node_id):
			if _active_debug_nodes.has(node_id):
				var t = _active_debug_nodes[node_id]
				if is_instance_valid(t):
					t.kill()
				_active_debug_nodes.erase(node_id)
			_live_node_ids.erase(node_id)
			_completed_node_ids[node_id] = true
			_update_node_style(node_id, _completed_stylebox)
	for node_id in new_active_set.keys():
		if not _live_node_ids.has(node_id):
			_live_node_ids[node_id] = true
			if _completed_node_ids.has(node_id):
				_completed_node_ids.erase(node_id)
			_update_node_style(node_id, _live_stylebox)
			_pulse_live_node(node_id)


func _update_node_style(node_id: StringName, style: StyleBox):
	if node_id.is_empty():
		return
	var visual_node = graph_controller.get_node_or_null(NodePath(node_id))
	if is_instance_valid(visual_node) and visual_node is GraphNode:
		visual_node.set("theme_override_styles/panel", style)


func _clear_all_highlights():
	if is_instance_valid(graph_controller):
		for child in graph_controller.get_children():
			if child is GraphNode:
				child.set("theme_override_styles/panel", null)


func _pulse_live_node(node_id: StringName):
	var visual_node = graph_controller.get_node_or_null(NodePath(node_id))
	if not is_instance_valid(visual_node):
		return

	if _active_debug_nodes.has(node_id):
		var existing_tween = _active_debug_nodes[node_id]
		if is_instance_valid(existing_tween) and existing_tween.is_running():
			return

	# Create a unique copy of the stylebox so we don't animate ALL active nodes in sync
	var unique_style: StyleBoxFlat = _live_stylebox.duplicate()
	visual_node.set("theme_override_styles/panel", unique_style)

	var tween = create_tween().set_loops()
	_active_debug_nodes[node_id] = tween

	var start_col = _live_stylebox.border_color
	var end_col = start_col
	end_col.a = 0.3  # Fade out

	var node_ref = weakref(visual_node)

	var tween_callback = func(val: Color):
		var node = node_ref.get_ref()
		if node:
			unique_style.border_color = val
			node.queue_redraw()
	(
		tween
		. tween_method(tween_callback, start_col, end_col, 0.6)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)

	var tween_callback_back = func(val: Color):
		var node = node_ref.get_ref()
		if node:
			unique_style.border_color = val
			node.queue_redraw()
	(
		tween
		. tween_method(tween_callback_back, end_col, start_col, 0.6)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)


func _restore_highlights_on_graph_change():
	# If user switches graph tabs while game is running, restore the visuals
	# 1. Completed & Failed
	for node_id in _completed_node_ids:
		_update_node_style(node_id, _completed_stylebox)
	for node_id in _failed_node_ids:
		_update_node_style(node_id, _failed_stylebox)

	# 2. Active Nodes (Pulsing restart)
	for node_id in _live_node_ids:
		_update_node_style(node_id, _live_stylebox)
		_pulse_live_node(node_id)


# -------


func _scan_and_edit_new_graph(path: String) -> void:
	_runtime_scan_filesystem()

	await get_tree().create_timer(0.1).timeout
	edit_graph(path)


## Internal function to safely access EditorInterface methods when needed.
func _runtime_scan_filesystem() -> void:
	# This function relies on _editor_interface being set, but avoids any type hints.
	if is_instance_valid(_editor_interface):
		_editor_interface.get_resource_filesystem().scan()
