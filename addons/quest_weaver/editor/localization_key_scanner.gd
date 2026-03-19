# res://addons/quest_weaver/editor/localization_key_scanner.gd
@tool
class_name LocalizationKeyScanner
extends RefCounted


## Analyzes the project, reads the existing CSV, adds missing columns/keys, and rewrites the file.
static func update_localization_file(
	scan_folder: String, csv_path: String, target_languages: Array[String]
) -> void:
	if scan_folder.is_empty() or csv_path.is_empty():
		push_warning("Key Scanner: Scan folder or CSV path not configured in settings.")
		return

	if target_languages.is_empty():
		push_warning("Key Scanner: No supported languages defined in settings. Defaulting to 'en'.")
		target_languages = ["en"]

	# 1. Collect all keys currently used in Quest Files
	var found_quest_keys: Dictionary = _scan_all_quest_files(scan_folder)

	# 2. Read the existing CSV data (if it exists) to preserve manual translations
	# Format: { "KEY_ID": { "en": "Text", "de": "Text" } }
	var existing_data: Dictionary = {}
	if FileAccess.file_exists(csv_path):
		existing_data = _read_existing_csv(csv_path)

	# 3. Merge found keys into existing data
	var added_key_count = 0
	for key in found_quest_keys:
		if not existing_data.has(key):
			existing_data[key] = {}  # New entry, no translations yet
			added_key_count += 1

	# 4. Write everything back to disk (handling new columns automatically)
	var success = _write_merged_csv(csv_path, existing_data, target_languages)

	if success:
		print("[Key Scanner] CSV updated successfully.")
		print("    - Target Languages: %s" % str(target_languages))
		print("    - Total Keys: %d" % existing_data.size())
		if added_key_count > 0:
			print("    - New Keys Added: %d" % added_key_count)
	else:
		push_error("Key Scanner: Failed to write CSV file.")


# --- STEP 1: SCANNING ---


static func _scan_all_quest_files(root_path: String) -> Dictionary:
	var found_strings: Dictionary = {}
	var directories_to_scan := [root_path]

	while not directories_to_scan.is_empty():
		var current_dir_path = directories_to_scan.pop_front()
		var dir = DirAccess.open(current_dir_path)
		if not dir:
			continue

		for item_name in dir.get_files():
			var full_path = current_dir_path.path_join(item_name)
			if full_path.ends_with("." + QWConstants.FILE_EXTENSION):
				_scan_single_file(full_path, found_strings)

		for item_name in dir.get_directories():
			directories_to_scan.push_back(current_dir_path.path_join(item_name))

	return found_strings


static func _scan_single_file(path: String, results: Dictionary):
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return
	var data = file.get_var(true)
	file.close()

	if not data is Dictionary or not data.has("nodes"):
		return

	for node_data in data.get("nodes").values():
		var script_path = node_data.get("@script_path", "").get_file().replace(".gd", "")

		if QWConstants.TRANSLATABLE_FIELDS.has(script_path):
			for field_name in QWConstants.TRANSLATABLE_FIELDS[script_path]:
				var text = node_data.get(field_name, "")
				if not text.is_empty():
					results[text] = true

		if script_path == "task_node_resource":
			for objective_data in node_data.get("objectives", []):
				var text = objective_data.get("description", "")
				if not text.is_empty():
					results[text] = true


# --- STEP 2: READING ---


static func _read_existing_csv(path: String) -> Dictionary:
	var data = {}
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return data

	# Header: ["keys", "en", "de", ...]
	var headers = file.get_csv_line()

	# Determine mapping: index -> language code
	var lang_indices = {}
	for i in range(1, headers.size()):  # Skip index 0 ("keys")
		lang_indices[i] = headers[i]

	while not file.eof_reached():
		var line = file.get_csv_line()
		if line.size() < 1:
			continue

		var key = line[0]
		if key.is_empty():
			continue

		data[key] = {}

		# Read existing translations
		for i in range(1, line.size()):
			if lang_indices.has(i):
				var lang_code = lang_indices[i]
				data[key][lang_code] = line[i]

	return data


# --- STEP 3: WRITING (MERGE) ---


static func _write_merged_csv(path: String, data: Dictionary, languages: Array[String]) -> bool:
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		var err = FileAccess.get_open_error()
		if err == ERR_FILE_ALREADY_IN_USE or err == ERR_UNAVAILABLE:
			push_warning(
				(
					"Key Scanner: Could not write to '%s'. The file is currently open in another program (e.g. Excel/LibreOffice). Please close it and try again."
					% path.get_file()
				)
			)
		else:
			push_error("Key Scanner: Could not open file for writing. Error Code: %d" % err)
		return false

	# 1. Write Header
	var header_row = PackedStringArray(["keys"])
	header_row.append_array(languages)
	file.store_csv_line(header_row)

	# 2. Write Rows
	# (Sorting keys ensures git-friendly diffs and stable order)
	var sorted_keys = data.keys()
	sorted_keys.sort()

	for key in sorted_keys:
		var row = PackedStringArray([key])
		var translations = data[key]

		for lang in languages:
			# If we have an existing translation, keep it.
			# If not (new language column added), use the key as default.
			var text_value = key
			if translations.has(lang) and not translations[lang].is_empty():
				text_value = translations[lang]

			row.append(text_value)

		file.store_csv_line(row)

	return true
