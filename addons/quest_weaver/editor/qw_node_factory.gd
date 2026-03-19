# res://addons/quest_weaver/editor/qw_node_factory.gd
@tool
class_name QWNodeFactory
extends Node

# Signal to request backdrop creation.
# This logic involves reading the selection from the GraphController,
# which is handled by the main editor logic.
signal create_backdrop_requested

# --- Dependencies ---
var _node_registry: NodeTypeRegistry
var _data_manager: QWGraphData
var _history: QWEditorHistory
var _graph_controller: QuestWeaverGraphController
var _add_node_menu: NodeSelectionMenu
var _editor: QuestWeaverEditor  # Reference to the main editor for selection/inspection logic

# --- State ---
var _pending_node_creation_pos: Vector2  # Position for the new node
var _pending_connection_data: Dictionary  # Connection data for the new node
var _is_initialized := false  # Flag to check if the node factory is initialized
var _pending_selected_visual_nodes: Array[GraphElement] = []  # Selection at menu open (right-click); used for Backdrop so selection isn't lost when menu gets focus.


func initialize(
	p_editor: QuestWeaverEditor,
	p_registry: NodeTypeRegistry,
	p_data_manager: QWGraphData,
	p_history: QWEditorHistory,
	p_graph_controller: QuestWeaverGraphController,
	p_menu: NodeSelectionMenu
) -> void:
	self._editor = p_editor
	self._node_registry = p_registry
	self._data_manager = p_data_manager
	self._history = p_history
	self._graph_controller = p_graph_controller
	self._add_node_menu = p_menu

	if not _add_node_menu.is_connected("node_selected", _on_node_selected_from_menu):
		_add_node_menu.node_selected.connect(_on_node_selected_from_menu)


func show_add_node_menu(graph_position: Vector2, connect_from_data: Dictionary = {}) -> void:
	if not _is_initialized:
		_add_node_menu.set_available_nodes(_node_registry.node_types)
		_is_initialized = true

	_pending_node_creation_pos = graph_position
	_pending_connection_data = connect_from_data
	# Snapshot selection now; right-click may have already cleared it, so fall back to last stored selection.
	_pending_selected_visual_nodes.clear()
	for node in _graph_controller.get_children():
		if node is GraphElement and node.selected:
			_pending_selected_visual_nodes.append(node)
	if _pending_selected_visual_nodes.is_empty():
		for node in _graph_controller.get_last_selected_visual_nodes():
			if (
				is_instance_valid(node)
				and is_instance_valid(node.get_parent())
				and node.get_parent() == _graph_controller
			):
				_pending_selected_visual_nodes.append(node)

	_add_node_menu.popup(Rect2i(get_viewport().get_mouse_position(), Vector2.ZERO))


func _on_node_selected_from_menu(type_name: StringName) -> void:
	# Use call_deferred to ensure the menu is closed and the editor state is stable
	# before proceeding with the complex node creation logic.
	call_deferred(&"_create_new_node", type_name)


func _create_new_node(type_name: StringName) -> void:
	var editable_graph = _data_manager.make_active_graph_editable()
	if not is_instance_valid(editable_graph):
		return

	# Backdrop wraps the nodes selected by right-click (snapshot from show_add_node_menu).
	if type_name == "Backdrop":
		var backdrop_cmd = CreateBackdropCommand.new(
			editable_graph, _pending_selected_visual_nodes, _pending_node_creation_pos
		)
		_history.execute_command(backdrop_cmd)
		_pending_connection_data.clear()
		_graph_controller.set_is_connecting(false)
		await get_tree().process_frame
		var backdrop_id = backdrop_cmd.get_created_backdrop_id()
		if not backdrop_id.is_empty():
			_editor.select_and_inspect_node(backdrop_id)
		return

	var node_script = _node_registry.get_script_for_name(type_name)
	if not is_instance_valid(node_script):
		return

	# Create and execute the command to add the node to the graph.
	var command = QWActionHandler.CreateNodeCommand.new(
		_editor, editable_graph, node_script, _pending_node_creation_pos, _pending_connection_data
	)
	_history.execute_command(command)

	# Clean up the state after the command has been created.
	_pending_connection_data.clear()

	# Disable the connecting line visual aid in the graph controller.
	_graph_controller.set_is_connecting(false)

	await get_tree().process_frame

	# Use the ID from the command (it generates the ID in execute())
	var created_id = command.get_created_node_id()
	if not created_id.is_empty():
		_editor.select_and_inspect_node(created_id)
