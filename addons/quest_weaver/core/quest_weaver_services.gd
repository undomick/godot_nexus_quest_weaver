## QWLogger, and QWGameState. Components register themselves via register_* methods.
extends Node

signal game_state_ready

signal controller_ready

signal presentation_manager_ready

signal logger_ready

var quest_controller: QuestController = null

var presentation_manager: Node = null

var logger: QWLogger = null

var _game_state_instance: Node = null

# res://addons/quest_weaver/core/quest_weaver_services.gd
## Autoload singleton that holds runtime references to QuestController, PresentationManager,


func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE:
		_on_exit_cleanup()


func _on_exit_cleanup() -> void:
	QWConstants.clear_static_references()
	quest_controller = null
	presentation_manager = null
	logger = null
	_game_state_instance = null


func register_quest_controller(qc: QuestController) -> void:
	if not is_instance_valid(qc):
		return
	if quest_controller == null:
		quest_controller = qc
		controller_ready.emit()


func register_presentation_manager(pm: Node) -> void:
	if not is_instance_valid(pm):
		return
	if presentation_manager == null:
		presentation_manager = pm
		presentation_manager_ready.emit()


func register_logger(p_logger: QWLogger) -> void:
	if not is_instance_valid(p_logger):
		return
	if logger == null:
		logger = p_logger
		logger_ready.emit()


func register_game_state(instance: Node) -> void:
	if not is_instance_valid(instance):
		return
	if not is_instance_valid(_game_state_instance):
		_game_state_instance = instance
		game_state_ready.emit()
	else:
		if logger:
			logger.warn("System", "Attempted to register GameState instance multiple times.")
		else:
			push_warning("[QW] GameState double registration.")


func has_game_state() -> bool:
	return is_instance_valid(_game_state_instance)


func get_game_state() -> Node:
	# Handle freed-but-not-null instance (e.g. after scene change)
	if not is_instance_valid(_game_state_instance):
		if _game_state_instance != null:
			if logger:
				logger.warn("System", "get_game_state called but game state is invalid.")
			else:
				push_warning("[QW] get_game_state called but game state is invalid.")
		return null
	return _game_state_instance
