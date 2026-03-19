# res://addons/quest_weaver/systems/managers/presentation_manager.gd
class_name PresentationManager

extends Node

signal presentation_completed(request_id: StringName)

var _queue: Array[Dictionary] = []  # Presentation request data dicts

var _is_displaying := false

var _is_force_closing := false

var _registry: PresentationRegistry

var _panel_scene_cache: Dictionary = {}  # scene_path -> PackedScene

var _current_request_id: StringName = &""

var _current_panel_instance: BaseUIPanel = null  # Reference for skipping

## Manages a queue of UI presentations (dialogs, messages, etc.).
## Requires a valid PresentationRegistry at settings.presentation_registry_path.
## Without a valid registry, no presentations are shown and queue_presentation calls are effectively no-ops.

# The signal carries the ID of the node that requested the message


func _ready() -> void:
	var settings = QWConstants.get_settings()
	if is_instance_valid(settings) and ResourceLoader.exists(settings.presentation_registry_path):
		_registry = ResourceLoader.load(settings.presentation_registry_path)
	else:
		push_error("PresentationManager: PresentationRegistry not found!")


func queue_presentation(data: Dictionary) -> void:
	_queue.append(data)

	if not _is_displaying:
		_show_next_in_queue()


func force_close_current() -> void:
	# Called by QuestController when skipping/resetting or on game exit
	_is_force_closing = true
	if is_instance_valid(_current_panel_instance):
		var panel = _current_panel_instance
		# Disconnect defensively; callback uses CONNECT_ONE_SHOT but may not have fired yet
		panel.presentation_completed.disconnect(
			Callable(self, "_on_panel_completed_from_panel").bind(panel)
		)
		# Abort animation before free to avoid orphan StringNames during shutdown
		if panel.has_method("abort_presentation"):
			panel.abort_presentation()
		panel.queue_free()
		_current_panel_instance = null

	if _is_displaying:
		# Emit the signal so the executor loop breaks and the flow continues
		presentation_completed.emit(_current_request_id)
		_is_displaying = false
		_current_request_id = &""

		# Optional: Clear the rest of the queue on skip to avoid "spamming" the next messages
		_queue.clear()
	_is_force_closing = false


func _show_next_in_queue() -> void:
	if _queue.is_empty():
		_is_displaying = false
		return

	if not is_instance_valid(_registry):
		push_warning("PresentationManager: Registry not loaded. Cannot show presentation.")
		_is_displaying = false
		return

	_is_displaying = true
	var data = _queue.pop_front()
	_current_request_id = StringName(str(data.get("_node_id", "")))

	var presentation_type = data.get("type", "Default")
	var template: UIPanelTemplateResource = _registry.entries.get(presentation_type)
	if not is_instance_valid(template):
		push_warning(
			(
				"PresentationManager: No template found for type '%s'. Skipping presentation."
				% presentation_type
			)
		)
		_on_panel_completed()
		return

	var scene_path = template.panel_scene_path

	if not ResourceLoader.exists(scene_path):
		_on_panel_completed()
		return

	var panel_scene: PackedScene = _panel_scene_cache.get(scene_path)
	if panel_scene == null:
		panel_scene = load(scene_path) as PackedScene
		if is_instance_valid(panel_scene):
			_panel_scene_cache[scene_path] = panel_scene
		else:
			_on_panel_completed()
			return

	var panel_instance: BaseUIPanel = panel_scene.instantiate()
	_current_panel_instance = panel_instance

	if not is_instance_valid(panel_instance):
		_on_panel_completed()
		return

	get_tree().root.add_child(panel_instance)
	panel_instance.presentation_completed.connect(
		_on_panel_completed_from_panel.bind(panel_instance), CONNECT_ONE_SHOT
	)
	panel_instance.present(data)


func _on_panel_completed() -> void:
	_on_panel_completed_from_panel(null)


func _on_panel_completed_from_panel(panel_instance: BaseUIPanel = null) -> void:
	if _is_force_closing:
		return
	if is_instance_valid(panel_instance):
		panel_instance.queue_free()
	_current_panel_instance = null
	presentation_completed.emit(_current_request_id)
	_show_next_in_queue()
