# res://addons/quest_weaver/editor/debugger/quest_weaver_debugger.gd
@tool
class_name QuestWeaverDebugger
extends Node

signal session_started
signal session_ended
signal node_activated_in_game(node_id: StringName)
signal node_completed_in_game(node_id: StringName)
signal node_failed_in_game(node_id: StringName)
signal instance_updated(payload: Dictionary)

var debugger_plugin: QuestWeaverDebuggerPlugin


func _init() -> void:
	debugger_plugin = QuestWeaverDebuggerPlugin.new()

	debugger_plugin.session_started.connect(session_started.emit)
	debugger_plugin.session_ended.connect(session_ended.emit)
	debugger_plugin.node_activated_in_game.connect(node_activated_in_game.emit)
	debugger_plugin.node_completed_in_game.connect(node_completed_in_game.emit)
	debugger_plugin.node_failed_in_game.connect(node_failed_in_game.emit)
	debugger_plugin.instance_updated.connect(instance_updated.emit)


func get_plugin_instance() -> QuestWeaverDebuggerPlugin:
	return debugger_plugin
