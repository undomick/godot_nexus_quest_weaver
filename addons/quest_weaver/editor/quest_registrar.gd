# res://addons/quest_weaver/editor/quest_registrar.gd
@tool
class_name QuestRegistrar
extends RefCounted

const MAX_SCAN_FILES := 2000


static func update_registry_from_project(registry: QuestRegistry, scan_folder: String) -> void:
	if not is_instance_valid(registry):
		push_error("QuestRegistrar: The provided QuestRegistry resource is invalid.")
		return

	if scan_folder.is_empty() or not scan_folder.begins_with("res://"):
		push_warning("QuestRegistrar: The 'Scan Folder' is not configured or invalid.")
		return

	if not DirAccess.dir_exists_absolute(scan_folder):
		push_warning("QuestRegistrar: The specified scan folder '%s' does not exist." % scan_folder)
		return

	# Temporary dictionary to collect results
	var new_map: Dictionary = {}
	var files_scanned := 0

	var directories_to_scan: Array[String] = [scan_folder]

	while not directories_to_scan.is_empty():
		if files_scanned >= MAX_SCAN_FILES:
			push_warning(
				(
					"QuestRegistrar: Scan limited to %d files. Some quests may be omitted."
					% MAX_SCAN_FILES
				)
			)
			break

		var current_dir_path = directories_to_scan.pop_front()

		var dir = DirAccess.open(current_dir_path)
		if not dir:
			continue

		dir.list_dir_begin()
		var item_name = dir.get_next()
		while item_name != "":
			if item_name == "." or item_name == "..":
				item_name = dir.get_next()
				continue

			var full_path = current_dir_path.path_join(item_name)

			if dir.current_is_dir():
				directories_to_scan.push_back(full_path)

			elif full_path.ends_with("." + QWConstants.FILE_EXTENSION):
				var file_id = item_name.get_basename()
				new_map[file_id] = full_path
				files_scanned += 1

				_scan_file_for_id(full_path, new_map)

			item_name = dir.get_next()
		dir.list_dir_end()

	# Update Registry
	if registry.quest_path_map.hash() != new_map.hash():
		registry.quest_path_map = new_map
		if not registry.resource_path.is_empty():
			var save_error = ResourceSaver.save(registry, registry.resource_path)
			if save_error != OK:
				push_error(
					(
						"QuestRegistrar: Failed to save the Quest Registry! Error: %s"
						% error_string(save_error)
					)
				)


static func _scan_file_for_id(file_path: String, out_map: Dictionary) -> void:
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return

	var data = file.get_var(true)
	file.close()

	if data is Dictionary and data.has("nodes"):
		var nodes_data = data.get("nodes", {})
		if not nodes_data is Dictionary:
			return

		for node_id in nodes_data:
			var node_data = nodes_data[node_id]
			if not node_data is Dictionary:
				continue
			var script_path = node_data.get("@script_path")

			if script_path == QWConstants.QUEST_CONTEXT_NODE_SCRIPT_PATH:
				var quest_id = node_data.get("quest_id", "")

				if not quest_id.is_empty():
					# If LogicID differs from FileID, map it too
					if out_map.has(quest_id) and out_map[quest_id] != file_path:
						push_warning(
							(
								"QuestRegistrar: Duplicate ID collision! '%s' exists in '%s' and '%s'."
								% [quest_id, out_map[quest_id], file_path]
							)
						)

					out_map[quest_id] = file_path
