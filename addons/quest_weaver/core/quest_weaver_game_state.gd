## Registers with QuestWeaverServices and listens to enemy_was_killed for KILL objectives.
class_name QWGameState

extends Node

signal kill_count_changed

# Dictionary[StringName, Variant]
var variables: Dictionary = {}

var quest_states: Dictionary = {}

# Dictionary[String, int] - enemy_id -> kill count (persisted)
var kill_counts: Dictionary = {}

# res://addons/quest_weaver/core/quest_weaver_game_state.gd
## Autoload singleton for game state: variables, quest status, and kill counts.


func _ready() -> void:
	var services = get_tree().root.get_node_or_null("QuestWeaverServices")
	if services:
		services.register_game_state(self)
	var global_bus = get_tree().root.get_node_or_null("QuestWeaverGlobal")
	if (
		is_instance_valid(global_bus)
		and not global_bus.enemy_was_killed.is_connected(_on_enemy_was_killed)
	):
		global_bus.enemy_was_killed.connect(_on_enemy_was_killed)


# --- Variable Management ---

## Gets a variable from the game state.


## Example: QWGameState.get_variable("player_level")
func get_variable(key: StringName, default = null) -> Variant:
	return variables.get(key, default)


## Sets a variable in the game state.
## Example: QWGameState.set_variable("player_level", 10)
func set_variable(key: StringName, value: Variant) -> void:
	variables[key] = value


## Checks if a variable exists in the game state.
## Example: QWGameState.has_variable("player_level")
func has_variable(key: StringName) -> bool:
	return variables.has(key)


# --- Quest Status Management ---

## Gets the status of a quest.


## Example: QWGameState.get_quest_status("main_quest_act1")
func get_quest_status(quest_id: StringName) -> int:
	return quest_states.get(quest_id, QWEnums.QuestState.UNAVAILABLE)


## Sets the status of a quest.
## Example: QWGameState.set_quest_status("main_quest_act1", QWEnums.QuestState.ACTIVE)
func set_quest_status(quest_id: StringName, status: int) -> void:
	quest_states[quest_id] = status


# --- Kill Tracking ---

## Returns the kill count for the given enemy_id. Used by KILL objectives.


func count_kill(enemy_id: StringName) -> int:
	return kill_counts.get(str(enemy_id), 0)


func _on_enemy_was_killed(enemy_id: StringName) -> void:
	var key = String(enemy_id)
	kill_counts[key] = kill_counts.get(key, 0) + 1
	kill_count_changed.emit()


# --- Save/Load Support ---

## Normalizes dictionary keys to StringName (JSON often yields String keys).


static func _normalize_keys_to_stringname(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in d:
		out[StringName(str(k))] = d[k]
	return out


## Serializes variables, quest_states, and kill_counts for persistence.
func get_save_data() -> Dictionary:
	return {
		"variables": variables.duplicate(true),
		"quest_states": quest_states.duplicate(true),
		"kill_counts": kill_counts.duplicate()
	}


## Restores variables, quest_states, and kill_counts from a previously saved dictionary.
func load_from_data(data: Dictionary) -> void:
	if data == null:
		push_warning("QWGameState: load_from_data called with null.")
		return
	var v = data.get("variables", {})
	var qs = data.get("quest_states", {})
	var kc = data.get("kill_counts", {})
	variables = _normalize_keys_to_stringname(v if v is Dictionary else {}).duplicate(true)
	quest_states = _normalize_keys_to_stringname(qs if qs is Dictionary else {}).duplicate(true)
	kill_counts = _normalize_keys_to_stringname(kc if kc is Dictionary else {}).duplicate()
