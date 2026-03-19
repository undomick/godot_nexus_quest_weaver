# res://addons/quest_weaver/editor/qw_editor_history.gd
@tool
class_name QWEditorHistory
extends RefCounted

signal version_changed

var _undo_stack: Array[EditorCommand] = []
var _redo_stack: Array[EditorCommand] = []
var _editor: QuestWeaverEditor


func initialize(p_editor: QuestWeaverEditor) -> void:
	self._editor = p_editor


func execute_command(command: EditorCommand) -> void:
	command.execute()
	_undo_stack.push_back(command)
	_redo_stack.clear()

	if not command is QWActionHandler.MoveNodesCommand:
		version_changed.emit()


func undo() -> void:
	if _undo_stack.is_empty():
		return

	var command: EditorCommand = _undo_stack.pop_back()
	command.undo()
	_redo_stack.push_back(command)
	version_changed.emit()


func redo() -> void:
	if _redo_stack.is_empty():
		return

	var command: EditorCommand = _redo_stack.pop_back()
	command.execute()
	_undo_stack.push_back(command)
	version_changed.emit()


func has_undo() -> bool:
	return not _undo_stack.is_empty()


func has_redo() -> bool:
	return not _redo_stack.is_empty()


## Call before shutdown to break refs and avoid UndoRedo leak on editor exit.
func cleanup() -> void:
	_undo_stack.clear()
	_redo_stack.clear()
	_editor = null
