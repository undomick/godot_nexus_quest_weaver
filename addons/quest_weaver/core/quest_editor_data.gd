# res://addons/quest_weaver/core/quest_editor_data.gd
@tool
class_name QuestEditorData
extends Resource

## Persists editor session state: open quest files and last focused file.
## Used by the plugin and side panel to restore tabs on editor restart.
##
## Paths to quest files currently open in the editor.
@export var open_files: Array[String] = []
## Path of the quest file that had focus when the editor was closed.
@export var last_focused_file: String = ""
