# res://addons/quest_weaver/plugin.gd
@tool
class_name QuestWeaverPlugin
extends EditorPlugin

const _PLUGIN_ICON = preload("assets/icons/icon.svg")

var main_view: QuestWeaverEditor = null
var editor_data: QuestEditorData
var validator_dock: QuestWeaverValidator
var debugger_node: QuestWeaverDebugger
var import_plugin: EditorImportPlugin
var export_plugin: EditorExportPlugin
var saver: ResourceFormatSaver

var registry_inspector: EditorInspectorPlugin
var translation_parser: EditorTranslationParserPlugin

var _save_debounce_timer: Timer
var _cached_version: String = ""


func _enable_plugin() -> void:
	var base_path = get_plugin_path()
	var global_path = base_path + "/core/quest_weaver_global.gd"
	var services_path = base_path + "/core/quest_weaver_services.gd"
	var gamestate_path = base_path + "/core/quest_weaver_game_state.gd"

	add_autoload_singleton("QuestWeaverGlobal", global_path)
	add_autoload_singleton("QuestWeaverServices", services_path)
	add_autoload_singleton("QuestWeaverGameState", gamestate_path)
	_load_editor_data()


func _disable_plugin() -> void:
	if Engine.is_editor_hint() and is_instance_valid(_save_debounce_timer):
		_save_debounce_timer.stop()
		_flush_project_settings()
	# Clear static refs and main_view EARLY (before remove_custom_type) to reduce "resources still in use" at exit
	if Engine.is_editor_hint():
		QuestValidator.clear_graph_cache()
		# Script cache cleared in _tear_down_main_view AFTER data_manager.clear_all()
		QWConstants.clear_static_references()
		QWEditorUtils.clear_cache()
		var ei = get_editor_interface()
		if is_instance_valid(ei):
			var insp = ei.get_inspector()
			if is_instance_valid(insp) and insp.has_method("edit"):
				insp.edit(null)
		if is_instance_valid(registry_inspector):
			remove_inspector_plugin(registry_inspector)
			registry_inspector = null
		# Free main_view and all ConditionResource refs BEFORE remove_custom_type
		_tear_down_main_view()
		remove_custom_type(QWConstants.RESOURCE_TYPE_NAME)
	# Remove format saver early; during editor shutdown it may already be cleared if we wait for _exit_tree
	if Engine.is_editor_hint() and is_instance_valid(saver):
		ResourceSaver.remove_resource_format_saver(saver)
		saver = null
	remove_autoload_singleton("QuestWeaverGameState")
	remove_autoload_singleton("QuestWeaverGlobal")
	remove_autoload_singleton("QuestWeaverServices")


## Tears down main_view and releases all editor refs. Idempotent: safe to call multiple times.
## Called from both _disable_plugin and _exit_tree; Godot's plugin shutdown order is undefined.
func _tear_down_main_view() -> void:
	if not is_instance_valid(main_view):
		return
	if is_instance_valid(editor_data):
		if is_instance_valid(main_view.side_panel):
			editor_data.open_files = main_view.side_panel.get_open_files()
		if is_instance_valid(main_view.data_manager):
			editor_data.last_focused_file = main_view.data_manager.get_active_graph_path()
		if not editor_data.resource_path.is_empty():
			var err = ResourceSaver.save(editor_data, editor_data.resource_path)
			if err != OK:
				push_warning("QuestWeaver: Failed to save editor data on exit (error %d)." % err)
		editor_data = null
	_make_visible(false)
	if (
		is_instance_valid(main_view.properties_panel)
		and main_view.properties_panel.has_method("clear_inspection")
	):
		main_view.properties_panel.clear_inspection()
	if is_instance_valid(main_view.get_history()):
		main_view.get_history().cleanup()
	if (
		is_instance_valid(main_view.graph_controller)
		and main_view.graph_controller.has_method("clear_visual_graph_sync")
	):
		main_view.graph_controller.clear_visual_graph_sync()
	if is_instance_valid(main_view.data_manager):
		main_view.data_manager.clear_all()
	GraphNodeResource.clear_script_cache()
	if main_view._clipboard:
		main_view._clipboard.clear()
	var parent = main_view.get_parent()
	if is_instance_valid(parent):
		parent.remove_child(main_view)
	main_view.free()
	main_view = null


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		import_plugin = QuestWeaverImportPlugin.new()
		export_plugin = QuestWeaverExportPlugin.new()
		saver = QWFormat.QuestGraphFormatSaver.new()
		add_import_plugin(import_plugin)
		add_export_plugin(export_plugin)
		ResourceSaver.add_resource_format_saver(saver)

		add_custom_type(
			QWConstants.RESOURCE_TYPE_NAME, "Resource", QuestGraphResource, _PLUGIN_ICON
		)

		var base_control = EditorInterface.get_base_control()
		validator_dock = base_control.find_child(QWConstants.VALIDATOR_DOCK_NAME, true, false)

		if not is_instance_valid(validator_dock):
			validator_dock = QWConstants.ValidatorDockScene.instantiate()
			validator_dock.name = QWConstants.VALIDATOR_DOCK_NAME
			add_control_to_bottom_panel(validator_dock, "Quest Validator")

		var inspector_script = load(
			"res://addons/quest_weaver/editor/inspector/qw_registry_inspector.gd"
		)
		if inspector_script:
			registry_inspector = inspector_script.new()
			add_inspector_plugin(registry_inspector)

		debugger_node = QuestWeaverDebugger.new()
		debugger_node.name = "QuestWeaverDebuggerHost"
		add_child(debugger_node)
		add_debugger_plugin(debugger_node.get_plugin_instance())

		translation_parser = QuestWeaverTranslationParser.new()
		add_translation_parser_plugin(translation_parser)

		_save_debounce_timer = Timer.new()
		_save_debounce_timer.one_shot = true
		_save_debounce_timer.wait_time = 0.5
		_save_debounce_timer.timeout.connect(_flush_project_settings)
		add_child(_save_debounce_timer)

		call_deferred(&"_connect_filesystem_signals")


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		_disconnect_signals()
		# Teardown is idempotent; order of _disable_plugin vs _exit_tree is undefined
		_tear_down_main_view()

		var base_control = EditorInterface.get_base_control()
		if is_instance_valid(base_control):
			var dock_to_remove = base_control.find_child(
				QWConstants.VALIDATOR_DOCK_NAME, true, false
			)
			if is_instance_valid(dock_to_remove):
				remove_control_from_bottom_panel(dock_to_remove)
				dock_to_remove.free()
			elif is_instance_valid(validator_dock):
				# find_child returned null (dock may be orphaned); free directly to avoid leak
				validator_dock.free()
			validator_dock = null
		elif is_instance_valid(validator_dock):
			# base_control null; free directly to avoid leak
			validator_dock.free()
			validator_dock = null
		if is_instance_valid(debugger_node):
			if is_instance_valid(debugger_node.get_plugin_instance()):
				remove_debugger_plugin(debugger_node.get_plugin_instance())
			debugger_node.free()
		debugger_node = null
		if is_instance_valid(registry_inspector):
			remove_inspector_plugin(registry_inspector)
			registry_inspector = null
		if is_instance_valid(translation_parser):
			remove_translation_parser_plugin(translation_parser)
			translation_parser = null

		# Run synchronously to avoid call_deferred executing on destroyed plugin during editor shutdown
		_do_plugin_cleanup()


func _do_plugin_cleanup() -> void:
	# Format saver is removed in _disable_plugin only; avoid remove here (can fail with "i >= saver_count" during editor shutdown)
	if is_instance_valid(export_plugin):
		remove_export_plugin(export_plugin)
	if is_instance_valid(import_plugin):
		remove_import_plugin(import_plugin)
	import_plugin = null
	export_plugin = null
	saver = null


func _load_editor_data() -> QuestEditorData:
	var path = QWConstants.get_settings().editor_data_path
	if ResourceLoader.exists(path):
		return ResourceLoader.load(path, "QuestEditorData", ResourceLoader.CACHE_MODE_REPLACE)
	else:
		var new_data = QuestEditorData.new()
		var save_err = ResourceSaver.save(new_data, path)
		if save_err != OK:
			push_error("QuestWeaver: Could not save new editor_data resource at '%s'" % path)
		return new_data


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool):
	if not Engine.is_editor_hint():
		return  # Runtime protection
	if not visible:
		if is_instance_valid(main_view):
			main_view.cancel_any_active_drags()

			main_view.visible = false
			if is_instance_valid(main_view.properties_panel):
				main_view.properties_panel.hide()
		return

	if not is_instance_valid(main_view):
		editor_data = _load_editor_data()
		main_view = QWConstants.MainViewScene.instantiate()
		EditorInterface.get_editor_main_screen().add_child(main_view)

		_connect_signals()

		# Get the EditorInterface instance
		var editor_interface = get_editor_interface()

		# Pass the editor_interface instance to the initialize function
		main_view.call_deferred(&"initialize", self, editor_data, editor_interface)

		if editor_interface:
			main_view.set_editor_scale(editor_interface.get_editor_scale())

	main_view.visible = true


func _handles(object: Object) -> bool:
	return object is QuestGraphResource


func _build() -> bool:
	if not Engine.is_editor_hint():
		return true  # Runtime protection
	if is_instance_valid(main_view) and main_view.is_node_ready():
		var action_handler = main_view.get_action_handler()

		if is_instance_valid(action_handler):
			action_handler.save_all_modified_graphs()

	return true


func _edit(object: Object) -> void:
	if not Engine.is_editor_hint():
		return  # Runtime protection
	if object is QuestGraphResource:
		_make_visible(true)
		# Defer so initialize() runs first when main_view was just created
		main_view.call_deferred(&"edit_graph", object.resource_path)


func _connect_filesystem_signals() -> void:
	var editor_interface = get_editor_interface()
	if editor_interface:
		var fs = editor_interface.get_resource_filesystem()
		if not fs:
			return

		if not fs.filesystem_changed.is_connected(_on_filesystem_changed):
			fs.filesystem_changed.connect(_on_filesystem_changed)


func _connect_signals() -> void:
	if not Engine.is_editor_hint():
		return  # Runtime protection
	if is_instance_valid(validator_dock) and is_instance_valid(main_view):
		validator_dock.set_open_files_provider(Callable(main_view.side_panel, "get_open_files"))
		if not validator_dock.validation_requested.is_connected(main_view._on_validation_requested):
			validator_dock.validation_requested.connect(main_view._on_validation_requested)
		if not validator_dock.result_selected.is_connected(
			main_view._on_validation_result_selected
		):
			validator_dock.result_selected.connect(main_view._on_validation_result_selected)
		if not main_view.validation_finished.is_connected(validator_dock.display_results):
			main_view.validation_finished.connect(validator_dock.display_results)

	if is_instance_valid(debugger_node) and is_instance_valid(main_view):
		if not debugger_node.session_started.is_connected(main_view._on_debug_session_started):
			debugger_node.session_started.connect(main_view._on_debug_session_started)
		if not debugger_node.session_ended.is_connected(main_view._on_debug_session_ended):
			debugger_node.session_ended.connect(main_view._on_debug_session_ended)
		if not debugger_node.node_activated_in_game.is_connected(
			main_view._on_debug_node_activated
		):
			debugger_node.node_activated_in_game.connect(main_view._on_debug_node_activated)
		if not debugger_node.node_completed_in_game.is_connected(
			main_view._on_debug_node_completed
		):
			debugger_node.node_completed_in_game.connect(main_view._on_debug_node_completed)
		if debugger_node.has_signal("node_failed_in_game"):
			if not debugger_node.node_failed_in_game.is_connected(main_view._on_debug_node_failed):
				debugger_node.node_failed_in_game.connect(main_view._on_debug_node_failed)
		if not debugger_node.instance_updated.is_connected(main_view._on_debug_instance_updated):
			debugger_node.instance_updated.connect(main_view._on_debug_instance_updated)


func _disconnect_signals() -> void:
	if not Engine.is_editor_hint():
		return
	var editor_interface = get_editor_interface()

	if is_instance_valid(editor_interface):
		var fs = editor_interface.get_resource_filesystem()
		if is_instance_valid(fs):
			if fs.is_connected("filesystem_changed", _on_filesystem_changed):
				fs.filesystem_changed.disconnect(_on_filesystem_changed)

	if is_instance_valid(validator_dock) and is_instance_valid(main_view):
		if validator_dock.is_connected("validation_requested", main_view._on_validation_requested):
			validator_dock.validation_requested.disconnect(main_view._on_validation_requested)
		if validator_dock.is_connected("result_selected", main_view._on_validation_result_selected):
			validator_dock.result_selected.disconnect(main_view._on_validation_result_selected)
		if main_view.is_connected("validation_finished", validator_dock.display_results):
			main_view.validation_finished.disconnect(validator_dock.display_results)

	if is_instance_valid(debugger_node) and is_instance_valid(main_view):
		if debugger_node.session_started.is_connected(main_view._on_debug_session_started):
			debugger_node.session_started.disconnect(main_view._on_debug_session_started)
		if debugger_node.session_ended.is_connected(main_view._on_debug_session_ended):
			debugger_node.session_ended.disconnect(main_view._on_debug_session_ended)
		if debugger_node.node_activated_in_game.is_connected(main_view._on_debug_node_activated):
			debugger_node.node_activated_in_game.disconnect(main_view._on_debug_node_activated)
		if debugger_node.node_completed_in_game.is_connected(main_view._on_debug_node_completed):
			debugger_node.node_completed_in_game.disconnect(main_view._on_debug_node_completed)
		if (
			debugger_node.has_signal("node_failed_in_game")
			and debugger_node.node_failed_in_game.is_connected(main_view._on_debug_node_failed)
		):
			debugger_node.node_failed_in_game.disconnect(main_view._on_debug_node_failed)
		if debugger_node.instance_updated.is_connected(main_view._on_debug_instance_updated):
			debugger_node.instance_updated.disconnect(main_view._on_debug_instance_updated)


func _on_filesystem_changed() -> void:
	if not Engine.is_editor_hint():
		return

	if is_instance_valid(main_view) and main_view.has_method("validate_open_files_exist"):
		main_view.call_deferred(&"validate_open_files_exist")


func save_setting(key: String, value: Variant) -> void:
	if not Engine.is_editor_hint():
		return  # Runtime protection
	var setting_key = "plugins/quest_weaver/%s" % key
	var editor_settings = get_editor_interface().get_editor_settings()
	editor_settings.set_setting(setting_key, value)
	if is_instance_valid(_save_debounce_timer):
		_save_debounce_timer.start()
	else:
		ProjectSettings.save()


func _flush_project_settings() -> void:
	ProjectSettings.save()


func load_setting(key: String, default_value: Variant) -> Variant:
	if not Engine.is_editor_hint():
		return  # Runtime protection
	var setting_key = "plugins/quest_weaver/%s" % key
	var editor_settings = get_editor_interface().get_editor_settings()

	if editor_settings.has_setting(setting_key):
		return editor_settings.get_setting(setting_key)
	else:
		return default_value


func get_plugin_path() -> String:
	return get_script().resource_path.get_base_dir()


func _get_plugin_name() -> String:
	return "QuestWeaver"


func _get_plugin_icon() -> Texture2D:
	return _PLUGIN_ICON


func get_version() -> String:
	if _cached_version.is_empty():
		var config := ConfigFile.new()
		var err := config.load(get_plugin_path() + "/plugin.cfg")
		if err == OK:
			_cached_version = config.get_value("plugin", "version", "0.0.0")
	return _cached_version
