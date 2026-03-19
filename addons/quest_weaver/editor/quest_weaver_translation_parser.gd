@tool
class_name QuestWeaverTranslationParser
extends EditorTranslationParserPlugin

## Integrates Quest Weaver .quest files into Godot's standard localization pipeline.
## Extracts translatable strings from quest nodes (titles, descriptions, messages, etc.)
## so Project -> Localization can pick them up automatically.


func _parse_file(path: String) -> Array:
	var msgids: Array[PackedStringArray] = []
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return msgids

	var data = file.get_var(true)
	if file.get_error() != OK:
		push_warning("QuestWeaverTranslationParser: Failed to read file '%s'." % path)
		file.close()
		return msgids
	file.close()

	if not data is Dictionary or not data.has("nodes"):
		return msgids

	var nodes_data = data.get("nodes", {})
	if not nodes_data is Dictionary:
		return msgids
	for node_data in nodes_data.values():
		if not node_data is Dictionary:
			continue
		var script_path = str(node_data.get("@script_path", "")).get_file().replace(".gd", "")

		if QWConstants.TRANSLATABLE_FIELDS.has(script_path):
			for field_name in QWConstants.TRANSLATABLE_FIELDS[script_path]:
				var text = str(node_data.get(field_name, "")).strip_edges()
				if not text.is_empty():
					msgids.append(PackedStringArray([text]))

		if script_path == "task_node_resource":
			var objectives = node_data.get("objectives", [])
			if objectives is Array:
				for objective_data in objectives:
					if objective_data is Dictionary:
						var description = str(objective_data.get("description", "")).strip_edges()
						if not description.is_empty():
							msgids.append(PackedStringArray([description]))

	return msgids


func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray([QWConstants.FILE_EXTENSION])
