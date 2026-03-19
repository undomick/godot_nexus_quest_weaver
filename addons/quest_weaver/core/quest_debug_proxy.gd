# res://addons/quest_weaver/core/quest_debug_proxy.gd
class_name QuestDebugProxy
extends RefCounted

## Debug proxy for quest state inspection. Exposed via QuestWeaverGlobal.debug.
## Only available when QuestController is registered; check before use.
## Methods: dump_state, complete_active_tasks, set_var, jump_to_node, list_quests, list_active_instances.

var _controller_weak: WeakRef


func _init(controller: QuestController):
	_controller_weak = weakref(controller)


func _get_controller() -> QuestController:
	if _controller_weak:
		return _controller_weak.get_ref() as QuestController
	return null


# --- API ---


## Prints the current state of the quest instance (variables, nodes, objectives).
func dump_state(quest_id: StringName) -> void:
	var c = _get_controller()
	if c:
		c._debug_dump_quest_state(quest_id)
	else:
		push_warning(
			"[QuestDebugProxy] Controller not available. Cannot dump state for '%s'." % quest_id
		)


## Marks all active task objectives as completed for the given quest.
func complete_active_tasks(quest_id: StringName) -> void:
	var c = _get_controller()
	if c:
		c._debug_complete_active_tasks(quest_id)
	else:
		push_warning(
			"[QuestDebugProxy] Controller not available. Cannot complete tasks for '%s'." % quest_id
		)


## Sets a quest variable. Use for debugging or testing.
func set_var(quest_id: StringName, key: StringName, value: Variant) -> void:
	var c = _get_controller()
	if c:
		c._debug_set_variable(quest_id, key, value)
	else:
		push_warning(
			"[QuestDebugProxy] Controller not available. Cannot set variable for '%s'." % quest_id
		)


## Forces the flow to jump to a specific node ID (Use Node ID from Editor).
func jump_to_node(node_id: StringName) -> void:
	var c = _get_controller()
	if c:
		c.jump_to_node(node_id)
	else:
		push_warning(
			"[QuestDebugProxy] Controller not available. Cannot jump to node '%s'." % node_id
		)


## Prints all registered quest IDs and their paths (and status if instance is active).
func list_quests() -> void:
	var c = _get_controller()
	if c:
		c._debug_list_quests()
	else:
		push_warning("[QuestDebugProxy] Controller not available. Cannot list quests.")


## Prints all active quest instances with file_id, quest_id, status, and active node IDs.
func list_active_instances() -> void:
	var c = _get_controller()
	if c:
		c._debug_list_active_instances()
	else:
		push_warning("[QuestDebugProxy] Controller not available. Cannot list active instances.")
