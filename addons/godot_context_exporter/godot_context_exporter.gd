@tool
extends EditorPlugin

## Context Exporter Plugin
##
## Exports selected GDScript/C# files, Scene trees, and Project Settings into a single text file or clipboard.
## Designed specifically to generate compact, context-rich documentation for LLMs (ChatGPT, Claude, etc.).

#region Constants & Configuration
#-----------------------------------------------------------------------------

# UI Colors (Dark theme optimized)
const COLOR_SAVE_BTN = Color("#2e6b2e")
const COLOR_SAVE_TEXT = Color("#46a946")
const COLOR_COPY_BTN = Color("#2e6b69")
const COLOR_COPY_TEXT = Color("#4ab4b1")
const COLOR_ERROR = Color("#b83b3b")
const COLOR_WARNING = Color("#d4a53a")
const COLOR_ACCENT = Color("#7ca6e2")
const INFO_ICON_COLOR = Color("6da7d4ff")

# Layout constants
const INFO_ICON_SIZE = 18
const INFO_ICON_GAP = 0
const TOOLBAR_ICON_SIZE = Vector2i(18, 18)

# Icon resources
const ICON_PATH_PNG = "res://addons/godot_context_exporter/icons/context_exporter.png"
const ICON_PATH_SVG = "res://addons/godot_context_exporter/icons/context_exporter.svg"

# Configuration defaults
# These formats are treated as single assets rather than deep node trees to save context window space.
const DEFAULT_COLLAPSIBLE_FORMATS = [".blend", ".gltf", ".glb", ".obj", ".fbx"]
const SETTING_FORMATS_PATH = "context_exporter/collapsible_formats"
const SETTING_SHOW_BUTTON_PATH = "context_exporter/show_editor_button"

# Styling constants
const THEME_BG_COLOR = Color("#232323")
const THEME_LIST_BG = Color("#2c3036")

#endregion


#region UI References
#-----------------------------------------------------------------------------
# Main references
var window: Window
var status_label: Label
var toolbar_button: Button

# Script Tab Controls
var script_list: ItemList
var select_all_scripts_checkbox: CheckBox
var group_by_folder_checkbox: CheckBox
var wrap_in_markdown_checkbox: CheckBox
var group_depth_spinbox: SpinBox
var expand_all_scripts_button: Button
var collapse_all_scripts_button: Button

# Scene Tab Controls
var scene_list: ItemList
var select_all_scenes_checkbox: CheckBox
var include_inspector_checkbox: CheckBox
var collapse_scenes_checkbox: CheckBox
var wrap_scenes_in_markdown_checkbox: CheckBox
var scene_group_by_folder_checkbox: CheckBox
var scene_group_depth_spinbox: SpinBox
var scene_expand_all_button: Button
var scene_collapse_all_button: Button

# Popups
var format_manager_dialog: Window
var formats_list_vbox: VBoxContainer
var advanced_settings_dialog: Window

#endregion


#region State Variables
#-----------------------------------------------------------------------------

# Script Selection State
var group_by_folder: bool = true
var group_depth: int = 0         # 0 = Recursive Tree (File system view), 1+ = Flat depth level
var wrap_in_markdown: bool = false
var all_script_paths: Array[String] = []
var folder_data: Dictionary = {} # Stores data when using flat/depth grouping
var tree_nodes: Dictionary = {}  # Stores data when using recursive tree view

# Scene Selection State
var scene_group_by_folder: bool = true
var scene_group_depth: int = 0
var all_scene_paths: Array[String] = []
var scene_folder_data: Dictionary = {}
var scene_tree_nodes: Dictionary = {}

# Export Options
var include_inspector_changes: bool = false
var wrap_scene_in_markdown: bool = false
var collapse_instanced_scenes: bool = false
var merge_similar_nodes: bool = false
var collapsible_formats: Array = DEFAULT_COLLAPSIBLE_FORMATS.duplicate()

# Project Settings & Globals
var include_project_godot: bool = false
var wrap_project_godot_in_markdown: bool = false
var include_autoloads: bool = true
var wrap_autoloads_in_markdown: bool = true

# Advanced Configuration
var include_addons: bool = false # Scanning addons folder is heavy, disabled by default
var show_editor_button: bool = true

#endregion


#region Plugin Lifecycle
#-----------------------------------------------------------------------------

func _enter_tree() -> void:
	# Add a menu item in Project -> Tools as a fallback access point
	add_tool_menu_item("Context Exporter...", Callable(self, "open_window"))
	
	_load_config()
	_setup_ui()
	
	# Only add the toolbar shortcut if enabled in settings
	if show_editor_button:
		_add_toolbar_button()

func _exit_tree() -> void:
	remove_tool_menu_item("Context Exporter...")
	
	# Clean up UI elements to prevent memory leaks or editor errors
	if is_instance_valid(toolbar_button):
		remove_control_from_container(EditorPlugin.CONTAINER_TOOLBAR, toolbar_button)
		toolbar_button.queue_free()
	
	if is_instance_valid(window):
		window.queue_free()
	if is_instance_valid(format_manager_dialog):
		format_manager_dialog.queue_free()
	if is_instance_valid(advanced_settings_dialog):
		advanced_settings_dialog.queue_free()

#endregion


#region UI Construction
#-----------------------------------------------------------------------------

#region UI Construction
#-----------------------------------------------------------------------------

## Creates and places the button in the main Godot Editor toolbar (top right).
func _add_toolbar_button() -> void:
	toolbar_button = Button.new()
	toolbar_button.text = "Context"
	toolbar_button.tooltip_text = "Open Godot Context Exporter"
	toolbar_button.flat = true
	toolbar_button.focus_mode = Control.FOCUS_NONE
	# Connect the click signal to the open_window function
	toolbar_button.pressed.connect(open_window)
	
	# Attempt to load custom icons (PNG or SVG) to make the button look integrated.
	var raw_icon: Texture2D = null
	if FileAccess.file_exists(ICON_PATH_PNG):
		raw_icon = load(ICON_PATH_PNG)
	elif FileAccess.file_exists(ICON_PATH_SVG):
		raw_icon = load(ICON_PATH_SVG)
	
	if raw_icon:
		# Resize the icon for consistency with standard editor toolbar icons (usually 16x16 or 18x18).
		var image = raw_icon.get_image()
		image.resize(TOOLBAR_ICON_SIZE.x, TOOLBAR_ICON_SIZE.y, Image.INTERPOLATE_CUBIC)
		toolbar_button.icon = ImageTexture.create_from_image(image)
	else:
		# Fallback: Use the default built-in "Script" icon from the Editor's theme if custom icon fails.
		var editor_base = get_editor_interface().get_base_control()
		if editor_base.has_theme_icon("Script", "EditorIcons"):
			toolbar_button.icon = editor_base.get_theme_icon("Script", "EditorIcons")
	
	# Add the button to the specific editor container (The top toolbar).
	add_control_to_container(EditorPlugin.CONTAINER_TOOLBAR, toolbar_button)

## Main initialization for the popup window and high-level layout.
func _setup_ui() -> void:
	# Create the main popup window as a standard Window node.
	window = Window.new()
	window.title = "Godot Context Exporter"
	window.min_size = Vector2i(600, 750)
	window.size = Vector2i(700, 850)
	window.visible = false
	window.wrap_controls = true
	# Hiding the window instead of freeing it allows us to preserve state (checkbox selections) between opens.
	window.close_requested.connect(window.hide)

	# Main layout container: A PanelContainer to provide a background color.
	var root_panel = PanelContainer.new()
	var main_style = StyleBoxFlat.new()
	main_style.bg_color = THEME_BG_COLOR
	root_panel.add_theme_stylebox_override("panel", main_style)
	root_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	window.add_child(root_panel)

	# Add margins so elements don't touch the window edges.
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 15)
	margin.add_theme_constant_override("margin_right", 15)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	root_panel.add_child(margin)
	
	# Vertical box to stack the Tabs (top) and Footer controls (bottom).
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 15)
	margin.add_child(main_vbox)

	# --- Tab System ---
	# We use a Control wrapper here to allow us to "float" a button on top of the tab bar area later.
	var tabs_wrapper = Control.new()
	tabs_wrapper.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(tabs_wrapper)

	var tab_container = TabContainer.new()
	tab_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tabs_wrapper.add_child(tab_container)

	# Build and add the two main tabs
	tab_container.add_child(_create_scripts_tab())
	tab_container.set_tab_title(0, "Scripts")
	
	tab_container.add_child(_create_scenes_tab())
	tab_container.set_tab_title(1, "Scenes")
	
	# --- Advanced Settings Button ---
	# We manually position this button at the Top-Right of the wrapper to make it look like 
	# it belongs to the tab bar, saving vertical space.
	var adv_btn = Button.new()
	adv_btn.text = "Advanced Settings"
	adv_btn.flat = true
	adv_btn.add_theme_color_override("font_color", COLOR_ACCENT)
	adv_btn.pressed.connect(_on_advanced_settings_pressed)
	adv_btn.focus_mode = Control.FOCUS_NONE
	
	tabs_wrapper.add_child(adv_btn)
	adv_btn.layout_mode = 1 # Set to Anchors mode
	adv_btn.anchors_preset = Control.PRESET_TOP_RIGHT
	adv_btn.offset_right = -5
	adv_btn.offset_top = 0
	
	# Build the bottom section (Save/Copy buttons and project settings).
	_create_footer_controls(main_vbox)
	
	# Attach the floating window to the editor's base control so it renders correctly within the OS context.
	get_editor_interface().get_base_control().add_child(window)

## Constructs the content of the "Scripts" tab.
func _create_scripts_tab() -> Control:
	var vbox = VBoxContainer.new()
	vbox.name = "ScriptsTab"
	vbox.add_theme_constant_override("separation", 10)

	# 1. Header Label
	var scripts_label = RichTextLabel.new()
	scripts_label.bbcode_enabled = true
	scripts_label.text = "[b][color=#d5eaf2]Select Scripts to Export:[/color][/b]"
	scripts_label.fit_content = true
	vbox.add_child(scripts_label)
	
	# 2. Controls Toolbar (Select All | Grouping | Depth | Expand/Collapse)
	var options_hbox = HBoxContainer.new()
	vbox.add_child(options_hbox)

	select_all_scripts_checkbox = CheckBox.new()
	select_all_scripts_checkbox.text = "Select All"
	select_all_scripts_checkbox.add_theme_color_override("font_color", COLOR_ACCENT)
	select_all_scripts_checkbox.pressed.connect(_on_select_all_scripts_toggled)
	options_hbox.add_child(select_all_scripts_checkbox)
	
	options_hbox.add_child(VSeparator.new())
	
	group_by_folder_checkbox = CheckBox.new()
	group_by_folder_checkbox.text = "Group by Folder"
	group_by_folder_checkbox.button_pressed = true 
	group_by_folder_checkbox.toggled.connect(_on_group_by_folder_toggled)
	options_hbox.add_child(group_by_folder_checkbox)
	
	# Depth Control (SpinBox to flatten the folder structure at a certain level)
	var depth_hbox = HBoxContainer.new()
	options_hbox.add_child(depth_hbox)
	
	var depth_label = Label.new()
	depth_label.text = "Depth:"
	depth_label.tooltip_text = "0 = Recursive Tree (Auto)\n1 = Root level\n2 = Subfolder level"
	depth_hbox.add_child(depth_label)
	
	group_depth_spinbox = SpinBox.new()
	group_depth_spinbox.min_value = 0
	group_depth_spinbox.max_value = 10
	group_depth_spinbox.value = group_depth
	group_depth_spinbox.tooltip_text = depth_label.tooltip_text
	group_depth_spinbox.editable = true
	group_depth_spinbox.modulate.a = 1.0
	# Connect value change to rebuild the model immediately
	group_depth_spinbox.value_changed.connect(func(val): 
		group_depth = int(val)
		_build_script_data_model()
		_render_script_list()
	)
	depth_hbox.add_child(group_depth_spinbox)
	
	options_hbox.add_child(VSeparator.new())
	
	expand_all_scripts_button = Button.new()
	expand_all_scripts_button.text = "Expand All"
	# Use bind(true) to reuse one function for both expand and collapse
	expand_all_scripts_button.pressed.connect(_on_expand_collapse_scripts.bind(true))
	options_hbox.add_child(expand_all_scripts_button)
	
	collapse_all_scripts_button = Button.new()
	collapse_all_scripts_button.text = "Collapse All"
	collapse_all_scripts_button.pressed.connect(_on_expand_collapse_scripts.bind(false))
	options_hbox.add_child(collapse_all_scripts_button)
	
	# 3. The Main File List
	var list_panel = _create_list_panel()
	list_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(list_panel)
	
	script_list = ItemList.new()
	script_list.select_mode = ItemList.SELECT_SINGLE
	script_list.allow_reselect = true # Required to allow toggling checkboxes on click
	script_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	script_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	script_list.item_clicked.connect(_on_script_item_clicked)
	list_panel.add_child(script_list)

	# 4. Tab Footer (Format options specific to Scripts)
	var options_grid = GridContainer.new()
	options_grid.columns = 2
	options_grid.add_theme_constant_override("h_separation", 20)
	options_grid.add_theme_constant_override("v_separation", 5)
	vbox.add_child(options_grid)

	var markdown_hbox = HBoxContainer.new()
	markdown_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	markdown_hbox.add_theme_constant_override("separation", INFO_ICON_GAP)
	options_grid.add_child(markdown_hbox)

	wrap_in_markdown_checkbox = CheckBox.new()
	wrap_in_markdown_checkbox.text = "Use Markdown (```gdscript``` / ```csharp```)"
	wrap_in_markdown_checkbox.toggled.connect(func(p): wrap_in_markdown = p)
	markdown_hbox.add_child(wrap_in_markdown_checkbox)
	
	return vbox

## Constructs the content of the "Scenes" tab. 
## Similar to Scripts tab but with extra Scene-specific processing options.
func _create_scenes_tab() -> Control:
	var vbox = VBoxContainer.new()
	vbox.name = "ScenesTab"
	vbox.add_theme_constant_override("separation", 10)

	# Header
	var scenes_label = RichTextLabel.new()
	scenes_label.bbcode_enabled = true
	scenes_label.text = "[b][color=#d5eaf2]Select Scenes to Export:[/color][/b]"
	scenes_label.fit_content = true
	vbox.add_child(scenes_label)

	# Toolbar
	var options_hbox = HBoxContainer.new()
	vbox.add_child(options_hbox)

	select_all_scenes_checkbox = CheckBox.new()
	select_all_scenes_checkbox.text = "Select All"
	select_all_scenes_checkbox.add_theme_color_override("font_color", COLOR_ACCENT)
	select_all_scenes_checkbox.pressed.connect(_on_select_all_scenes_toggled)
	options_hbox.add_child(select_all_scenes_checkbox)
	
	options_hbox.add_child(VSeparator.new())
	
	scene_group_by_folder_checkbox = CheckBox.new()
	scene_group_by_folder_checkbox.text = "Group by Folder"
	scene_group_by_folder_checkbox.button_pressed = true
	scene_group_by_folder_checkbox.toggled.connect(_on_scene_group_by_folder_toggled)
	options_hbox.add_child(scene_group_by_folder_checkbox)

	var depth_hbox = HBoxContainer.new()
	options_hbox.add_child(depth_hbox)
	
	var depth_label = Label.new()
	depth_label.text = "Depth:"
	depth_label.tooltip_text = "0 = Recursive Tree (Auto)\n1 = Root level\n2 = Subfolder level"
	depth_hbox.add_child(depth_label)
	
	scene_group_depth_spinbox = SpinBox.new()
	scene_group_depth_spinbox.min_value = 0
	scene_group_depth_spinbox.max_value = 10
	scene_group_depth_spinbox.value = scene_group_depth
	scene_group_depth_spinbox.tooltip_text = depth_label.tooltip_text
	scene_group_depth_spinbox.editable = true
	scene_group_depth_spinbox.modulate.a = 1.0
	scene_group_depth_spinbox.value_changed.connect(func(val): 
		scene_group_depth = int(val)
		_build_scene_data_model()
		_render_scene_list()
	)
	depth_hbox.add_child(scene_group_depth_spinbox)

	options_hbox.add_child(VSeparator.new())
	
	scene_expand_all_button = Button.new()
	scene_expand_all_button.text = "Expand All"
	scene_expand_all_button.pressed.connect(_on_expand_collapse_scenes.bind(true))
	options_hbox.add_child(scene_expand_all_button)
	
	scene_collapse_all_button = Button.new()
	scene_collapse_all_button.text = "Collapse All"
	scene_collapse_all_button.pressed.connect(_on_expand_collapse_scenes.bind(false))
	options_hbox.add_child(scene_collapse_all_button)
	
	# The Main List
	var list_panel = _create_list_panel()
	list_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(list_panel)

	scene_list = ItemList.new()
	scene_list.select_mode = ItemList.SELECT_SINGLE 
	scene_list.allow_reselect = true
	scene_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scene_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scene_list.item_clicked.connect(_on_scene_item_clicked)
	list_panel.add_child(scene_list)

	# Tab Footer (Scene Processing Options)
	var options_grid = GridContainer.new()
	options_grid.columns = 2
	options_grid.add_theme_constant_override("h_separation", 20) 
	options_grid.add_theme_constant_override("v_separation", 5)
	vbox.add_child(options_grid)

	# Option 1: Inspector Changes (Diffs)
	var inspector_hbox = HBoxContainer.new()
	inspector_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector_hbox.add_theme_constant_override("separation", INFO_ICON_GAP) 
	options_grid.add_child(inspector_hbox)

	include_inspector_checkbox = CheckBox.new()
	include_inspector_checkbox.text = "Show Inspector Changes"
	include_inspector_checkbox.toggled.connect(func(p): include_inspector_changes = p)
	inspector_hbox.add_child(include_inspector_checkbox)
	
	# Add an info icon with a tooltip explaining this complex feature
	inspector_hbox.add_child(_create_info_icon(
		"Shows properties modified in the Inspector that differ from defaults.\n" +
		"Adds a 'changes' list to nodes, revealing tweaked values like Position, Scale, or Script Variables."
	))

	# Option 2: Merge Similar Nodes
	var merge_hbox = HBoxContainer.new()
	merge_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	merge_hbox.add_theme_constant_override("separation", INFO_ICON_GAP)
	options_grid.add_child(merge_hbox)
	
	var merge_checkbox = CheckBox.new()
	merge_checkbox.text = "Merge Similar Nodes"
	merge_checkbox.toggled.connect(func(p): merge_similar_nodes = p)
	merge_hbox.add_child(merge_checkbox)
	
	merge_hbox.add_child(_create_info_icon(
		"Detects adjacent duplicates (e.g. Enemy_1, Enemy_2, Enemy_3)\n" +
		"and combines them into a single line (Enemy x3) to save space."
	))

	# Option 3: Markdown Wrapping
	var markdown_hbox = HBoxContainer.new()
	markdown_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	markdown_hbox.add_theme_constant_override("separation", INFO_ICON_GAP)
	options_grid.add_child(markdown_hbox)

	wrap_scenes_in_markdown_checkbox = CheckBox.new()
	wrap_scenes_in_markdown_checkbox.text = "Use Markdown (```text```)"
	wrap_scenes_in_markdown_checkbox.toggled.connect(func(p): wrap_scene_in_markdown = p)
	markdown_hbox.add_child(wrap_scenes_in_markdown_checkbox)

	# Option 4: Simplify Imported Scenes (Collapsing .blend/.gltf files)
	var collapse_hbox = HBoxContainer.new()
	collapse_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	collapse_hbox.add_theme_constant_override("separation", INFO_ICON_GAP)
	options_grid.add_child(collapse_hbox)
	
	collapse_scenes_checkbox = CheckBox.new()
	collapse_scenes_checkbox.text = "Simplify Imported Scenes"
	collapse_scenes_checkbox.toggled.connect(func(p): collapse_instanced_scenes = p)
	collapse_hbox.add_child(collapse_scenes_checkbox)
	
	collapse_hbox.add_child(_create_info_icon(
		"Treats complex imported files (like .blend, .gltf) as a single node line.\n" +
		"Prevents hundreds of internal mesh nodes from cluttering your export.\n" +
		"(You can configure extensions in Advanced Settings)"
	))

	return vbox

## Creates the independent window for configuring Advanced Settings (filters and editor options).
func _create_advanced_settings_dialog() -> void:
	advanced_settings_dialog = Window.new()
	advanced_settings_dialog.title = "Advanced Settings"
	advanced_settings_dialog.min_size = Vector2i(400, 500)
	advanced_settings_dialog.size = Vector2i(400, 500)
	# Trigger the save logic when closing via 'x'
	advanced_settings_dialog.close_requested.connect(_save_and_close_advanced_settings)
	window.add_child(advanced_settings_dialog)
	
	# Background Styling
	var bg_panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = THEME_BG_COLOR
	bg_panel.add_theme_stylebox_override("panel", style)
	bg_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	advanced_settings_dialog.add_child(bg_panel)
	
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 15)
	margin.add_theme_constant_override("margin_right", 15)
	margin.add_theme_constant_override("margin_top", 15)
	margin.add_theme_constant_override("margin_bottom", 15)
	bg_panel.add_child(margin)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 15)
	margin.add_child(main_vbox)
	
	# --- Section: Editor Integration ---
	var integration_vbox = VBoxContainer.new()
	main_vbox.add_child(integration_vbox)
	
	var int_label = Label.new()
	int_label.text = "Editor Integration"
	int_label.add_theme_color_override("font_color", COLOR_ACCENT)
	integration_vbox.add_child(int_label)
	
	integration_vbox.add_child(HSeparator.new())
	
	var btn_checkbox = CheckBox.new()
	btn_checkbox.text = "Show 'Context' button in toolbar"
	btn_checkbox.button_pressed = show_editor_button
	# We name this node so we can find it easily during the Save step
	btn_checkbox.name = "ShowButtonCheckbox" 
	integration_vbox.add_child(btn_checkbox)
	
	# --- Section: Scanning Options ---
	var scan_vbox = VBoxContainer.new()
	main_vbox.add_child(scan_vbox)
	
	var label = Label.new()
	label.text = "Scanning Options"
	label.add_theme_color_override("font_color", COLOR_ACCENT)
	scan_vbox.add_child(label)
	
	scan_vbox.add_child(HSeparator.new())
	
	var addons_checkbox = CheckBox.new()
	addons_checkbox.text = "Include 'addons/' folder content"
	addons_checkbox.button_pressed = include_addons
	addons_checkbox.toggled.connect(_on_include_addons_toggled)
	scan_vbox.add_child(addons_checkbox)
	
	var info_label = Label.new()
	info_label.text = "Note: Including addons can significantly increase the list size."
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.modulate = Color(1, 1, 1, 0.6)
	scan_vbox.add_child(info_label)
	
	# --- Section: Format Management ---
	# This section allows users to define which extensions count as "collapsible" (e.g. .blend, .glb)
	var fmt_vbox = VBoxContainer.new()
	fmt_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL 
	main_vbox.add_child(fmt_vbox)
	
	var fmt_label = Label.new()
	fmt_label.text = "Collapsible Formats"
	fmt_label.add_theme_color_override("font_color", COLOR_ACCENT)
	fmt_vbox.add_child(fmt_label)
	
	fmt_vbox.add_child(HSeparator.new())
	
	var help_label = Label.new()
	help_label.text = "Extensions to simplify (treat as single node):"
	help_label.modulate = Color(1, 1, 1, 0.8)
	fmt_vbox.add_child(help_label)
	
	# Scrollable List container for the formats
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll_style = StyleBoxFlat.new()
	scroll_style.bg_color = Color(0, 0, 0, 0.2)
	scroll_style.set_corner_radius_all(4)
	scroll.add_theme_stylebox_override("panel", scroll_style)
	fmt_vbox.add_child(scroll)
	
	formats_list_vbox = VBoxContainer.new()
	formats_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(formats_list_vbox)
	
	# Action Buttons (Add / Reset)
	var buttons_hbox = HBoxContainer.new()
	fmt_vbox.add_child(buttons_hbox)
	
	var add_btn = Button.new()
	add_btn.text = "+ Add Extension"
	add_btn.flat = true
	add_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_btn.pressed.connect(func(): _add_format_row(""))
	buttons_hbox.add_child(add_btn)
	
	var spacer_btn = Control.new()
	spacer_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons_hbox.add_child(spacer_btn)
	
	var reset_btn = Button.new()
	reset_btn.text = "Reset to Defaults"
	reset_btn.flat = true
	reset_btn.add_theme_color_override("font_color", COLOR_WARNING)
	reset_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	reset_btn.tooltip_text = "Restore original list: " + ", ".join(DEFAULT_COLLAPSIBLE_FORMATS)
	reset_btn.pressed.connect(_on_reset_formats_pressed)
	buttons_hbox.add_child(reset_btn)
	
	# Main Footer (Save)
	var close_btn = Button.new()
	close_btn.text = "Save & Close"
	close_btn.custom_minimum_size.y = 30
	close_btn.pressed.connect(_save_and_close_advanced_settings)
	main_vbox.add_child(close_btn)

## Rebuilds the format list with the hardcoded default values.
func _on_reset_formats_pressed() -> void:
	for child in formats_list_vbox.get_children():
		child.queue_free()
	
	for ext in DEFAULT_COLLAPSIBLE_FORMATS:
		_add_format_row(ext)

## Creates a sub-dialog (if needed independently) for managing formats.
## Note: This is partly redundant with Advanced Settings but kept for modularity.
func _create_format_manager_dialog() -> void:
	format_manager_dialog = Window.new()
	format_manager_dialog.title = "Manage Collapsible Formats"
	format_manager_dialog.min_size = Vector2i(350, 400)
	format_manager_dialog.size = Vector2i(350, 500)
	format_manager_dialog.close_requested.connect(format_manager_dialog.hide)
	window.add_child(format_manager_dialog)
	
	var bg_panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = THEME_BG_COLOR
	bg_panel.add_theme_stylebox_override("panel", style)
	bg_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	format_manager_dialog.add_child(bg_panel)
	
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	bg_panel.add_child(margin)
	
	var main_vbox = VBoxContainer.new()
	margin.add_child(main_vbox)
	
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(scroll)
	
	formats_list_vbox = VBoxContainer.new()
	scroll.add_child(formats_list_vbox)
	
	var add_button = Button.new()
	add_button.text = "Add New Format"
	add_button.pressed.connect(_add_format_row.bind(""))
	main_vbox.add_child(add_button)
	
	main_vbox.add_child(HSeparator.new())
	
	var buttons_hbox = HBoxContainer.new()
	buttons_hbox.alignment = BoxContainer.ALIGNMENT_END
	main_vbox.add_child(buttons_hbox)
	
	var ok_button = Button.new()
	ok_button.text = "OK"
	ok_button.pressed.connect(_on_format_dialog_ok)
	buttons_hbox.add_child(ok_button)
	
	var cancel_button = Button.new()
	cancel_button.text = "Cancel"
	cancel_button.pressed.connect(format_manager_dialog.hide)
	buttons_hbox.add_child(cancel_button)

## Helper: Adds a single editable row (LineEdit + Delete Button) to the formats list.
func _add_format_row(text_value: String) -> void:
	var hbox = HBoxContainer.new()
	formats_list_vbox.add_child(hbox)
	
	var line_edit = LineEdit.new()
	line_edit.text = text_value
	line_edit.placeholder_text = ".extension"
	line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(line_edit)
	
	var del_btn = Button.new()
	del_btn.text = " × "
	del_btn.modulate = COLOR_ERROR
	del_btn.tooltip_text = "Remove"
	# Connect directly to queue_free to remove the row without needing an index reference.
	del_btn.pressed.connect(hbox.queue_free)
	hbox.add_child(del_btn)

## Reads the state of the Advanced Settings dialog, applies changes to global variables, and saves config.
func _save_and_close_advanced_settings() -> void:
	# 1. Update Button Visibility based on checkbox
	var btn_checkbox = advanced_settings_dialog.find_child("ShowButtonCheckbox", true, false) as CheckBox
	if btn_checkbox:
		var new_show_state = btn_checkbox.button_pressed
		
		if new_show_state != show_editor_button:
			show_editor_button = new_show_state
			if show_editor_button:
				if not is_instance_valid(toolbar_button):
					_add_toolbar_button()
			else:
				if is_instance_valid(toolbar_button):
					remove_control_from_container(EditorPlugin.CONTAINER_TOOLBAR, toolbar_button)
					toolbar_button.queue_free()

	# 2. Update Formats list from the dynamic UI rows
	collapsible_formats.clear()
	for child in formats_list_vbox.get_children():
		var line_edit = child.get_child(0) as LineEdit
		if line_edit:
			var txt = line_edit.text.strip_edges()
			if not txt.is_empty():
				if not txt.begins_with("."):
					txt = "." + txt
				if not txt in collapsible_formats:
					collapsible_formats.append(txt)
	
	# 3. Persist Settings to project.godot or editor settings
	_save_config()
	
	# 4. Refresh Scenes logic if the collapsible formats changed
	if collapse_instanced_scenes:
		_render_scene_list()
		
	advanced_settings_dialog.hide()

## Helper: Creates a styled background panel for ItemLists to make them stand out.
func _create_list_panel() -> PanelContainer:
	var list_style = StyleBoxFlat.new()
	list_style.bg_color = THEME_LIST_BG
	list_style.set_corner_radius_all(3)
	var list_panel = PanelContainer.new()
	list_panel.add_theme_stylebox_override("panel", list_style)
	return list_panel

## Constructs the bottom section of the main window (Autoloads, Project Settings, Export Buttons).
func _create_footer_controls(parent: VBoxContainer) -> void:
	var options_grid = GridContainer.new()
	options_grid.columns = 2
	options_grid.add_theme_constant_override("h_separation", 20)
	options_grid.add_theme_constant_override("v_separation", 2)
	parent.add_child(options_grid)
	
	# --- Autoloads (Globals) Section ---
	var autoloads_hbox = HBoxContainer.new()
	autoloads_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	autoloads_hbox.add_theme_constant_override("separation", INFO_ICON_GAP)
	options_grid.add_child(autoloads_hbox)

	var autoloads_checkbox = CheckBox.new()
	autoloads_checkbox.text = "Include Globals (Autoloads/Singletons)"
	autoloads_checkbox.button_pressed = true
	autoloads_hbox.add_child(autoloads_checkbox)
	
	autoloads_hbox.add_child(_create_info_icon(
		"Exports Scripts and Scenes defined in Project Settings -> Autoload.\n" +
		"Provides context about Singletons and global variables accessible from anywhere in your code.\n" +
		"When enabled, selected scripts which are autoloaded will be ignored at export to prevent duplicates."
	))
	
	# --- Project Settings Section ---
	var proj_godot_hbox = HBoxContainer.new()
	proj_godot_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	proj_godot_hbox.add_theme_constant_override("separation", INFO_ICON_GAP)
	options_grid.add_child(proj_godot_hbox)

	var project_godot_checkbox = CheckBox.new()
	project_godot_checkbox.text = "Include project.godot file content"
	proj_godot_hbox.add_child(project_godot_checkbox)
	
	proj_godot_hbox.add_child(_create_info_icon(
		"Exports key configuration details like Input Map actions, Layer Names, and Application settings.\n" +
		"Helps understand project-wide constants and controls."
	))

	# --- Indented Sub-options (Markdown Wrappers) ---
	
	# Autoloads Markdown Checkbox (Child of Autoloads)
	var al_margin = MarginContainer.new()
	al_margin.add_theme_constant_override("margin_left", 24)
	options_grid.add_child(al_margin)
	
	var wrap_autoloads_checkbox = CheckBox.new()
	wrap_autoloads_checkbox.text = "Use Markdown"
	wrap_autoloads_checkbox.button_pressed = true
	wrap_autoloads_checkbox.toggled.connect(func(p): wrap_autoloads_in_markdown = p)
	al_margin.add_child(wrap_autoloads_checkbox)
	
	# Logic: Disable the markdown sub-checkbox if the main Autoloads checkbox is off.
	autoloads_checkbox.toggled.connect(func(p): 
		include_autoloads = p
		wrap_autoloads_checkbox.disabled = not p
		if not p: wrap_autoloads_checkbox.button_pressed = false
		else: wrap_autoloads_checkbox.button_pressed = wrap_autoloads_in_markdown
	)

	# Project.godot Markdown Checkbox (Child of Project Settings)
	var proj_margin = MarginContainer.new()
	proj_margin.add_theme_constant_override("margin_left", 24)
	options_grid.add_child(proj_margin)

	var wrap_project_godot_checkbox = CheckBox.new()
	wrap_project_godot_checkbox.text = "Use Markdown (```ini```)"
	wrap_project_godot_checkbox.disabled = true
	wrap_project_godot_checkbox.toggled.connect(func(p): wrap_project_godot_in_markdown = p)
	proj_margin.add_child(wrap_project_godot_checkbox)

	# Logic: Disable the markdown sub-checkbox if the main project.godot checkbox is off.
	project_godot_checkbox.toggled.connect(func(p):
		include_project_godot = p
		wrap_project_godot_checkbox.disabled = not p
		if not p:
			wrap_project_godot_checkbox.button_pressed = false
	)

	# --- Main Action Buttons (Copy / Save) ---
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 20)
	hbox.alignment = HBoxContainer.ALIGNMENT_CENTER
	parent.add_child(hbox)
	
	var copy_button = Button.new()
	copy_button.text = "Copy to Clipboard"
	copy_button.custom_minimum_size = Vector2(150, 35)
	var copy_style = StyleBoxFlat.new(); copy_style.bg_color = COLOR_COPY_BTN
	copy_button.add_theme_stylebox_override("normal", copy_style)
	# Pass 'true' to indicate clipboard export
	copy_button.pressed.connect(_export_selected.bind(true))
	hbox.add_child(copy_button)
	
	var save_button = Button.new()
	save_button.text = "Save to File"
	save_button.custom_minimum_size = Vector2(150, 35)
	var save_style = StyleBoxFlat.new(); save_style.bg_color = COLOR_SAVE_BTN
	save_button.add_theme_stylebox_override("normal", save_style)
	# Pass 'false' to indicate file export
	save_button.pressed.connect(_export_selected.bind(false))
	hbox.add_child(save_button)
	
	# Status label for feedback (e.g. "Copied 5 scripts")
	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(status_label)

## Helper: Creates a standard Label formatted as an info icon with a tooltip.
func _create_info_icon(tooltip_text: String) -> Label:
	var label = Label.new()
	label.text = "ⓘ" 
	label.tooltip_text = tooltip_text
	label.mouse_filter = Control.MOUSE_FILTER_STOP # Ensures the tooltip event is caught
	label.mouse_default_cursor_shape = Control.CURSOR_HELP
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", INFO_ICON_COLOR)
	label.add_theme_font_size_override("font_size", INFO_ICON_SIZE)
	return label

#endregion


#region Data Management & Rendering
#-----------------------------------------------------------------------------

func _load_config() -> void:
	# Load Formats
	if ProjectSettings.has_setting(SETTING_FORMATS_PATH):
		var setting_value = ProjectSettings.get_setting(SETTING_FORMATS_PATH)
		if setting_value is PackedStringArray:
			collapsible_formats = Array(setting_value)
		else:
			collapsible_formats = setting_value
	else:
		collapsible_formats = DEFAULT_COLLAPSIBLE_FORMATS.duplicate()
	
	# Load UI Preference
	if ProjectSettings.has_setting(SETTING_SHOW_BUTTON_PATH):
		show_editor_button = ProjectSettings.get_setting(SETTING_SHOW_BUTTON_PATH)
	else:
		show_editor_button = true

func _save_config() -> void:
	# Save Formats
	var data_to_save = PackedStringArray(collapsible_formats)
	ProjectSettings.set_setting(SETTING_FORMATS_PATH, data_to_save)
	ProjectSettings.add_property_info({
		"name": SETTING_FORMATS_PATH,
		"type": TYPE_PACKED_STRING_ARRAY,
		"hint": PROPERTY_HINT_NONE,
	})
	ProjectSettings.set_initial_value(SETTING_FORMATS_PATH, PackedStringArray(DEFAULT_COLLAPSIBLE_FORMATS))
	
	# Save UI Preference
	ProjectSettings.set_setting(SETTING_SHOW_BUTTON_PATH, show_editor_button)
	ProjectSettings.add_property_info({
		"name": SETTING_SHOW_BUTTON_PATH,
		"type": TYPE_BOOL,
		"hint": PROPERTY_HINT_NONE,
	})
	ProjectSettings.set_initial_value(SETTING_SHOW_BUTTON_PATH, true)
	
	# Commit to file
	var error = ProjectSettings.save()
	if error != OK:
		push_error("Context Exporter: Could not save settings. Error: %s" % error)

func open_window() -> void:
	# Scan the project files every time the window opens to ensure the list is fresh
	_scan_and_refresh()
	
	status_label.remove_theme_color_override("font_color")
	status_label.text = "Select scripts and/or scenes to export."
	window.popup_centered()

func _scan_and_refresh() -> void:
	# Find all relevant files
	var gd_scripts = _find_files_recursive("res://", ".gd")
	var cs_scripts = _find_files_recursive("res://", ".cs")
	all_script_paths = gd_scripts + cs_scripts
	all_script_paths.sort()
	
	all_scene_paths = _find_files_recursive("res://", ".tscn")
	all_scene_paths.sort()
	
	# Rebuild internal data models
	_build_script_data_model()
	_render_script_list()
	
	_build_scene_data_model()
	_render_scene_list()

# --- Scripts Model Construction ---
func _build_script_data_model() -> void:
	# Decide between Tree Structure (Depth 0) or Flat Groups (Depth > 0)
	if group_by_folder and group_depth == 0:
		_build_recursive_tree_data(all_script_paths, tree_nodes, "tree_nodes")
	else:
		_build_flat_group_data(all_script_paths, folder_data, group_depth)

# --- Scenes Model Construction ---
func _build_scene_data_model() -> void:
	if scene_group_by_folder and scene_group_depth == 0:
		_build_recursive_tree_data(all_scene_paths, scene_tree_nodes, "scene_tree_nodes")
	else:
		_build_flat_group_data(all_scene_paths, scene_folder_data, scene_group_depth)

# --- Shared Logic ---

func _get_group_dir_for_path(path: String, depth: int) -> String:
	# Helper to find the "virtual" folder path based on the selected depth level
	if depth == 0: return path.get_base_dir()
	
	var clean_path = path.trim_prefix("res://")
	var parts = clean_path.split("/")
	
	if parts.size() - 1 < depth:
		return path.get_base_dir()
		
	var subset = parts.slice(0, depth)
	return "res://" + "/".join(subset)

func _build_flat_group_data(all_paths: Array[String], out_data: Dictionary, depth: int) -> void:
	# Preserves checked state when rebuilding the model
	var old_checked = {}
	for dir in out_data:
		if out_data[dir].has("items"):
			for path in out_data[dir]["items"]:
				if out_data[dir]["items"][path]["is_checked"]:
					old_checked[path] = true

	out_data.clear()

	for path in all_paths:
		var dir = _get_group_dir_for_path(path, depth)
		
		if not out_data.has(dir):
			out_data[dir] = { "is_expanded": true, "is_checked": false, "items": {} }
		
		var is_checked = old_checked.has(path)
		out_data[dir]["items"][path] = {"is_checked": is_checked}
	
	# Determine folder checked state based on children
	for dir in out_data:
		var all_checked = true
		var items = out_data[dir]["items"]
		if items.is_empty(): all_checked = false
		else:
			for path in items:
				if not items[path]["is_checked"]:
					all_checked = false; break
		out_data[dir]["is_checked"] = all_checked

func _build_recursive_tree_data(all_paths: Array[String], out_nodes: Dictionary, state_key_hint: String) -> void:
	var old_state = out_nodes.duplicate(true)
	out_nodes.clear()
	
	# Ensure Root exists
	if not out_nodes.has("res://"):
		var was_expanded = true
		if old_state.has("res://"): was_expanded = old_state["res://"]["is_expanded"]
		out_nodes["res://"] = { 
			"type": "folder", "parent": "", "children": [], 
			"is_expanded": was_expanded, "is_checked": false 
		}

	for file_path in all_paths:
		var was_checked = false
		if old_state.has(file_path): was_checked = old_state[file_path]["is_checked"]
		
		out_nodes[file_path] = {
			"type": "file",
			"parent": file_path.get_base_dir(),
			"children": [],
			"is_expanded": false,
			"is_checked": was_checked
		}
		
		# Build parent folders up to root
		var current_path = file_path
		while current_path != "res://":
			var parent_dir = current_path.get_base_dir()
			
			if out_nodes.has(parent_dir):
				if not out_nodes[parent_dir]["children"].has(current_path):
					out_nodes[parent_dir]["children"].append(current_path)
			else:
				var dir_expanded = true
				if old_state.has(parent_dir): dir_expanded = old_state[parent_dir]["is_expanded"]
				
				out_nodes[parent_dir] = {
					"type": "folder",
					"parent": parent_dir.get_base_dir(),
					"children": [current_path],
					"is_expanded": dir_expanded,
					"is_checked": false
				}
			
			current_path = parent_dir
			if current_path == "res://" and not out_nodes["res://"]["children"].has(current_path):
				# Break loop if we reached root but logic failed, though unusual
				pass

	# Post-process: update folder checkboxes based on children
	for path in out_nodes:
		if out_nodes[path]["type"] == "folder":
			_update_tree_folder_checked_state(path, out_nodes)

func _update_tree_folder_checked_state(folder_path: String, nodes_dict: Dictionary) -> bool:
	if not nodes_dict.has(folder_path): return false
	var node = nodes_dict[folder_path]
	if node["type"] == "file": return node["is_checked"]
	
	if node["children"].is_empty():
		node["is_checked"] = false
		return false
		
	var all_children_checked = true
	for child in node["children"]:
		if not _update_tree_folder_checked_state(child, nodes_dict):
			all_children_checked = false
	
	node["is_checked"] = all_children_checked
	return all_children_checked

# --- Rendering ---

func _render_script_list() -> void:
	script_list.clear()
	if not group_by_folder:
		_render_simple_flat_list(script_list, all_script_paths, folder_data, "script")
	elif group_depth == 0:
		_render_recursive_tree_list(script_list, tree_nodes, "res://", 0, "script")
	else:
		_render_flat_list(script_list, folder_data, "script")

func _render_scene_list() -> void:
	scene_list.clear()
	if not scene_group_by_folder:
		_render_simple_flat_list(scene_list, all_scene_paths, scene_folder_data, "scene")
	elif scene_group_depth == 0:
		_render_recursive_tree_list(scene_list, scene_tree_nodes, "res://", 0, "scene")
	else:
		_render_flat_list(scene_list, scene_folder_data, "scene")

# --- Generic Rendering Helpers ---

func _render_recursive_tree_list(list: ItemList, nodes: Dictionary, current_path: String, indent_level: int, item_type: String) -> void:
	if not nodes.has(current_path): return
	
	var node = nodes[current_path]
	var is_folder = (node["type"] == "folder")
	
	var indent_str = "    ".repeat(indent_level)
	var checkbox = "☑ " if node["is_checked"] else "☐ "
	
	var icon = ""
	var text_name = ""
	
	if is_folder:
		icon = "▾ " if node["is_expanded"] else "▸ "
		if current_path == "res://":
			text_name = "res://"
		else:
			text_name = current_path.get_file() + "/"
	else:
		icon = "    " 
		text_name = current_path.get_file()
	
	list.add_item(indent_str + icon + checkbox + text_name)
	
	var idx = list.get_item_count() - 1
	list.set_item_metadata(idx, {
		"mode": "tree",
		"path": current_path,
		"type": node["type"],
		"item_type": item_type
	})
	
	if is_folder and node["is_expanded"]:
		# Sort folders first, then files
		var folders = []
		var files = []
		for child_path in node["children"]:
			if nodes[child_path]["type"] == "folder":
				folders.append(child_path)
			else:
				files.append(child_path)
		
		folders.sort()
		files.sort()
		
		for f in folders: _render_recursive_tree_list(list, nodes, f, indent_level + 1, item_type)
		for f in files: _render_recursive_tree_list(list, nodes, f, indent_level + 1, item_type)

func _render_flat_list(list: ItemList, data_dict: Dictionary, item_type: String) -> void:
	var sorted_folders = data_dict.keys(); sorted_folders.sort()
	for dir in sorted_folders:
		var folder_info = data_dict[dir]
		var display_dir = dir.replace("res://", "")
		if display_dir == "": display_dir = "res://"
		elif not display_dir.ends_with("/"): display_dir += "/"
		
		var checkbox = "☑ " if folder_info.is_checked else "☐ "
		var expand_symbol = "▾ " if folder_info.is_expanded else "▸ "
		
		list.add_item(expand_symbol + checkbox + display_dir)
		var folder_idx = list.get_item_count() - 1
		list.set_item_metadata(folder_idx, {"mode": "flat", "type": "folder", "dir": dir, "item_type": item_type})

		if folder_info.is_expanded:
			var sorted_items = folder_info.items.keys(); sorted_items.sort()
			for path in sorted_items:
				var item_info = folder_info.items[path]
				var item_checkbox = "☑ " if item_info.is_checked else "☐ "
				
				var display_name = path
				if dir != "res://" and path.begins_with(dir):
					display_name = path.trim_prefix(dir).trim_prefix("/")
				else:
					display_name = path.replace("res://", "")
				
				var indent_str = "        "
				list.add_item(indent_str + item_checkbox + display_name)
				
				var item_idx = list.get_item_count() - 1
				list.set_item_metadata(item_idx, {"mode": "flat", "type": "file", "path": path, "item_type": item_type})

func _render_simple_flat_list(list: ItemList, all_paths: Array[String], data_dict: Dictionary, item_type: String) -> void:
	# Even in simple mode, we try to use the dictionary to maintain checked state consistency
	for path in all_paths:
		var is_checked = false
		
		# Look up check state in the dictionary
		for d in data_dict:
			if data_dict[d].has("items") and data_dict[d]["items"].has(path):
				is_checked = data_dict[d]["items"][path]["is_checked"]
				break
				
		var checkbox = "☑ " if is_checked else "☐ "
		list.add_item(checkbox + path.replace("res://", ""))
		var idx = list.get_item_count() - 1
		list.set_item_metadata(idx, {"mode": "simple", "type": "file", "path": path, "item_type": item_type})

#endregion


#region Signals & Event Handlers
#-----------------------------------------------------------------------------

func _on_manage_formats_pressed() -> void:
	if not is_instance_valid(format_manager_dialog):
		_create_format_manager_dialog()
	
	for child in formats_list_vbox.get_children():
		child.queue_free()
		
	for format_ext in collapsible_formats:
		_add_format_row(format_ext)
		
	format_manager_dialog.popup_centered()

func _on_advanced_settings_pressed() -> void:
	if not is_instance_valid(advanced_settings_dialog):
		_create_advanced_settings_dialog()
	
	# Reset list to current state
	for child in formats_list_vbox.get_children():
		child.queue_free()
		
	for ext in collapsible_formats:
		_add_format_row(ext)
	
	advanced_settings_dialog.popup_centered()

func _on_include_addons_toggled(pressed: bool) -> void:
	include_addons = pressed
	_scan_and_refresh()

func _on_format_dialog_ok() -> void:
	collapsible_formats.clear()
	for child in formats_list_vbox.get_children():
		var line_edit: LineEdit = child.get_child(0)
		var text = line_edit.text.strip_edges()
		if not text.is_empty():
			if not text.begins_with("."):
				text = "." + text
			collapsible_formats.append(text)
	format_manager_dialog.hide()

# --- Shared Interaction Logic ---

func _handle_item_click(list: ItemList, index: int, at_position: Vector2, mouse_button_index: int, 
						tree_dict: Dictionary, flat_dict: Dictionary, is_tree_mode: bool, 
						refresh_callback: Callable, toggle_tree_cb: Callable, toggle_flat_cb: Callable) -> void:
	
	if mouse_button_index != MOUSE_BUTTON_LEFT: return
	var meta = list.get_item_metadata(index)
	if meta.is_empty(): return

	if is_tree_mode and meta["mode"] == "tree":
		var path = meta["path"]
		var node = tree_dict[path]
		
		# Estimate UI zones based on depth
		var depth = 0
		var p = node["parent"]
		while p != "":
			depth += 1
			p = tree_dict[p]["parent"]
			
		var indent_offset = depth * 25
		var arrow_zone = indent_offset + 20
		var checkbox_zone_start = arrow_zone
		
		if node["type"] == "folder":
			# Click on arrow toggles expansion, click elsewhere toggles check
			if at_position.x < checkbox_zone_start:
				node["is_expanded"] = not node["is_expanded"]
			else:
				toggle_tree_cb.call(path, not node["is_checked"])
		else:
			toggle_tree_cb.call(path, not node["is_checked"])
			
	elif meta["mode"] == "flat":
		if meta["type"] == "folder":
			var dir = meta["dir"]
			if at_position.x < 20: 
				flat_dict[dir].is_expanded = not flat_dict[dir].is_expanded
			else:
				flat_dict[dir].is_checked = not flat_dict[dir].is_checked
				for path in flat_dict[dir].items:
					flat_dict[dir].items[path].is_checked = flat_dict[dir].is_checked
		
		elif meta["type"] == "file":
			var path = meta["path"]
			# Find containing dir to update its check state
			var found_dir = ""
			for d in flat_dict:
				if flat_dict[d].items.has(path):
					found_dir = d; break
			
			if found_dir != "":
				flat_dict[found_dir].items[path].is_checked = not flat_dict[found_dir].items[path].is_checked
				
				# Refresh parent folder check status
				var all_checked = true
				for s_path in flat_dict[found_dir].items:
					if not flat_dict[found_dir].items[s_path].is_checked:
						all_checked = false; break
				flat_dict[found_dir].is_checked = all_checked
				
	elif meta["mode"] == "simple":
		# Simple Flat List Mode
		var path = meta["path"]
		for d in flat_dict:
			if flat_dict[d].items.has(path):
				flat_dict[d].items[path].is_checked = not flat_dict[d].items[path].is_checked

	# Re-render to show changes
	refresh_callback.call()

# --- Script Handlers ---

func _on_script_item_clicked(index: int, at_position: Vector2, mouse_button_index: int) -> void:
	_handle_item_click(script_list, index, at_position, mouse_button_index, 
		tree_nodes, folder_data, group_depth == 0, 
		_render_script_list, _toggle_script_tree_checkbox, Callable())

func _toggle_script_tree_checkbox(path: String, new_state: bool) -> void:
	_toggle_generic_tree_checkbox(path, new_state, tree_nodes)

func _on_group_by_folder_toggled(pressed: bool) -> void:
	group_by_folder = pressed
	if is_instance_valid(group_depth_spinbox):
		group_depth_spinbox.editable = pressed
		group_depth_spinbox.modulate.a = 1.0 if pressed else 0.5
	
	if is_instance_valid(expand_all_scripts_button):
		expand_all_scripts_button.disabled = not pressed
		collapse_all_scripts_button.disabled = not pressed

	_build_script_data_model()
	_render_script_list()

func _on_expand_collapse_scripts(do_expand: bool) -> void:
	_expand_collapse_generic(do_expand, group_depth == 0, tree_nodes, folder_data)
	_render_script_list()

func _on_select_all_scripts_toggled() -> void:
	var is_checked = select_all_scripts_checkbox.button_pressed
	if group_depth == 0:
		_toggle_generic_tree_checkbox("res://", is_checked, tree_nodes)
	else:
		_select_all_flat(is_checked, folder_data)
	_render_script_list()

# --- Scene Handlers ---

func _on_scene_item_clicked(index: int, at_position: Vector2, mouse_button_index: int) -> void:
	_handle_item_click(scene_list, index, at_position, mouse_button_index,
		scene_tree_nodes, scene_folder_data, scene_group_depth == 0,
		_render_scene_list, _toggle_scene_tree_checkbox, Callable())

func _toggle_scene_tree_checkbox(path: String, new_state: bool) -> void:
	_toggle_generic_tree_checkbox(path, new_state, scene_tree_nodes)

func _on_scene_group_by_folder_toggled(pressed: bool) -> void:
	scene_group_by_folder = pressed
	if is_instance_valid(scene_group_depth_spinbox):
		scene_group_depth_spinbox.editable = pressed
		scene_group_depth_spinbox.modulate.a = 1.0 if pressed else 0.5
	
	if is_instance_valid(scene_expand_all_button):
		scene_expand_all_button.disabled = not pressed
		scene_collapse_all_button.disabled = not pressed

	_build_scene_data_model()
	_render_scene_list()

func _on_expand_collapse_scenes(do_expand: bool) -> void:
	_expand_collapse_generic(do_expand, scene_group_depth == 0, scene_tree_nodes, scene_folder_data)
	_render_scene_list()

func _on_select_all_scenes_toggled() -> void:
	var is_checked = select_all_scenes_checkbox.button_pressed
	if scene_group_depth == 0:
		_toggle_generic_tree_checkbox("res://", is_checked, scene_tree_nodes)
	else:
		_select_all_flat(is_checked, scene_folder_data)
	_render_scene_list()

# --- Logic Implementation Helpers ---

func _toggle_generic_tree_checkbox(path: String, new_state: bool, nodes: Dictionary) -> void:
	if not nodes.has(path): return
	var node = nodes[path]
	
	node["is_checked"] = new_state
	if node["type"] == "folder":
		for child in node["children"]:
			_toggle_generic_tree_checkbox(child, new_state, nodes)
			
	_update_parent_check_state(node["parent"], nodes)

func _update_parent_check_state(parent_path: String, nodes: Dictionary) -> void:
	# Recursively ensure parent checkboxes reflect the state of their children
	if parent_path == "" or not nodes.has(parent_path): return
	
	var parent = nodes[parent_path]
	var all_checked = true
	for child in parent["children"]:
		if not nodes[child]["is_checked"]:
			all_checked = false; break
	
	if parent["is_checked"] != all_checked:
		parent["is_checked"] = all_checked
		_update_parent_check_state(parent["parent"], nodes)

func _expand_collapse_generic(do_expand: bool, is_tree: bool, tree_dict: Dictionary, flat_dict: Dictionary) -> void:
	if is_tree:
		for path in tree_dict:
			if tree_dict[path]["type"] == "folder":
				tree_dict[path]["is_expanded"] = do_expand
	else:
		for dir in flat_dict:
			flat_dict[dir]["is_expanded"] = do_expand

func _select_all_flat(is_checked: bool, flat_dict: Dictionary) -> void:
	for dir in flat_dict:
		flat_dict[dir].is_checked = is_checked
		for path in flat_dict[dir].items:
			flat_dict[dir].items[path].is_checked = is_checked

#endregion


#region Export Logic
#-----------------------------------------------------------------------------

func _export_selected(to_clipboard: bool) -> void:
	var selected_scripts = _get_selected_script_paths()
	var selected_scenes = _get_selected_scene_paths()
	
	selected_scripts.sort()
	selected_scenes.sort()

	# Handle Autoloads (Singletons)
	# We fetch them first to avoid duplicating code if an Autoload script is also selected manually.
	var autoloads = {"scripts": [], "scenes": []}
	var has_autoloads = false
	
	if include_autoloads:
		autoloads = _get_project_autoloads()
		has_autoloads = not autoloads["scripts"].is_empty() or not autoloads["scenes"].is_empty()
		
		# Filter Scripts: Remove if already in Autoloads
		var unique_scripts: Array[String] = []
		for path in selected_scripts:
			if not path in autoloads["scripts"]:
				unique_scripts.append(path)
		selected_scripts = unique_scripts
		
		# Filter Scenes: Remove if already in Autoloads
		var unique_scenes: Array[String] = []
		for path in selected_scenes:
			if not path in autoloads["scenes"]:
				unique_scenes.append(path)
		selected_scenes = unique_scenes

	# Validation: Ensure we actually have something to export
	if not include_project_godot and not has_autoloads and selected_scripts.is_empty() and selected_scenes.is_empty():
		_set_status_message("Nothing selected to export.", COLOR_WARNING)
		return
		
	var content_text = ""
	
	# 1. Export Project Settings
	if include_project_godot:
		content_text += _build_project_godot_content()

	# 2. Export Autoloads
	if has_autoloads:
		if not content_text.is_empty(): content_text += "\n\n"
		content_text += "--- AUTOLOADS / GLOBALS ---\n\n"
		
		if not autoloads["scripts"].is_empty():
			content_text += _build_scripts_content(autoloads["scripts"], wrap_autoloads_in_markdown)
		
		if not autoloads["scenes"].is_empty():
			if not autoloads["scripts"].is_empty(): content_text += "\n\n"
			content_text += _build_scenes_content(autoloads["scenes"], wrap_autoloads_in_markdown)

	# 3. Export Selected Scripts
	if not selected_scripts.is_empty():
		if not content_text.is_empty(): content_text += "\n\n"
		content_text += "--- SCRIPTS ---\n\n"
		content_text += _build_scripts_content(selected_scripts) 
	
	# 4. Export Selected Scenes
	if not selected_scenes.is_empty():
		if not content_text.is_empty(): content_text += "\n\n"
		content_text += "--- SCENES ---\n\n"
		content_text += _build_scenes_content(selected_scenes)
	
	# Finalize
	var total_lines = content_text.split("\n").size()
	var total_chars = content_text.length()
	var approx_tokens = _estimate_tokens(content_text)
	
	var stats_line = "\nTotal: %d lines, %d characters (~%d tokens)" % [total_lines, total_chars, approx_tokens]
	
	var items_str = "%d script(s), %d scene(s)" % [selected_scripts.size(), selected_scenes.size()]
	if include_project_godot: items_str += ", project.godot"
	if has_autoloads: items_str += " + Globals"

	if to_clipboard:
		DisplayServer.clipboard_set(content_text)
		_set_status_message("Success! Copied " + items_str + "." + stats_line, COLOR_COPY_TEXT)
	else:
		var output_path = "res://context_export.txt"
		var file = FileAccess.open(output_path, FileAccess.WRITE)
		if file:
			file.store_string(content_text)
			_set_status_message("Success! Exported " + items_str + " to " + output_path + "." + stats_line, COLOR_SAVE_TEXT)
		else:
			_set_status_message("Error writing to file!", COLOR_ERROR)

func _set_status_message(text: String, color: Color) -> void:
	status_label.add_theme_color_override("font_color", color)
	status_label.text = text

func _get_project_autoloads() -> Dictionary:
	var result = {"scripts": [], "scenes": []}
	
	for prop in ProjectSettings.get_property_list():
		var name = prop.name
		if name.begins_with("autoload/"):
			var path = ProjectSettings.get_setting(name)
			if path.begins_with("*"):
				path = path.substr(1)
			if path.ends_with(".gd") or path.ends_with(".cs"):
				result["scripts"].append(path)
			elif path.ends_with(".tscn"):
				result["scenes"].append(path)
				
	return result

func _get_selected_script_paths() -> Array[String]:
	return _get_selected_paths_generic(group_depth == 0, tree_nodes, folder_data)

func _get_selected_scene_paths() -> Array[String]:
	return _get_selected_paths_generic(scene_group_depth == 0, scene_tree_nodes, scene_folder_data)

func _get_selected_paths_generic(is_tree: bool, tree_dict: Dictionary, flat_dict: Dictionary) -> Array[String]:
	var selected: Array[String] = []
	if is_tree:
		for path in tree_dict:
			if tree_dict[path]["type"] == "file" and tree_dict[path]["is_checked"]:
				selected.append(path)
	else:
		for dir in flat_dict:
			for path in flat_dict[dir].items:
				if flat_dict[dir].items[path].is_checked:
					selected.append(path)
	return selected

func _estimate_tokens(text: String) -> int:
	if text.is_empty():
		return 0
	return maxi(1, int(text.length() / 4.0))

#endregion


#region Content Formatters
#-----------------------------------------------------------------------------

func _build_project_godot_content() -> String:
	# Constructs a simplified INI-style representation of project.godot.
	# We focus on fields relevant for context (name, main_scene, input map, layers).
	var content = ""
	content += "[application]\n"
	
	var app_name = ProjectSettings.get_setting("application/config/name", "")
	if not app_name.is_empty():
		content += 'config/name="%s"\n' % app_name
	
	var main_scene = ProjectSettings.get_setting("application/run/main_scene", "")
	if not main_scene.is_empty():
		# Resolve UID to actual path for readability
		if main_scene.begins_with("uid://"):
			var uid_id = ResourceUID.text_to_id(main_scene)
			if ResourceUID.has_id(uid_id):
				main_scene = ResourceUID.get_id_path(uid_id)
		content += 'run/main_scene="%s"\n' % main_scene
	content += "\n"

	var autoloads = _get_project_settings_section("autoload")
	if not autoloads.is_empty():
		content += "[autoload]\n"
		for key in autoloads:
			content += '%s="%s"\n' % [key, autoloads[key]]
		content += "\n"

	var groups = _get_project_settings_section("global_group")
	if not groups.is_empty():
		content += "[global_group]\n"
		for key in groups:
			content += '%s="%s"\n' % [key, groups[key]]
		content += "\n"
		
	var layers = _get_project_settings_section("layer_names")
	var active_layers = {}
	for key in layers:
		if not layers[key].is_empty():
			active_layers[key] = layers[key]
	
	if not active_layers.is_empty():
		content += "[layer_names]\n"
		var sorted_keys = active_layers.keys()
		sorted_keys.sort() 
		for key in sorted_keys:
			content += '%s="%s"\n' % [key, active_layers[key]]
		content += "\n"

	var input_section = _generate_clean_input_section()
	if input_section.strip_edges() != "[input]":
		content += input_section + "\n"

	var header = "--- PROJECT.GODOT ---\n\n"
	if wrap_project_godot_in_markdown:
		return header + "```ini\n" + content.strip_edges() + "\n```"
	else:
		return header + content.strip_edges()

func _get_project_settings_section(prefix: String) -> Dictionary:
	var section_data = {}
	for prop in ProjectSettings.get_property_list():
		var prop_name = prop.name
		if prop_name.begins_with(prefix + "/"):
			var key = prop_name.trim_prefix(prefix + "/")
			var value = ProjectSettings.get_setting(prop_name)
			section_data[key] = str(value)
	return section_data

func _build_scripts_content(paths: Array, use_markdown_override = null) -> String:
	var content = ""
	
	var do_wrap = wrap_in_markdown
	if use_markdown_override != null:
		do_wrap = use_markdown_override

	for file_path in paths:
		var file = FileAccess.open(file_path, FileAccess.READ)
		if file:
			var file_content = file.get_as_text()
			content += "--- SCRIPT: " + file_path + " ---\n\n"
			if do_wrap:
				var lang_tag = "gdscript"
				if file_path.ends_with(".cs"):
					lang_tag = "csharp"
				content += "```" + lang_tag + "\n" + file_content + "\n```\n\n"
			else:
				content += file_content + "\n\n"
	return content.rstrip("\n")

func _build_scenes_content(paths: Array, use_markdown_override = null) -> String:
	var do_wrap = wrap_scene_in_markdown
	if use_markdown_override != null:
		do_wrap = use_markdown_override

	var scene_outputs: Array[String] = []
	for file_path in paths:
		var scene_text = file_path.get_file() + ":\n"
		var packed_scene = ResourceLoader.load(file_path)
		if packed_scene is PackedScene:
			var instance = packed_scene.instantiate()
			scene_text += _build_tree_string_for_scene(instance)
			instance.queue_free()
		else:
			scene_text += "Failed to load scene."
		scene_outputs.append(scene_text)
	
	var final_content = "\n\n".join(scene_outputs)
	
	if do_wrap:
		return "```text\n" + final_content + "\n```"
	else:
		return final_content

func _build_tree_string_for_scene(root_node: Node) -> String:
	if not is_instance_valid(root_node): return ""
	
	var root_line = _get_node_info_string(root_node)
	var scene_path = root_node.get_scene_file_path()
	
	# If root matches collapsible format, stop deep recursion
	if collapse_instanced_scenes and _path_ends_with_collapsible_format(scene_path):
		return root_line
	
	var children_lines: Array[String] = []
	var signal_strings = _get_node_signals(root_node)
	var real_children = root_node.get_children()
	
	var has_signals = not signal_strings.is_empty()
	var has_children = not real_children.is_empty()
	
	if has_signals:
		var is_last_item = not has_children
		children_lines.append(_format_signals_block(signal_strings, "", is_last_item))

	# Recurse with node merging logic
	_build_children_lines_grouped(real_children, "", children_lines)

	return root_line + ("\n" if not children_lines.is_empty() else "") + "\n".join(children_lines)

func _build_children_lines_grouped(children: Array[Node], prefix: String, out_lines: Array[String]) -> void:
	# Iterates through children and intelligently groups adjacent identical nodes.
	var count = children.size()
	if count == 0: return

	var i = 0
	while i < count:
		var current_node = children[i]
		var group_size = 1
		
		# Look ahead for duplicates if merging is enabled
		if merge_similar_nodes:
			var j = i + 1
			while j < count:
				var next_node = children[j]
				if _are_nodes_similar(current_node, next_node):
					group_size += 1
					j += 1
				else:
					break
		
		var is_last_item = (i + group_size == count)
		var line_prefix = prefix + ("└── " if is_last_item else "├── ")
		var node_info = _get_node_info_string(current_node)
		
		# Format group indicator (x5)
		if group_size > 1:
			if " (" in node_info:
				node_info = node_info.replace(" (", " [b](x%d)[/b] (" % group_size)
			else:
				node_info += " [b](x%d)[/b]" % group_size
			node_info = node_info.replace("[b]", "").replace("[/b]", "")

		out_lines.append(line_prefix + node_info)
		
		# Recursive step:
		# If we grouped nodes, we only show the children of the FIRST node as an example structure.
		var current_scene_path = current_node.get_scene_file_path()
		var is_collapsed = collapse_instanced_scenes and _path_ends_with_collapsible_format(current_scene_path)
		
		if not is_collapsed:
			var child_prefix = prefix + ("    " if is_last_item else "│   ")
			
			var signal_strings = _get_node_signals(current_node)
			var sub_children = current_node.get_children()
			
			var has_sub_signals = not signal_strings.is_empty()
			var has_sub_children = not sub_children.is_empty()
			
			if has_sub_signals:
				var sig_is_last = not has_sub_children
				out_lines.append(_format_signals_block(signal_strings, child_prefix, sig_is_last))
			
			if has_sub_children:
				_build_children_lines_grouped(sub_children, child_prefix, out_lines)
		
		i += group_size

func _are_nodes_similar(node_a: Node, node_b: Node) -> bool:
	if not is_instance_valid(node_a) or not is_instance_valid(node_b):
		return false
		
	# 1. Check Scene paths
	var scene_a = node_a.get_scene_file_path()
	var scene_b = node_b.get_scene_file_path()
	if not scene_a.is_empty() or not scene_b.is_empty():
		return scene_a == scene_b

	# 2. Check Class and Script
	if node_a.get_class() != node_b.get_class():
		return false
	if node_a.get_script() != node_b.get_script():
		return false
		
	return true

func _format_signals_block(signals: Array, prefix: String, is_last: bool) -> String:
	var connector = "└── " if is_last else "├── "
	var deep_indent = "    " if is_last else "│   "
	
	var result = prefix + connector + "signals: [\n"
	
	for i in range(signals.size()):
		var sig = signals[i]
		var comma = "," if i < signals.size() - 1 else ""
		result += prefix + deep_indent + '  "%s"%s\n' % [sig, comma]
		
	result += prefix + deep_indent + "]"
	return result

func _generate_clean_input_section() -> String:
	# Convert Godot's InputMap dictionary into a human-readable text format.
	# Saves tokens compared to dumping raw InputEvent objects.
	var output = "[input]\n\n"
	var input_props = []
	
	for prop in ProjectSettings.get_property_list():
		if prop.name.begins_with("input/"):
			input_props.append(prop.name)
	
	input_props.sort()
	
	for prop_name in input_props:
		var action_name = prop_name.trim_prefix("input/")
		if action_name.begins_with("ui_"): continue
			
		var setting = ProjectSettings.get_setting(prop_name)
		
		if typeof(setting) == TYPE_DICTIONARY and setting.has("events"):
			var events = setting["events"]
			var events_str_list = []
			
			for event in events:
				var formatted = _format_input_event(event)
				if not formatted.is_empty():
					events_str_list.append(formatted)
			
			if not events_str_list.is_empty():
				output += "%s: %s\n" % [action_name, ", ".join(events_str_list)]
				
	return output.strip_edges()

func _format_input_event(event: InputEvent) -> String:
	if event is InputEventKey:
		var k_code = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		return "Key(%s)" % OS.get_keycode_string(k_code)
		
	elif event is InputEventMouseButton:
		var btn_name = ""
		match event.button_index:
			MOUSE_BUTTON_LEFT: btn_name = "Left"
			MOUSE_BUTTON_RIGHT: btn_name = "Right"
			MOUSE_BUTTON_MIDDLE: btn_name = "Middle"
			MOUSE_BUTTON_WHEEL_UP: btn_name = "WheelUp"
			MOUSE_BUTTON_WHEEL_DOWN: btn_name = "WheelDown"
			MOUSE_BUTTON_WHEEL_LEFT: btn_name = "WheelLeft"
			MOUSE_BUTTON_WHEEL_RIGHT: btn_name = "WheelRight"
			MOUSE_BUTTON_XBUTTON1: btn_name = "XBtn1"
			MOUSE_BUTTON_XBUTTON2: btn_name = "XBtn2"
			_: btn_name = str(event.button_index)
		return "MouseBtn(%s)" % btn_name
		
	elif event is InputEventJoypadButton:
		return "JoyBtn(%s)" % str(event.button_index)
		
	elif event is InputEventJoypadMotion:
		var dir = "+" if event.axis_value > 0 else "-"
		return "JoyAxis(%s%s)" % [str(event.axis), dir]
		
	return ""

func _get_node_signals(node: Node) -> Array:
	var result = []
	var signals_info = node.get_signal_list()
	
	for sig in signals_info:
		var sig_name = sig["name"]
		var connections = node.get_signal_connection_list(sig_name)
		
		for conn in connections:
			var target_obj = conn["callable"].get_object()
			var method_name = conn["callable"].get_method()
			
			if is_instance_valid(target_obj) and target_obj is Node:
				var target_name = target_obj.name
				result.append("%s -> %s :: %s" % [sig_name, target_name, method_name])
				
	result.sort()
	return result

func _get_node_info_string(node: Node) -> String:
	if not is_instance_valid(node): return "<invalid node>"
	
	var node_type = node.get_class()
	var attributes: Array[String] = []
	
	if str(node.name) != node_type: 
		attributes.append('name: "%s"' % node.name)
	
	var scene_path = node.get_scene_file_path()
	if not scene_path.is_empty(): 
		attributes.append('scene: "%s"' % scene_path)
	
	var script = node.get_script()
	if is_instance_valid(script) and not script.resource_path.is_empty():
		attributes.append('script: "%s"' % script.resource_path)
	
	# Groups
	var groups = node.get_groups()
	var user_groups = []
	for g in groups:
		if not str(g).begins_with("_"):
			user_groups.append(str(g))
	
	if not user_groups.is_empty():
		attributes.append("groups: %s" % JSON.stringify(user_groups))
	
	# Inspector Changes
	if include_inspector_changes:
		var changed_props = _get_changed_properties(node)
		if not changed_props.is_empty():
			attributes.append("changes: %s" % JSON.stringify(changed_props))
	
	var attr_str = " (" + ", ".join(attributes) + ")" if not attributes.is_empty() else ""
	return node_type + attr_str

func _get_changed_properties(node: Node) -> Dictionary:
	# Compares current node properties against a fresh instance of the same class
	# to find what has been modified in the Inspector.
	var changed_props = {}
	var default_node = ClassDB.instantiate(node.get_class())
	if not is_instance_valid(default_node): return {}

	for prop in node.get_property_list():
		if prop.usage & PROPERTY_USAGE_STORAGE:
			var prop_name = prop.name
			if prop_name in ["unique_name_in_owner", "script"]: continue

			var current_value = node.get(prop_name)
			var default_value = default_node.get(prop_name)
			
			if typeof(current_value) != typeof(default_value) or current_value != default_value:
				var formatted_value = _format_property_value(current_value)
				if formatted_value != null:
					changed_props[prop_name] = formatted_value
				
	default_node.free()
	return changed_props

func _format_property_value(value: Variant) -> Variant:
	if value == null: return null

	# Simplify Objects to paths
	if typeof(value) == TYPE_OBJECT:
		if not is_instance_valid(value): return null
		if value is Resource and not value.resource_path.is_empty():
			return value.resource_path 
		return null

	# Format Transforms for readability
	if typeof(value) == TYPE_TRANSFORM3D:
		var pos = value.origin
		var rot_deg = value.basis.get_euler() * (180.0 / PI)
		var scale = value.basis.get_scale()
		var f = func(v): return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]
		var parts = []
		if not pos.is_zero_approx(): parts.append("pos: " + f.call(pos))
		if not rot_deg.is_zero_approx(): parts.append("rot: " + f.call(rot_deg))
		if not scale.is_equal_approx(Vector3.ONE): parts.append("scale: " + f.call(scale))
		return ", ".join(parts) if not parts.is_empty() else "Identity"

	if typeof(value) == TYPE_TRANSFORM2D:
		var pos = value.origin
		var rot_deg = value.get_rotation() * (180.0 / PI)
		var scale = value.get_scale()
		var parts = []
		if not pos.is_zero_approx(): parts.append("pos: (%.2f, %.2f)" % [pos.x, pos.y])
		if not is_zero_approx(rot_deg): parts.append("rot: %.2f" % rot_deg)
		if not scale.is_equal_approx(Vector2.ONE): parts.append("scale: (%.2f, %.2f)" % [scale.x, scale.y])
		return ", ".join(parts) if not parts.is_empty() else "Identity"

	# Recursively clean arrays
	if typeof(value) == TYPE_ARRAY:
		var clean_array = []
		for item in value:
			var f_item = _format_property_value(item)
			if f_item != null: clean_array.append(f_item)
		if clean_array.is_empty(): return null
		return clean_array

	if typeof(value) == TYPE_BOOL: return value
	if typeof(value) == TYPE_INT: return value
	if typeof(value) == TYPE_FLOAT: return snappedf(value, 0.001)

	return str(value)

#endregion


#region File System Utilities
#-----------------------------------------------------------------------------

func _path_ends_with_collapsible_format(path: String) -> bool:
	if path.is_empty():
		return false
	for ext in collapsible_formats:
		if path.ends_with(ext):
			return true
	return false

func _find_files_recursive(path: String, extension: String) -> Array[String]:
	var files: Array[String] = []
	# Skip the addons folder unless explicitly enabled to improve performance
	if not include_addons and path.begins_with("res://addons"): return files
	
	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var item = dir.get_next()
		while item != "":
			if item == "." or item == "..":
				item = dir.get_next()
				continue
			
			var full_path = path.path_join(item)
			if dir.current_is_dir():
				files.append_array(_find_files_recursive(full_path, extension))
			elif item.ends_with(extension):
				files.append(full_path)
			
			item = dir.get_next()
	return files

#endregion
