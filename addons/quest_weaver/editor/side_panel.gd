# res://addons/quest_weaver/editor/side_panel.gd
@tool

extends VBoxContainer

signal create_new_file_at_path(path: String)

signal open_file_requested(path: String)

signal bookmark_selected(path: String)

signal close_bookmark_requested(path: String)

signal close_all_requested

signal save_active_graph_requested

signal save_single_file_requested(path: String)

signal save_all_files_requested

# Styling
const CATEGORY_COLOR = Color(0.4, 0.6, 0.9)

const _ICON_QUEST = preload("res://addons/quest_weaver/assets/icons/icon.svg")

const _ICON_SAVE_ALL = preload("res://addons/quest_weaver/assets/icons/save_all.svg")

const _START_NODE_SCRIPT = preload(
	"res://addons/quest_weaver/nodes/common/start_node/start_node_resource.gd"
)

# Context Menu IDs (0-9: File Ops, 10-19: Category Ops, 20-29: Utilities)
const CMID_CLOSE_CATEGORY := 10

const CMID_CLOSE_OTHER_CATEGORIES := 11

const CMID_COLLAPSE_OTHER_CATEGORIES := 12

const CMID_SHOW_IN_FILESYSTEM := 20

const MAX_SCAN_FILES := 500

const MAX_CATEGORY_PREFETCH := 32

var data_manager: QWGraphData

var open_dir_dialog: FileDialog

# Internal State
var _open_files: Array[String] = []

var _category_cache: Dictionary = {}  # Path -> Category String

var _tree_items_by_path: Dictionary = {}  # Path -> TreeItem

var _category_collapse_state: Dictionary = {}  # Category name -> collapsed (true/false), persisted across redraws

var _context_menu_target_path: String = ""

var _context_menu_target_category: String = ""

var _icon_quest: Texture2D

var _icon_folder: Texture2D

var _search_icon: Texture2D

var _clear_icon: Texture2D

var _open_files_uids: Dictionary = {}  # { int(UID) : String(Path) }

var _path_to_uid: Dictionary = {}  # { String(Path) : int(UID) } for O(1) lookup

var _editor_interface_ref = null  # type Variant for avoiding parsing error in exported game

var _filter_debounce_timer: Timer = null

var _file_list_debounce_timer: Timer = null

# UI References
@onready var tree: Tree = %QuestTree

@onready var filter_edit: LineEdit = %FilterEdit

@onready var context_menu: PopupMenu = %ContextMenu

@onready var open_file_dialog: FileDialog = $OpenFileDialog

@onready var quick_create_edit: LineEdit = %QuickCreateEdit

# Buttons
@onready var new_button: Button = %NewButton

@onready var open_button: Button = %OpenButton

@onready var open_dir_button: Button = %OpenDirButton

@onready var save_button: Button = %SaveButton

@onready var save_all_button: Button = %SaveAllButton

@onready var localization_button: Button = %LocalizationButton

@onready var donate_button: Button = %DonateButton

@onready var docs_button: Button = %DocsButton


func initialize(p_data_manager: QWGraphData, p_editor_interface = null) -> void:
	self.data_manager = p_data_manager
	self._editor_interface_ref = p_editor_interface


func _ready() -> void:
	if not is_instance_valid(tree):
		push_error("SidePanel: %QuestTree node missing. Please update side_panel.tscn")
		return

	tree.allow_rmb_select = true

	_init_dir_dialog()
	_init_filter_debounce()
	_init_file_list_debounce()
	_load_icons()
	_setup_ui_connections()
	_build_context_menu()

	tree.set_drag_forwarding(
		Callable(self, "_tree_get_drag_data"),
		Callable(self, "_tree_can_drop_data"),
		Callable(self, "_tree_drop_data")
	)  # drag & drop

	# Initial draw
	_redraw_tree()


func _init_filter_debounce() -> void:
	_filter_debounce_timer = Timer.new()
	_filter_debounce_timer.one_shot = true
	_filter_debounce_timer.wait_time = 0.15
	_filter_debounce_timer.timeout.connect(_on_filter_debounce_timeout)
	add_child(_filter_debounce_timer)


func _init_file_list_debounce() -> void:
	_file_list_debounce_timer = Timer.new()
	_file_list_debounce_timer.one_shot = true
	_file_list_debounce_timer.wait_time = 0.1
	_file_list_debounce_timer.timeout.connect(_on_file_list_debounce_timeout)
	add_child(_file_list_debounce_timer)


func _request_tree_redraw() -> void:
	_file_list_debounce_timer.stop()
	_file_list_debounce_timer.start()


func _on_file_list_debounce_timeout() -> void:
	_redraw_tree()


func _init_dir_dialog() -> void:
	open_dir_dialog = FileDialog.new()
	open_dir_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	open_dir_dialog.access = FileDialog.ACCESS_RESOURCES
	open_dir_dialog.title = "Open All Quests in Folder"
	add_child(open_dir_dialog)
	open_dir_dialog.dir_selected.connect(_on_folder_selected_to_load)


func _load_icons() -> void:
	_icon_quest = _ICON_QUEST
	_icon_folder = get_theme_icon("Folder", "EditorIcons")
	_search_icon = get_theme_icon("Search", "EditorIcons")
	_clear_icon = get_theme_icon("Close", "EditorIcons")

	new_button.icon = get_theme_icon("New", "EditorIcons")
	open_button.icon = get_theme_icon("Load", "EditorIcons")
	open_dir_button.icon = get_theme_icon("Filesystem", "EditorIcons")
	save_button.icon = get_theme_icon("Save", "EditorIcons")
	save_all_button.icon = _ICON_SAVE_ALL
	localization_button.icon = get_theme_icon("Translation", "EditorIcons")
	docs_button.icon = get_theme_icon("Help", "EditorIcons")

	filter_edit.right_icon = _search_icon


func _setup_ui_connections() -> void:
	save_button.disabled = true
	save_all_button.disabled = true

	new_button.pressed.connect(_on_new_button_toggled)
	open_button.pressed.connect(func(): open_file_dialog.popup_centered())
	open_dir_button.pressed.connect(func(): open_dir_dialog.popup_centered(Vector2i(800, 600)))
	save_button.pressed.connect(save_active_graph_requested.emit)
	save_all_button.pressed.connect(save_all_files_requested.emit)
	localization_button.pressed.connect(_on_scan_keys_pressed)
	donate_button.pressed.connect(func(): OS.shell_open("https://ko-fi.com/jundrie"))
	docs_button.pressed.connect(
		func(): OS.shell_open("https://github.com/undomick/godot_nexus_quest_weaver/wiki")
	)

	filter_edit.text_changed.connect(_on_filter_text_changed)
	filter_edit.gui_input.connect(_on_filter_gui_input)

	tree.item_activated.connect(_on_tree_item_activated)  # Double click
	tree.item_mouse_selected.connect(_on_tree_item_mouse_selected)  # Right click logic
	tree.empty_clicked.connect(func(_pos, _btn): tree.deselect_all())

	quick_create_edit.visible = false
	quick_create_edit.text_submitted.connect(_on_quick_create_submitted)
	quick_create_edit.focus_exited.connect(func(): quick_create_edit.hide())

	context_menu.id_pressed.connect(_on_context_menu_id_pressed)

	open_file_dialog.file_selected.connect(open_file_requested.emit)


# ==============================================================================
# TREE BUILDING & LOGIC
# ==============================================================================


func _on_new_button_toggled() -> void:
	quick_create_edit.visible = !quick_create_edit.visible
	if quick_create_edit.visible:
		quick_create_edit.clear()
		quick_create_edit.grab_focus()


func _on_quick_create_submitted(new_name: String) -> void:
	if new_name.is_empty():
		quick_create_edit.hide()
		return

	# Sanitize name
	new_name = new_name.to_snake_case()
	if not new_name.ends_with(".quest"):
		new_name += ".quest"

	# Determine folder
	var settings = QWConstants.get_settings()
	var folder = "res://"
	if settings and not settings.quest_scan_folder.is_empty():
		folder = settings.quest_scan_folder

	# Create directory if missing
	if not DirAccess.dir_exists_absolute(folder):
		DirAccess.make_dir_recursive_absolute(folder)

	var full_path = folder.path_join(new_name)

	# Check duplicate
	if FileAccess.file_exists(full_path):
		push_warning("QuestWeaver: File '%s' already exists." % full_path)
		return

	# Create Valid Resource
	var new_res = QuestGraphResource.new()

	# Optionally: Add a StartNode immediately so it has a valid structure
	if _START_NODE_SCRIPT:
		var start_node = _START_NODE_SCRIPT.new()
		start_node.id = "start_node"
		start_node.graph_position = Vector2(100, 100)
		# Ensure it's Uncategorized initially or explicit
		start_node.graph_category = "Uncategorized"
		new_res.nodes["start_node"] = start_node

	var file = FileAccess.open(full_path, FileAccess.WRITE)
	if file == null:
		push_error(
			(
				"QuestWeaver: Could not create file at '%s'. Error: %s"
				% [full_path, error_string(FileAccess.get_open_error())]
			)
		)
		return

	# Store the dictionary representation directly, matching QWFormat logic.
	file.store_var(new_res.to_dictionary(), true)
	file.close()

	quick_create_edit.hide()
	if is_instance_valid(_editor_interface_ref):
		_editor_interface_ref.get_resource_filesystem().scan()
	call_deferred(&"_safe_open_new_file", full_path)


func _on_scan_keys_pressed() -> void:
	if not Engine.is_editor_hint():
		return

	var settings = QWConstants.get_settings()
	if not settings:
		return

	LocalizationKeyScanner.update_localization_file(
		settings.quest_scan_folder, settings.localization_csv_path, settings.supported_locales
	)

	# Refresh FileSystem dock
	if is_instance_valid(_editor_interface_ref):
		_editor_interface_ref.get_resource_filesystem().scan()


func get_open_files() -> Array[String]:
	return _open_files.duplicate()


func _safe_open_new_file(path: String) -> void:
	var attempts = 0
	while not ResourceLoader.exists(path) and attempts < 10:
		await get_tree().create_timer(0.1).timeout
		attempts += 1

	if ResourceLoader.exists(path):
		create_new_file_at_path.emit(path)
		_update_category_cache(path)
		_redraw_tree()
	else:
		push_error("QuestWeaver: Created file not found after waiting: " + path)


func add_file_to_open_list(path: String) -> void:
	if path.is_empty():
		return
	if not _open_files.has(path):
		_open_files.append(path)

		var uid = ResourceLoader.get_resource_uid(path)

		if uid != -1:
			_open_files_uids[uid] = path
			_path_to_uid[path] = uid

		_update_category_cache(path)
	_request_tree_redraw()


func remove_file_from_open_list(path: String) -> void:
	if _open_files.has(path):
		_open_files.erase(path)
		_category_cache.erase(path)

		if _path_to_uid.has(path):
			var uid = _path_to_uid[path]
			_open_files_uids.erase(uid)
			_path_to_uid.erase(path)

		_request_tree_redraw()


func check_for_moved_files_via_uid() -> void:
	var redraw_needed = false
	var uids = _open_files_uids.keys()

	for uid in uids:
		var old_path = _open_files_uids[uid]

		if ResourceUID.has_id(uid):
			var current_real_path = ResourceUID.get_id_path(uid)

			if current_real_path != old_path and not current_real_path.is_empty():
				# 1. Update UID Cache
				_open_files_uids[uid] = current_real_path
				if _path_to_uid.has(old_path):
					_path_to_uid.erase(old_path)
				_path_to_uid[current_real_path] = uid

				# 2. Update Open Files List
				var idx = _open_files.find(old_path)
				if idx != -1:
					_open_files[idx] = current_real_path

				# 3. Update Category Cache Key
				if _category_cache.has(old_path):
					var cat = _category_cache[old_path]
					_category_cache.erase(old_path)
					_category_cache[current_real_path] = cat

				# 4. inform DataManager
				if (
					is_instance_valid(data_manager)
					and data_manager.get_active_graph_path() == old_path
				):
					data_manager.set_active_graph(current_real_path)

				redraw_needed = true

	if redraw_needed:
		_request_tree_redraw()


func refresh_category_for_path(path: String) -> void:
	if _category_cache.has(path):
		_category_cache.erase(path)
	# Force immediate reload
	_update_category_cache(path)
	_redraw_tree()


func mark_file_as_unsaved(_file_path: String, _is_unsaved: bool) -> void:
	if not is_instance_valid(data_manager):
		return
	if _tree_items_by_path.has(_file_path):
		var item = _tree_items_by_path[_file_path]
		var display_text = _file_path.get_file().get_basename()

		if data_manager.has_unsaved_changes(_file_path):
			display_text += " (*)"
			item.set_custom_color(0, Color.ORANGE)
		else:
			item.set_custom_color(0, Color.WHITE)
		item.set_text(0, display_text)

	if is_instance_valid(data_manager) and data_manager.get_active_graph_path() == _file_path:
		save_button.disabled = not data_manager.has_unsaved_changes(_file_path)

	_update_save_all_button_state()


func _update_save_all_button_state() -> void:
	if not is_instance_valid(data_manager):
		save_all_button.disabled = true
		return

	var unsaved_paths = data_manager.get_all_unsaved_paths()
	save_all_button.disabled = unsaved_paths.is_empty()


func update_selection(active_path: String) -> void:
	if not is_instance_valid(tree):
		return
	if not is_instance_valid(data_manager):
		tree.deselect_all()
		save_button.disabled = true
		return
	if _tree_items_by_path.has(active_path):
		var item = _tree_items_by_path[active_path]
		# Ensure category is expanded
		var parent = item.get_parent()
		if parent:
			parent.collapsed = false

		tree.set_selected(item, 0)
		tree.scroll_to_item(item)
		save_button.disabled = not data_manager.has_unsaved_changes(active_path)
	else:
		tree.deselect_all()
		save_button.disabled = true


func _redraw_tree() -> void:
	# Save collapse state from category items (root's direct children).
	# Iterate over categories, not files - container.get_first_child() yielded files before.
	# When filter hid categories, we only update the ones we see; others keep their previous state.
	var root_before = tree.get_root()
	if root_before:
		var category_item = root_before.get_first_child()
		while category_item:
			var cat_name: String = category_item.get_text(0)
			_category_collapse_state[cat_name] = category_item.collapsed
			category_item = category_item.get_next()

	tree.clear()
	_tree_items_by_path.clear()

	var root = tree.create_item()
	var filter = filter_edit.text.to_lower()

	# 1. Organize files by Category
	var categorized_files: Dictionary = {}  # "CategoryName": [path1, path2]

	for path in _open_files:
		# Filter check
		var display_name = path.get_file().get_basename()
		if not filter.is_empty() and not display_name.to_lower().contains(filter):
			continue

		var cat = _get_category_for_path(path)
		if not categorized_files.has(cat):
			categorized_files[cat] = []
		categorized_files[cat].append(path)

	# 2. Sort Categories (Keys)
	var sorted_categories = categorized_files.keys()
	sorted_categories.sort()

	# 3. Build Tree Nodes
	for category in sorted_categories:
		var category_item: TreeItem = tree.create_item(root)
		category_item.set_text(0, category)
		category_item.set_icon(0, _icon_folder)
		category_item.set_metadata(0, {"type": "category", "name": category})
		category_item.set_custom_color(0, CATEGORY_COLOR)
		category_item.set_icon_modulate(0, CATEGORY_COLOR)

		var files_in_cat: Array = categorized_files[category]
		files_in_cat.sort_custom(func(a, b): return a.get_file() < b.get_file())

		for path in files_in_cat:
			var item = tree.create_item(category_item)
			var display_name = path.get_file().get_basename()

			if is_instance_valid(data_manager) and data_manager.has_unsaved_changes(path):
				display_name += " (*)"
				item.set_custom_color(0, Color.ORANGE)

			item.set_text(0, display_name)
			item.set_icon(0, _icon_quest)
			item.set_metadata(0, {"type": "file", "path": path})
			item.set_tooltip_text(0, path)

			_tree_items_by_path[path] = item

		# Apply collapse state after adding children
		if _category_collapse_state.has(category):
			var should_collapse: bool = _category_collapse_state[category]
			category_item.collapsed = should_collapse

	# Restore selection last so active file's parent stays expanded
	if is_instance_valid(data_manager):
		update_selection(data_manager.get_active_graph_path())


# Helper: Read category from StartNodeResource (cached)
func _get_category_for_path(path: String) -> String:
	if _category_cache.has(path):
		return _category_cache[path]

	# Fallback if not cached (load and check)
	_update_category_cache(path)
	return _category_cache.get(path, "Uncategorized")


func _update_category_cache(path: String) -> void:
	var res: QuestGraphResource = null

	if is_instance_valid(data_manager) and data_manager.get_active_graph_path() == path:
		res = data_manager.get_active_graph()
	else:
		if not FileAccess.file_exists(path):
			_category_cache[path] = "Missing File"
			return
		res = ResourceLoader.load(path, "QuestGraphResource", ResourceLoader.CACHE_MODE_IGNORE)

	var category = "Uncategorized"

	if is_instance_valid(res):
		for node_id in res.nodes:
			var node = res.nodes[node_id]
			if node is StartNodeResource:
				if not node.graph_category.is_empty():
					category = node.graph_category
				break

	_category_cache[path] = category


func is_uid_valid_for_path(path: String) -> bool:
	if not _path_to_uid.has(path):
		return false
	var uid: int = _path_to_uid[path]
	return ResourceUID.has_id(uid)


# ==============================================================================
# FOLDER SCAN & DRAG DROP
# ==============================================================================


func _on_folder_selected_to_load(dir_path: String) -> void:
	var found_files = _scan_folder_recursive(dir_path, [0])
	if found_files.size() >= MAX_SCAN_FILES:
		push_warning(
			(
				"QuestWeaver: Folder scan limited to %d files. Some .quest files may be omitted."
				% MAX_SCAN_FILES
			)
		)

	if found_files.size() > 20:
		var confirm = ConfirmationDialog.new()
		confirm.title = "Load many files?"
		confirm.dialog_text = "Found %d quest files. Open all?" % found_files.size()
		add_child(confirm)
		confirm.confirmed.connect(
			func():
				for f in found_files:
					add_file_to_open_list(f)
				confirm.queue_free()
		)
		confirm.canceled.connect(func(): confirm.queue_free())
		confirm.popup_centered()
	else:
		for f in found_files:
			add_file_to_open_list(f)


func _scan_folder_recursive(path: String, accumulated_count: Array) -> Array[String]:
	var results: Array[String] = []
	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if accumulated_count[0] >= MAX_SCAN_FILES:
				dir.list_dir_end()
				return results
			if dir.current_is_dir():
				if file_name != "." and file_name != "..":
					results.append_array(
						_scan_folder_recursive(path.path_join(file_name), accumulated_count)
					)
			elif file_name.ends_with(".quest"):
				results.append(path.path_join(file_name))
				accumulated_count[0] += 1
			file_name = dir.get_next()
		dir.list_dir_end()
	return results


func _build_drag_data_for_item(item: TreeItem) -> Variant:
	if not item:
		return null
	var meta = item.get_metadata(0)
	if not meta or meta.type != "file":
		return null
	var file_path: String = meta.path
	return {"type": "files", "files": [file_path], "from": self}


func _create_drag_preview_for_path(file_path: String) -> Label:
	var preview = Label.new()
	preview.text = file_path.get_file()
	return preview


func _tree_get_drag_data(at_position: Vector2) -> Variant:
	var item = tree.get_item_at_position(at_position)
	var data = _build_drag_data_for_item(item)
	if data == null:
		return null
	set_drag_preview(_create_drag_preview_for_path(data.files[0]))
	return data


func _tree_can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if data is Dictionary and data.get("type") == "files":
		return true
	return false


func _tree_drop_data(_at_position: Vector2, data: Variant) -> void:
	if data is Dictionary and data.get("type") == "files":
		var files = data.get("files", [])
		for path in files:
			if path.ends_with(".quest"):
				open_file_requested.emit(path)
			elif DirAccess.dir_exists_absolute(path):
				_on_folder_selected_to_load(path)


# ==============================================================================
# CONTEXT MENU
# ==============================================================================


func _build_context_menu() -> void:
	context_menu.clear()
	# ID Mapping:
	# 0-9: File Operations
	# 10-19: Category Operations
	# 20-29: Utilities

	context_menu.add_item("Open / Activate", 0)
	context_menu.add_separator()
	context_menu.add_item("Save", 1)
	context_menu.add_item("Save All", 2)
	context_menu.add_separator()
	context_menu.add_item("Close", 3)
	context_menu.add_item("Close Other Files", 4)
	context_menu.add_item("Close All Files", 5)
	context_menu.add_separator()
	context_menu.add_item("Close Category", 10)
	context_menu.add_item("Close Other Categories", 11)
	context_menu.add_item("Collapse All Other Categories", 12)
	context_menu.add_separator()
	context_menu.add_item("Show in FileSystem", 20)
	context_menu.add_item("Copy Path", 21)
	context_menu.add_item("Copy UID", 22)


func _on_tree_item_mouse_selected(pos: Vector2, mouse_btn: int) -> void:
	if mouse_btn != MOUSE_BUTTON_RIGHT:
		return

	var item = tree.get_item_at_position(pos)
	if not item:
		return

	item.select(0)

	var meta = item.get_metadata(0)
	if not meta:
		return

	_context_menu_target_path = ""
	_context_menu_target_category = ""

	if meta.type == "file":
		_context_menu_target_path = meta.path
		_context_menu_target_category = _get_category_for_path(meta.path)

		context_menu.set_item_disabled(context_menu.get_item_index(CMID_CLOSE_CATEGORY), true)
		context_menu.set_item_disabled(
			context_menu.get_item_index(CMID_COLLAPSE_OTHER_CATEGORIES), false
		)
		context_menu.set_item_disabled(context_menu.get_item_index(CMID_SHOW_IN_FILESYSTEM), false)

	elif meta.type == "category":
		_context_menu_target_category = meta.name

		context_menu.set_item_disabled(context_menu.get_item_index(CMID_CLOSE_CATEGORY), false)
		context_menu.set_item_disabled(
			context_menu.get_item_index(CMID_COLLAPSE_OTHER_CATEGORIES), false
		)
		context_menu.set_item_disabled(context_menu.get_item_index(CMID_SHOW_IN_FILESYSTEM), true)

	context_menu.popup(Rect2i(get_global_mouse_position(), Vector2i.ZERO))


func _on_context_menu_id_pressed(id: int) -> void:
	match id:
		0:  # Open
			if not _context_menu_target_path.is_empty():
				bookmark_selected.emit(_context_menu_target_path)
		1:  # Save
			if not _context_menu_target_path.is_empty():
				save_single_file_requested.emit(_context_menu_target_path)
		2:  # Save All
			save_all_files_requested.emit()
		3:  # Close
			if not _context_menu_target_path.is_empty():
				close_bookmark_requested.emit(_context_menu_target_path)
		4:  # Close Others
			if not _context_menu_target_path.is_empty():
				for p in _open_files.duplicate():
					if p != _context_menu_target_path:
						close_bookmark_requested.emit(p)
		5:  # Close All
			close_all_requested.emit()

		10:  # Close Category
			if not _context_menu_target_category.is_empty():
				_close_files_in_category(_context_menu_target_category)
		11:  # Close Other Categories
			if not _context_menu_target_category.is_empty():
				# Batch-prefetch categories (max 20 per action to avoid UI freeze)
				var prefetched = 0
				for p in _open_files:
					if prefetched >= MAX_CATEGORY_PREFETCH:
						break
					if not _category_cache.has(p):
						_update_category_cache(p)
						prefetched += 1
				for p in _open_files:
					var c = _get_category_for_path(p)
					if c != _context_menu_target_category:
						close_bookmark_requested.emit(p)
		12:  # Collapse All Other Categories
			if not _context_menu_target_category.is_empty():
				_collapse_all_other_categories(_context_menu_target_category)

		20:  # Show in FileSystem
			if (
				not _context_menu_target_path.is_empty()
				and is_instance_valid(_editor_interface_ref)
			):
				_editor_interface_ref.get_file_system_dock().navigate_to_path(
					_context_menu_target_path
				)
		21:  # Copy Path
			if not _context_menu_target_path.is_empty():
				DisplayServer.clipboard_set(_context_menu_target_path)
		22:  # Copy UID
			if not _context_menu_target_path.is_empty():
				var uid = ResourceLoader.get_resource_uid(_context_menu_target_path)
				if uid != -1:
					DisplayServer.clipboard_set(ResourceUID.id_to_text(uid))
				else:
					DisplayServer.clipboard_set("UID_NOT_FOUND")


func _close_files_in_category(category: String) -> void:
	# Iterate over duplicate to safely remove
	for p in _open_files.duplicate():
		if _get_category_for_path(p) == category:
			close_bookmark_requested.emit(p)


func _collapse_all_other_categories(keep_expanded: String) -> void:
	var root_item = tree.get_root()
	if not root_item:
		return
	var category_item = root_item.get_first_child()
	while category_item:
		var cat_name: String = category_item.get_text(0)
		var should_collapse: bool = cat_name != keep_expanded
		category_item.collapsed = should_collapse
		_category_collapse_state[cat_name] = should_collapse
		category_item = category_item.get_next()


func _on_tree_item_activated() -> void:
	var item = tree.get_selected()
	if not item:
		return
	var meta = item.get_metadata(0)
	if not meta:
		return
	if meta.type == "file":
		bookmark_selected.emit(meta.path)
	elif meta.type == "category":
		item.collapsed = not item.collapsed


# ==============================================================================
# FILTER & SEARCH
# ==============================================================================


func _on_filter_text_changed(new_text: String) -> void:
	filter_edit.right_icon = _clear_icon if not new_text.is_empty() else _search_icon
	_filter_debounce_timer.stop()
	_filter_debounce_timer.start()


func _on_filter_debounce_timeout() -> void:
	_redraw_tree()


func _on_filter_gui_input(event: InputEvent) -> void:
	if filter_edit.text.is_empty():
		return
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and event.is_pressed()
	):
		# Logic to detect click on clear icon (simplified approximation)
		if event.position.x > filter_edit.size.x - 30:
			filter_edit.clear()
			get_viewport().set_input_as_handled()


# ==============================================================================
# DRAG & DROP (SIDE_PANEL TO PROPERTIES_PANEL)
# ==============================================================================


func _get_drag_data(at_position: Vector2) -> Variant:
	var item = tree.get_item_at_position(at_position)
	var data = _build_drag_data_for_item(item)
	if data == null:
		return null
	set_drag_preview(_create_drag_preview_for_path(data.files[0]))
	return data


# ==============================================================================
# HANDLE FILES MOVED
# ==============================================================================

## Called when a quest file is renamed/moved (e.g. from FileSystem dock).


## Use this for explicit path updates; check_for_moved_files_via_uid handles UID-based detection.
func update_moved_files(old_path: String, new_path: String) -> void:
	# 1. Update Open Files List
	if _open_files.has(old_path):
		var index = _open_files.find(old_path)
		_open_files[index] = new_path

	# 2. Update UID maps
	if _path_to_uid.has(old_path):
		var uid: int = _path_to_uid[old_path]
		_path_to_uid.erase(old_path)
		_path_to_uid[new_path] = uid
		_open_files_uids[uid] = new_path

	# 3. Update Cache
	if _category_cache.has(old_path):
		var cat = _category_cache[old_path]
		_category_cache.erase(old_path)
		_category_cache[new_path] = cat

	# 4. Update Active Graph in DataManager if needed
	if is_instance_valid(data_manager) and data_manager.get_active_graph_path() == old_path:
		data_manager.set_active_graph(new_path)

	_request_tree_redraw()
