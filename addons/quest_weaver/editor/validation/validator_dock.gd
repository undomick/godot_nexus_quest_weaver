# res://addons/quest_weaver/editor/validation/validator_dock.gd
@tool

class_name QuestWeaverValidator

extends MarginContainer

## Combines validation results (Validate Active / Validate All) with runtime debug category toggles.
## The debug checkboxes (System, Flow, etc.) control which categories appear in the debug overlay
## when running the game with QuestWeaver debugger connected; they are co-located here for
## developer convenience since both are development-time tools.
signal validation_requested

signal result_selected(node_id: StringName, source_quest_path: String)

# Runtime debug overlay categories; used to build the checkbox UI in this dock.
const DEBUG_CATEGORIES = ["System", "Flow", "Executor", "Inventory", "Animation", "SaveLoad"]

var _debug_settings: QuestWeaverDebugSettings

## Callable that returns Array[String] of open quest file paths. Set by plugin.
var _get_open_files: Callable

@onready var validate_button: Button = %ValidateButton

@onready var validate_side_panel_button: Button = %ValidateSidePanelButton

@onready var validate_all_button: Button = %ValidateAllButton

@onready var results_tree: Tree = %ResultsTree

@onready var category_list: VBoxContainer = %CategoryList


func set_open_files_provider(getter: Callable) -> void:
	_get_open_files = getter


func _ready() -> void:
	validate_button.text = "Validate Active Quest"
	validate_side_panel_button.text = "Validate Opened Quests"
	validate_all_button.text = "Validate All Quests"
	validate_all_button.icon = get_theme_icon("Search", "EditorIcons")
	validate_button.icon = get_theme_icon("Search", "EditorIcons")
	validate_side_panel_button.icon = get_theme_icon("Search", "EditorIcons")

	# Configure the results tree columns: Severity, Quest, Message, NodeID
	results_tree.set_column_title(0, "Severity")
	results_tree.set_column_title(1, "Quest")
	results_tree.set_column_title(2, "Message")
	results_tree.set_column_title(3, "NodeID")

	results_tree.set_column_expand(0, false)
	results_tree.set_column_expand(1, true)
	results_tree.set_column_expand(2, true)
	results_tree.set_column_expand(3, false)
	results_tree.set_column_expand_ratio(1, 1)  # Quest: 33%
	results_tree.set_column_expand_ratio(2, 2)  # Message: 66%

	results_tree.set_column_custom_minimum_width(0, 150)
	results_tree.set_column_custom_minimum_width(1, 130)
	results_tree.set_column_custom_minimum_width(2, 180)
	results_tree.set_column_custom_minimum_width(3, 150)

	validate_button.pressed.connect(_on_validate_button_pressed)
	validate_side_panel_button.pressed.connect(_on_validate_side_panel_pressed)
	validate_all_button.pressed.connect(_on_validate_all_button_pressed)
	results_tree.item_selected.connect(_on_results_tree_item_selected)

	# --- Load settings and build the debug UI ---
	_load_debug_settings()
	_build_debug_ui()


# Called externally by the editor to display validation results.
func display_results(results: Array[ValidationResult]) -> void:
	results_tree.clear()
	var root = results_tree.create_item()

	if results.is_empty():
		var item = results_tree.create_item(root)
		item.set_text(2, "Validation successful: No issues found.")
		item.set_icon(0, get_theme_icon("StatusSuccess", "EditorIcons"))
		return

	var error_icon = get_theme_icon("Error", "EditorIcons")
	var warning_icon = get_theme_icon("Warning", "EditorIcons")
	var info_icon = get_theme_icon("Info", "EditorIcons")

	for result in results:
		var item = results_tree.create_item(root)
		var quest_name: String = (
			result.source_quest_path.get_file().get_basename()
			if not result.source_quest_path.is_empty()
			else ""
		)
		item.set_text(1, quest_name)
		item.set_text(2, result.message)
		item.set_text(3, result.node_id)
		var meta = {"node_id": result.node_id, "source_path": result.source_quest_path}
		item.set_metadata(0, meta)

		match result.severity:
			ValidationResult.Severity.ERROR:
				item.set_icon(0, error_icon)
				item.set_text(0, "Error")
			ValidationResult.Severity.WARNING:
				item.set_icon(0, warning_icon)
				item.set_text(0, "Warning")
			ValidationResult.Severity.INFO:
				item.set_icon(0, info_icon)
				item.set_text(0, "Info")

		# Enable text wrapping for columns when space is limited
		for col in range(4):
			item.set_autowrap_mode(col, TextServer.AUTOWRAP_WORD_SMART)


# Forwards the button click signal to the editor.
func _on_validate_button_pressed() -> void:
	validation_requested.emit()


# Validates all quests in the SidePanel (opened files) and displays results.
func _on_validate_side_panel_pressed() -> void:
	var paths: Array[String] = []
	if _get_open_files.is_valid():
		var ret = _get_open_files.call()
		if ret is Array:
			for p in ret:
				if p is String and not p.is_empty():
					paths.append(p)
	if paths.is_empty():
		var warning_result = (
			ValidationResult
			. new(
				ValidationResult.Severity.WARNING,
				"No quests are currently opened in the side panel. Open at least one quest file to validate.",
				&"",
				"",
				""
			)
		)
		display_results([warning_result])
		return
	var validator = QuestValidator.new()
	var results = validator.validate_quests_at_paths(paths)
	validator.free()
	display_results(results)


# Validates all quests in the registry and displays results (no main view required).
func _on_validate_all_button_pressed() -> void:
	var validator = QuestValidator.new()
	var results = validator.validate_all_quests_in_registry()
	validator.free()
	display_results(results)


# Forwards the item selection signal to the editor to focus the node.
func _on_results_tree_item_selected() -> void:
	var selected_item = results_tree.get_selected()
	if not selected_item:
		return

	var meta = selected_item.get_metadata(0)
	var node_id: StringName = &""
	var source_path: String = ""
	if meta is Dictionary:
		node_id = meta.get("node_id", &"")
		source_path = meta.get("source_path", "")
	else:
		push_warning("QuestWeaverValidator: Tree item has invalid metadata for result_selected.")
	if not node_id.is_empty():
		result_selected.emit(node_id, source_path)


# --- DEBUG SETTINGS ---

# Loads the settings resource or creates it if it doesn't exist.


func _load_debug_settings() -> void:
	if ResourceLoader.exists(QWConstants.DEBUG_SETTINGS_PATH):
		_debug_settings = ResourceLoader.load(QWConstants.DEBUG_SETTINGS_PATH)
	else:
		_debug_settings = QuestWeaverDebugSettings.new()
		# Save it immediately so it exists for the next time.
		ResourceSaver.save(_debug_settings, QWConstants.DEBUG_SETTINGS_PATH)

	# Ensure all categories from our master list exist in the settings file.
	# This makes adding new categories in the future easy.
	var settings_changed := false
	for category in DEBUG_CATEGORIES:
		if not _debug_settings.active_categories.has(category):
			_debug_settings.active_categories[category] = true  # Default new categories to 'on'.
			settings_changed = true

	if settings_changed:
		ResourceSaver.save(_debug_settings, QWConstants.DEBUG_SETTINGS_PATH)


# Creates the CheckBox controls dynamically based on the master list.
func _build_debug_ui() -> void:
	for child in category_list.get_children():
		child.queue_free()

	for category in DEBUG_CATEGORIES:
		var checkbox = CheckBox.new()
		checkbox.text = category
		checkbox.button_pressed = _debug_settings.active_categories.get(category, true)
		# When a checkbox is toggled, call the handler function.
		checkbox.toggled.connect(_on_debug_category_toggled.bind(category))
		category_list.add_child(checkbox)


# Called when any checkbox is toggled by the user.
func _on_debug_category_toggled(is_pressed: bool, category: String) -> void:
	if not is_instance_valid(_debug_settings):
		return

	# Update the value in our settings resource...
	_debug_settings.active_categories[category] = is_pressed
	# ...and save the change back to the .tres file immediately.
	ResourceSaver.save(_debug_settings, QWConstants.DEBUG_SETTINGS_PATH)
