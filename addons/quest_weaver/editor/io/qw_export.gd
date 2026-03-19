# res://addons/quest_weaver/editor/io/qw_export.gd
@tool
class_name QuestWeaverExportPlugin
extends EditorExportPlugin

## Placeholder for future QuestWeaver-specific export handling.
## .quest files are exported as-is by Godot's default behavior.
## This hook can be used later for e.g. validation or format conversion on export.


func _get_name() -> String:
	return "QuestWeaverExport"


func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
	if path.ends_with(".quest"):
		pass
