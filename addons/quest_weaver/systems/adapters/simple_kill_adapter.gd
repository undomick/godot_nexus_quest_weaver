# res://addons/quest_weaver/systems/adapters/simple_kill_adapter.gd
@tool
class_name SimpleKillAdapter
extends QuestKillAdapterBase

var _kill_controller: Node = null
var _is_initialized_successfully := false
var _pending_game_state_connection := false


func initialize() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if not is_instance_valid(tree):
		push_error(
			"QuestWeaver (SimpleKillAdapter): Could not get SceneTree access. Adapter will not function."
		)
		return
	# 1. Try explicit kill_controller in scene (for custom implementations)
	_kill_controller = tree.get_first_node_in_group("kill_controller")
	if not is_instance_valid(_kill_controller):
		# 2. Fallback: use QWGameState (built-in kill tracking, out-of-the-box)
		var services = tree.root.get_node_or_null("QuestWeaverServices")
		if is_instance_valid(services):
			if services.has_game_state():
				_kill_controller = services.get_game_state()
			else:
				_pending_game_state_connection = true
				if not services.game_state_ready.is_connected(_on_game_state_ready):
					services.game_state_ready.connect(_on_game_state_ready)
	if not is_instance_valid(_kill_controller):
		if not _pending_game_state_connection:
			push_warning(
				"QuestWeaver (SimpleKillAdapter): No node in group 'kill_controller' and no QuestWeaverGameState registered. Add one for KILL objectives to work."
			)
		return
	_finish_initialization(tree)


func _on_game_state_ready() -> void:
	if not _pending_game_state_connection:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if not is_instance_valid(tree):
		return
	var services = tree.root.get_node_or_null("QuestWeaverServices")
	if not is_instance_valid(services):
		return
	_kill_controller = services.get_game_state()
	if not is_instance_valid(_kill_controller):
		return  # Stay subscribed; may get another signal when GameState registers
	_pending_game_state_connection = false
	if services.game_state_ready.is_connected(_on_game_state_ready):
		services.game_state_ready.disconnect(_on_game_state_ready)
	_finish_initialization(tree)


func _finish_initialization(tree: SceneTree) -> void:
	if not is_instance_valid(_kill_controller):
		return
	if (
		_kill_controller.has_signal(&"kill_count_changed")
		and not _kill_controller.is_connected(
			&"kill_count_changed", Callable(self, "_on_kill_count_changed")
		)
	):
		_kill_controller.connect(&"kill_count_changed", Callable(self, "_on_kill_count_changed"))
	_is_initialized_successfully = true
	var services = tree.root.get_node_or_null("QuestWeaverServices")
	if is_instance_valid(services) and services.logger:
		services.logger.log("Flow", "SimpleKillAdapter initialized successfully.")


func _on_kill_count_changed() -> void:
	kills_updated.emit()


func count_kill(enemy_id: StringName) -> int:
	if not _is_initialized_successfully or not is_instance_valid(_kill_controller):
		return 0
	if _kill_controller.has_method(&"count_kill"):
		return _kill_controller.count_kill(str(enemy_id))
	return 0
