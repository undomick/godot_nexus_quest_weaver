# res://addons/quest_weaver/editor/qw_input_handler.gd
@tool
class_name QWInputHandler
extends Node

var _editor: QuestWeaverEditor
var _history: QWEditorHistory
var _action_handler: QWActionHandler
var _graph_controller: QuestWeaverGraphController
var _editor_interface  # Removed type hint 'EditorInterface'


func initialize(
	p_editor: QuestWeaverEditor,
	p_history: QWEditorHistory,
	p_action_handler: QWActionHandler,
	p_graph_controller: QuestWeaverGraphController,
	p_editor_interface
):
	self._editor = p_editor
	self._history = p_history
	self._action_handler = p_action_handler
	self._graph_controller = p_graph_controller
	self._editor_interface = p_editor_interface


func handle_event(event: InputEvent) -> bool:
	if not _editor_has_focus():
		return false

	if not (event is InputEventKey and event.is_pressed() and not event.is_echo()):
		return false

	var key_event := event as InputEventKey
	var is_command_pressed = key_event.is_command_or_control_pressed()

	# When a LineEdit/TextEdit has focus, only let Ctrl+Z/Y through so they go to history, not the control.
	if _is_text_input_focused():
		if not (is_command_pressed and (key_event.keycode == KEY_Z or key_event.keycode == KEY_Y)):
			return false

	if is_command_pressed:
		match key_event.keycode:
			KEY_S:
				_action_handler.save_all_modified_graphs()
				return true
			KEY_C:
				_action_handler.copy_selection_to_clipboard()
				return true
			KEY_V:
				_action_handler.paste_from_clipboard()
				return true
			KEY_Z:
				if _history.has_undo():
					_history.undo()
				# Always consume so LineEdit/TextEdit does not steal Undo; multiple Undos work.
				return true
			KEY_Y:
				if _history.has_redo():
					_history.redo()
				# Always consume so LineEdit/TextEdit does not steal Redo; multiple Redos work.
				return true

	if key_event.keycode == KEY_DELETE:
		var selected_node_ids: Array[StringName] = _graph_controller.get_selected_node_ids()
		if not selected_node_ids.is_empty():
			_action_handler.on_nodes_deleted(selected_node_ids)
			return true

	return false


func _is_text_input_focused() -> bool:
	if not is_instance_valid(_editor_interface):
		return false

	var focus_owner: Control = (
		_editor_interface.get_editor_main_screen().get_viewport().gui_get_focus_owner()
	)
	return focus_owner is LineEdit or focus_owner is TextEdit


func _editor_has_focus() -> bool:
	var focus_owner = _editor.get_viewport().gui_get_focus_owner()
	if not is_instance_valid(focus_owner):
		return false

	var current_node = focus_owner
	while is_instance_valid(current_node):
		if current_node == _editor:
			return true

		current_node = current_node.get_parent()
	return false
