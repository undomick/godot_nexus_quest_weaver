# res://addons/quest_weaver/editor/dialogs/quest_file_dialog.gd
@tool
class_name QuestFileDialog
extends FileDialog

signal path_confirmed(path: String)

enum QuestDialogMode { OPEN_FILE, NEW_FILE }


func _ready() -> void:
	file_selected.connect(_on_dialog_file_selected)
	canceled.connect(queue_free)


func show_for_mode(p_mode: QuestDialogMode, start_dir: String = "res://") -> void:
	match p_mode:
		QuestDialogMode.OPEN_FILE:
			file_mode = FileDialog.FILE_MODE_OPEN_FILE
			title = "Open Quest"
		QuestDialogMode.NEW_FILE:
			file_mode = FileDialog.FILE_MODE_SAVE_FILE
			title = "Create New Quest"
		_:
			file_mode = FileDialog.FILE_MODE_OPEN_FILE
			title = "Open Quest"

	filters = ["*.quest ; Quest Graph File"]
	current_dir = start_dir
	popup_centered()


func _on_dialog_file_selected(path: String) -> void:
	if get_file_mode() == FILE_MODE_SAVE_FILE and not path.ends_with(".quest"):
		path += ".quest"

	path_confirmed.emit(path)
	queue_free()
