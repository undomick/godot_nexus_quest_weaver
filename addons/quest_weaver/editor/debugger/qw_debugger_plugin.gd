# res://addons/quest_weaver/editor/debugger/qw_debugger_plugin.gd
@tool
class_name QuestWeaverDebuggerPlugin
extends EditorDebuggerPlugin

signal session_started()
signal session_ended()
signal node_activated_in_game(node_id: String)
signal node_completed_in_game(node_id: String)
signal node_failed_in_game(node_id: String)

func _has_capture(capture: String) -> bool:
	return capture == "quest_weaver"

func _setup_session(session_id: int) -> void:
	var session = get_session(session_id)
	if not session.stopped.is_connected(_on_session_stopped):
		session.stopped.connect(_on_session_stopped)

func _on_session_stopped() -> void:
	session_ended.emit()

func _capture(message: String, data: Array, _session_id: int) -> bool:
	var command = message.trim_prefix("quest_weaver:")

	match command:
		"session_started":
			session_started.emit()
			
		"node_activated":
			if not data.is_empty() and (data[0] is String or data[0] is StringName):
				node_activated_in_game.emit(str(data[0]))
				
		"node_completed":
			if not data.is_empty() and (data[0] is String or data[0] is StringName):
				node_completed_in_game.emit(str(data[0]))
				
		"node_failed":
			if not data.is_empty() and (data[0] is String or data[0] is StringName):
				node_failed_in_game.emit(str(data[0]))
	
	return true
