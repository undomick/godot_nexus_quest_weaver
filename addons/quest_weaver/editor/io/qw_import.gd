# res://addons/quest_weaver/editor/io/qw_import.gd
@tool
class_name QuestWeaverImportPlugin
extends EditorImportPlugin


func _get_importer_name() -> String:
	return "quest_weaver.importer"


func _get_visible_name() -> String:
	return "Quest Graph"


func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray([QWConstants.FILE_EXTENSION])


func _get_save_extension() -> String:
	return "tres"


func _get_resource_type() -> String:
	return "Resource"


func _get_resource_icon(_path: String) -> Texture2D:
	return load(QWConstants.ICON_PATH)


func _get_priority() -> float:
	return 1.0


func _get_import_order() -> int:
	return 0


func _get_preset_count() -> int:
	return 0


func _get_import_options(_path: String, _preset_index: int) -> Array[Dictionary]:
	return []


func _import(
	source_file: String,
	save_path: String,
	_options: Dictionary,
	_platform_variants: Array[String],
	_gen_files: Array[String]
) -> Error:
	var file = FileAccess.open(source_file, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()

	var data = file.get_var(true)
	file.close()

	if not data is Dictionary:
		push_error("QuestWeaver Importer: File '%s' has an invalid format." % source_file)
		return ERR_PARSE_ERROR

	var quest_graph_resource = QuestGraphResource.new()
	quest_graph_resource.from_dictionary(data)

	if quest_graph_resource.nodes.is_empty():
		push_error("QuestWeaver Importer: File '%s' produced no valid nodes." % source_file)
		return ERR_PARSE_ERROR

	var full_save_path = "%s.%s" % [save_path, _get_save_extension()]

	var err = ResourceSaver.save(quest_graph_resource, full_save_path)
	if err != OK:
		push_error(
			"QuestWeaver Importer: Was unable to store resource under '%s'." % full_save_path
		)
		return err

	return OK
