# res://addons/quest_weaver/editor/inspector/qw_registry_inspector.gd
@tool
extends EditorInspectorPlugin


func _can_handle(object: Object) -> bool:
	return object is QuestRegistry


func _parse_begin(object: Object) -> void:
	var btn = Button.new()
	btn.text = "Update Registry from Project"
	btn.icon = EditorInterface.get_base_control().get_theme_icon("Reload", "EditorIcons")
	btn.custom_minimum_size.y = 30

	btn.pressed.connect(_on_update_pressed.bind(object as QuestRegistry))

	add_custom_control(btn)


func _on_update_pressed(registry: QuestRegistry) -> void:
	var settings = QWConstants.get_settings()

	if not settings or settings.quest_scan_folder.is_empty():
		push_error(
			"QuestWeaver: Cannot update registry. 'Quest Scan Folder' is not set in QuestWeaverSettings."
		)
		return

	QuestRegistrar.update_registry_from_project(registry, settings.quest_scan_folder)
	EditorInterface.get_resource_filesystem().scan()
