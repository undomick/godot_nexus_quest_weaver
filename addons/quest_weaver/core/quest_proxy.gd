# res://addons/quest_weaver/core/quest_proxy.gd
class_name QuestProxy
extends RefCounted

## A lightweight wrapper object that acts as a "Remote Control" for a specific quest.
## Instantiated via QuestWeaverGlobal.quest("id").

var _id: StringName
var _controller_weak: WeakRef
var _use_file_logic: bool = false

func _init(p_quest_id: StringName, p_controller: QuestController, p_use_file_logic: bool = false) -> void:
	self._id = p_quest_id
	self._controller_weak = weakref(p_controller)
	self._use_file_logic = p_use_file_logic

func _get(property: StringName) -> Variant:
	if property == &"rewards":
		return get_rewards()
	return null

# ==============================================================================
# STATE ACTIONS
# ==============================================================================

func start() -> void:
	var c = _get_controller()
	if not c: return
	
	if _use_file_logic:
		c.start_quest_file(_id)
	else:
		c.start_quest_id(_id)

func start_with_params(params: Dictionary) -> void:
	var c = _get_controller()
	if not c: return
	
	# Note: start_quest_with_parameters currently expects an ID and resolves internally.
	# We pass the ID we have.
	c.start_quest_with_parameters(_id, params)

func complete() -> void:
	var c = _get_controller()
	if not c: return
	
	if _use_file_logic:
		c.complete_quest_file(_id, true)
	else:
		c.complete_quest_id(_id, true)

func fail() -> void:
	var c = _get_controller()
	if not c: return
	
	if _use_file_logic:
		c.complete_quest_file(_id, false)
	else:
		c.complete_quest_id(_id, false)

func restart() -> void:
	var c = _get_controller()
	if not c: return
	
	if _use_file_logic:
		c.restart_quest_file(_id)
	else:
		c.restart_quest_id(_id)

# ==============================================================================
# STATE QUERIES
# ==============================================================================

func get_state() -> int:
	var c = _get_controller()
	return c.get_quest_state(_id) if c else QWEnums.QuestState.UNAVAILABLE

func make_available() -> void:
	var c = _get_controller()
	if c: c.set_quest_available(_id)

func is_unavailable() -> bool:
	return get_state() == QWEnums.QuestState.UNAVAILABLE

func is_available() -> bool:
	return get_state() == QWEnums.QuestState.AVAILABLE

func is_active() -> bool:
	return get_state() == QWEnums.QuestState.ACTIVE

func is_completed() -> bool:
	return get_state() == QWEnums.QuestState.COMPLETED

func is_failed() -> bool:
	return get_state() == QWEnums.QuestState.FAILED

# ==============================================================================
# DATA ACCESS
# ==============================================================================

func get_variable(key: StringName, default: Variant = null) -> Variant:
	var c = _get_controller()
	if c: return c.get_quest_variable(_id, key, default)
	return default

## Returns the static title (from Blueprint) or resolved runtime title.
func get_title() -> String:
	var c = _get_controller()
	if not c: return ""
	var data = c.get_quest_data(_id)
	return data.get("title", "")

## Returns the current description (runtime override or blueprint).
func get_description() -> String:
	var c = _get_controller()
	if not c: return ""
	var data = c.get_quest_data(_id)
	return data.get("description", "")

## Expose rewards to the Expression system
func get_rewards() -> Dictionary:
	var c = _get_controller()
	if c:
		return c.get_quest_rewards(_id)
	return {}

## Returns active objectives for this quest (for UI display).
func get_active_objectives() -> Array:
	var c = _get_controller()
	if c:
		return c.get_active_objectives_for_quest(_id)
	return []

## Sets a runtime description override for this quest.
func set_description(description: String) -> void:
	var c = _get_controller()
	if c:
		c.set_quest_description_by_quest_id(_id, description)

# ==============================================================================
# INTERNAL
# ==============================================================================

func _get_controller() -> QuestController:
	if _controller_weak:
		return _controller_weak.get_ref() as QuestController
	return null
