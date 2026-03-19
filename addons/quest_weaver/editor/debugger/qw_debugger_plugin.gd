# res://addons/quest_weaver/editor/debugger/qw_debugger_plugin.gd
@tool

class_name QuestWeaverDebuggerPlugin

extends EditorDebuggerPlugin

signal session_started

signal session_ended

signal node_activated_in_game(node_id: StringName)

signal node_completed_in_game(node_id: StringName)

signal node_failed_in_game(node_id: StringName)

signal instance_updated(payload: Dictionary)

const VIEWER_SCENE = preload(
	"res://addons/quest_weaver/editor/debugger/quest_weaver_debugger_viewer.tscn"
)

var _session_id_to_viewer: Dictionary = {}

var _session_stopped_callables: Dictionary = {}


func _has_capture(capture: String) -> bool:
	return capture == "quest_weaver"


func _setup_session(session_id: int) -> void:
	var session = get_session(session_id)
	var callable = _on_session_stopped.bind(session_id)
	_session_stopped_callables[session_id] = callable
	if not session.stopped.is_connected(callable):
		session.stopped.connect(callable)

	var viewer: Control = VIEWER_SCENE.instantiate()
	session.add_session_tab(viewer)
	_session_id_to_viewer[session_id] = viewer


func _on_session_stopped(session_id: int) -> void:
	var viewer = _session_id_to_viewer.get(session_id)
	if is_instance_valid(viewer) and viewer.has_method(&"clear_display"):
		viewer.clear_display()
	_session_id_to_viewer.erase(session_id)
	_session_stopped_callables.erase(session_id)
	session_ended.emit()


func _capture(message: String, data: Array, session_id: int) -> bool:
	var command = message.trim_prefix("quest_weaver:")

	if command == "register" or command == "instance_update":
		var viewer = _session_id_to_viewer.get(session_id)
		if viewer and viewer.has_method(&"on_capture"):
			viewer.on_capture(message, data)
		if command == "instance_update" and data.size() >= 1 and data[0] is Dictionary:
			instance_updated.emit(data[0])
		return true

	match command:
		"session_started":
			session_started.emit()
			return true

		"node_activated":
			if not data.is_empty() and (data[0] is String or data[0] is StringName):
				node_activated_in_game.emit(StringName(data[0]))
			return true

		"node_completed":
			if not data.is_empty() and (data[0] is String or data[0] is StringName):
				node_completed_in_game.emit(StringName(data[0]))
			return true

		"node_failed":
			if not data.is_empty() and (data[0] is String or data[0] is StringName):
				node_failed_in_game.emit(StringName(data[0]))
			return true

		"session_ended":
			return true

		_:
			return false
