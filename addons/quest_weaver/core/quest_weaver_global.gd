# res://addons/quest_weaver/core/quest_weaver_global.gd
extends Node

## Global Event Bus and Facade for Quest Weaver.
## Provides easy access to quest states, variables and flow control.

# --- SIGNALS ---
## Emit when a quest becomes available. Used for Quest Boards.
## Example: QuestWeaverGlobal.quest_became_available.emit("main_quest_act1")
signal quest_became_available(quest_id: StringName)
## Emit when an event is fired. Used for custom events.
## Example: QuestWeaverGlobal.quest_event_fired.emit("custom_event", {"key": "value"})
signal quest_event_fired(event_name: StringName, payload: Dictionary)
## Emit when the player interacts with an object. Connect INTERACT objectives to this.
## Example: QuestWeaverGlobal.interacted_with_object.emit(my_npc_node)
signal interacted_with_object(node: Node)
## Emit when an enemy is killed. Used for KILL objectives.
## Example: QuestWeaverGlobal.enemy_was_killed.emit("rat")
signal enemy_was_killed(enemy_id: StringName)
## Emit when the player enters a location. Used for ENTER_LOCATION objectives.
## Example: QuestWeaverGlobal.entered_location.emit("tavern")
signal entered_location(location_id: StringName)
## Emit when the interaction lock changes. Used for UI updates.
## Example: QuestWeaverGlobal.interaction_lock_changed.emit(true)
signal interaction_lock_changed(is_locked: bool)
## Emit when the progress of an objective changes. Used for UI updates.
## Example: QuestWeaverGlobal.quest_objective_progress_changed.emit("main_quest_act1", "kill_rats", 10, 100)
signal quest_objective_progress_changed(quest_id: StringName, objective_id: StringName, current_progress: int, max_progress: int)
## Emit when the state of an objective changes. Used for UI updates.
## Example: QuestWeaverGlobal.quest_objective_state_changed.emit("main_quest_act1", "kill_rats", ObjectiveResource.Status.COMPLETED)
signal quest_objective_state_changed(quest_id: StringName, objective_id: StringName, new_status: int)

# --- PROPERTIES ---
var is_locked: bool = false
var are_notifications_suppressed: bool = false

var _current_blocker_node_id: StringName = &""
var _controller_weak: WeakRef = null
var debug: QuestDebugProxy

func register_controller(controller: Node) -> void:
	_controller_weak = weakref(controller)
	debug = QuestDebugProxy.new(controller as QuestController)

# ==============================================================================
# 1. STATE QUERIES (Read-Only)
# ==============================================================================

## Checks if a quest is available (Status 1).
## Example: QuestWeaverGlobal.is_quest_available("main_quest_act1")
func is_quest_available(quest_id: StringName) -> bool:
	return get_quest_state(quest_id) == QWEnums.QuestState.AVAILABLE

## Checks if a quest is active (Status 2).
## Example: QuestWeaverGlobal.is_quest_active("main_quest_act1")
func is_quest_active(quest_id: StringName) -> bool:
	return get_quest_state(quest_id) == QWEnums.QuestState.ACTIVE

## Checks if a quest is completed (Status 3).
## Example: QuestWeaverGlobal.is_quest_completed("main_quest_act1")
func is_quest_completed(quest_id: StringName) -> bool:
	return get_quest_state(quest_id) == QWEnums.QuestState.COMPLETED

## Checks if a quest is failed (Status 4).
## Example: QuestWeaverGlobal.is_quest_failed("main_quest_act1")
func is_quest_failed(quest_id: StringName) -> bool:
	return get_quest_state(quest_id) == QWEnums.QuestState.FAILED

## Returns the raw enum value (See QWEnums.QuestState).
## Example: QuestWeaverGlobal.get_quest_state("main_quest_act1")
func get_quest_state(quest_id: StringName) -> int:
	var controller = _get_controller_safe()
	if not controller: return QWEnums.QuestState.UNAVAILABLE
	return controller.get_quest_state(quest_id)

## Returns the rewards for a quest.
## Example: QuestWeaverGlobal.get_quest_rewards("main_quest_act1")
func get_quest_rewards(quest_id: StringName) -> Dictionary:
	var controller = _get_controller_safe()
	if controller:
		return controller.get_quest_rewards(quest_id)
	return {}

## Checks if an objective is completed.
## Example: QuestWeaverGlobal.is_objective_completed("kill_rats")
func is_objective_completed(objective_id: StringName) -> bool:
	var controller = _get_controller_safe()
	if not controller: return false
	
	# Mapping directly to ObjectiveResource.Status for clarity
	return controller.get_objective_status(objective_id) == ObjectiveResource.Status.COMPLETED

## Returns the current progress count of an objective.
## Example: QuestWeaverGlobal.get_objective_progress("kill_rats")
func get_objective_progress(objective_id: StringName) -> int:
	var controller = _get_controller_safe()
	if controller:
		return controller.get_objective_progress(objective_id)
	return 0

## Returns the ObjectiveResource (blueprint) for a given objective ID, or null if not found.
## Use in text expressions via objective('id').item(0) to reference items from another task.
func get_objective_resource(objective_id: StringName) -> ObjectiveResource:
	var controller = _get_controller_safe()
	if controller:
		return controller.get_objective_resource(objective_id)
	return null

## Retrieves a runtime variable from a specific quest instance.
func get_quest_variable(quest_id: StringName, key: StringName, default: Variant = null) -> Variant:
	var controller = _get_controller_safe()
	if controller:
		return controller.get_quest_variable(quest_id, key, default)
	return default

# ==============================================================================
# 2. VARIABLE ACCESS (GameState Bridge)
# ==============================================================================

## Sets a variable in the game state.
## Example: QuestWeaverGlobal.set_variable("player_level", 10)
func set_variable(key: StringName, value: Variant) -> void:
	var gs = _get_gamestate_safe()
	if gs:
		gs.set_variable(key, value)

## Gets a variable from the game state.
## Example: QuestWeaverGlobal.get_variable("player_level")
func get_variable(key: StringName, default: Variant = null) -> Variant:
	var gs = _get_gamestate_safe()
	if gs:
		return gs.get_variable(key, default)
	return default

# ==============================================================================
# 3. MANUAL TRIGGERS & CONTROL
# ==============================================================================

## Marks a quest as available (e.g. for a Quest Board) without starting the logic.
func set_quest_available(quest_id: StringName) -> void:
	var controller = _get_controller_safe()
	if controller: controller.set_quest_available(quest_id)

## Returns a list of all quests that are currently in the AVAILABLE state.
func get_available_quests() -> Array[StringName]:
	var controller = _get_controller_safe()
	if controller: return controller.get_available_quests()
	return []

## Starts a quest by its Logical ID (QuestContext). Auto-loads if registered.
func start_quest_id(quest_id: StringName) -> void:
	var controller = _get_controller_safe()
	if controller: controller.start_quest_id(quest_id)

## Starts a quest by its File Name (without .quest). Does NOT auto-load from registry reliably.
func start_quest_file(file_id: StringName) -> void:
	var controller = _get_controller_safe()
	if controller: controller.start_quest_file(file_id)

## Restarts a quest by ID (Full Reset). Use it for Debug.
func restart_quest_id(quest_id: StringName) -> void:
	var controller = _get_controller_safe()
	if controller: controller.restart_quest_id(quest_id)

func restart_quest_file(file_id: StringName) -> void:
	var controller = _get_controller_safe()
	if controller: controller.restart_quest_file(file_id)

## Starts a quest with parameters (Templates). Uses Logical ID preference.
func start_quest_with_parameters(quest_id: StringName, params: Dictionary) -> void:
	var controller = _get_controller_safe()
	if controller: controller.start_quest_with_parameters(quest_id, params)

## Completes a quest. Success=true -> COMPLETED, Success=false -> FAILED.
func complete_quest_id(quest_id: StringName, success: bool = true) -> void:
	var controller = _get_controller_safe()
	if controller: controller.complete_quest_id(quest_id, success)

func complete_quest_file(file_id: StringName, success: bool = true) -> void:
	var controller = _get_controller_safe()
	if controller: controller.complete_quest_file(file_id, success)

## Manually completes a specific objective by ID.
func complete_objective(objective_id: StringName) -> void:
	var controller = _get_controller_safe()
	if controller: controller.set_manual_objective_status(objective_id, ObjectiveResource.Status.COMPLETED)

## Debug: Jump to node
func jump_to_node(node_id: StringName) -> void:
	var controller = _get_controller_safe()
	if controller: controller.jump_to_node(node_id)

# ==============================================================================
# 4. SAVE / LOAD (Unified API)
# ==============================================================================

## Returns a combined save dictionary for quest state and game state (variables, kill counts).
## Use this when saving your game. Store the result in your save file.
## Example: var save_data = QuestWeaverGlobal.get_quest_save_data()
func get_quest_save_data() -> Dictionary:
	var result: Dictionary = {}
	var controller = _get_controller_safe()
	var gs = _get_gamestate_safe()
	if controller:
		var quest_data = controller.get_save_data()
		result["version"] = quest_data.get("version", "1.0")
		result["instances"] = quest_data.get("instances", [])
	if gs:
		var gs_data = gs.get_save_data()
		result["variables"] = gs_data.get("variables", {})
		result["quest_states"] = gs_data.get("quest_states", {})
		result["kill_counts"] = gs_data.get("kill_counts", {})
	return result

## Restores quest state and game state from a previously saved dictionary.
## Call this when loading your game, before or right after the QuestController is ready.
## Example: QuestWeaverGlobal.load_quest_data(save_data["quest_weaver"])
func load_quest_data(data: Dictionary) -> void:
	var controller = _get_controller_safe()
	var gs = _get_gamestate_safe()
	if controller:
		var quest_part = {
			"version": data.get("version", "1.0"),
			"instances": data.get("instances", [])
		}
		controller.load_from_data(quest_part)
	if gs:
		var gs_part = {
			"variables": data.get("variables", {}),
			"quest_states": data.get("quest_states", {}),
			"kill_counts": data.get("kill_counts", {})
		}
		gs.load_from_data(gs_part)

## Returns active objectives for a quest (for UI display).
func get_active_objectives(quest_id: StringName) -> Array:
	var controller = _get_controller_safe()
	if controller:
		return controller.get_active_objectives_for_quest(quest_id)
	return []

## Sets a runtime description override for a quest (by quest_id or node_id).
func set_quest_description(quest_or_node_id: StringName, description: String) -> void:
	var controller = _get_controller_safe()
	if controller: controller.set_quest_description_by_quest_id(quest_or_node_id, description)

# ==============================================================================
# 5. FLOW CONTROL (Locking & Skipping)
# ==============================================================================

## Call this to force-skip the currently blocking action (Cutscene/Dialog).
func skip_action() -> void:
	if is_locked and _current_blocker_node_id != &"":
		var controller = _get_controller_safe()
		if controller:
			controller.force_skip_node(_current_blocker_node_id)

## Internal: Called by Nodes.
func lock_interaction(node_id: StringName) -> void:
	if is_locked: return
	is_locked = true
	_current_blocker_node_id = node_id
	interaction_lock_changed.emit(true)

## Internal: Called by Nodes.
func unlock_interaction(node_id: StringName) -> void:
	if _current_blocker_node_id == node_id:
		is_locked = false
		_current_blocker_node_id = &""
		interaction_lock_changed.emit(false)

# ==============================================================================
# INTERNAL HELPERS
# ==============================================================================

func _get_controller_safe() -> QuestController:
	if _controller_weak:
		return _controller_weak.get_ref() as QuestController
	return null

func _get_gamestate_safe() -> QWGameState:
	# Fallback lookup if services aren't injected
	var services = get_tree().root.get_node_or_null("QuestWeaverServices")
	if services and services.has_method("get_game_state"):
		return services.get_game_state() as QWGameState
	return null

## Gracefully shuts down the Quest Weaver system and then quits the application.
## Use this instead of get_tree().quit() to prevent memory leaks in debug builds.
func quit_game() -> void:
	var controller = _get_controller_safe()
	if is_instance_valid(controller) and controller.has_method("shutdown"):
		controller.shutdown()
	
	await get_tree().process_frame
	get_tree().quit()

## Returns a proxy via Quest ID (Registry Lookup).
## Usage: QuestWeaverGlobal.quest_id("the_rat_killer").start()
func quest_id(quest_id: StringName) -> QuestProxy:
	var controller = _get_controller_safe()
	if controller:
		return QuestProxy.new(quest_id, controller, false)
	return QuestProxy.new(quest_id, null, false)

## Returns a proxy via Filename (Direct File Access).
## Usage: QuestWeaverGlobal.quest_file("main_quest_act1").start()
func quest_file(filename_id: StringName) -> QuestProxy:
	var controller = _get_controller_safe()
	if controller:
		return QuestProxy.new(filename_id, controller, true)
	return QuestProxy.new(filename_id, null, true)
