# res://addons/quest_weaver/core/quest_debug_proxy.gd
class_name QuestDebugProxy
extends RefCounted

var _controller_weak: WeakRef

func _init(controller: QuestController):
	_controller_weak = weakref(controller)

func _get_controller() -> QuestController:
	if _controller_weak: return _controller_weak.get_ref() as QuestController
	return null

# --- API ---

func dump_state(quest_id: StringName) -> void:
	var c = _get_controller()
	if c: c.debug_dump_quest_state(quest_id)

func complete_active_tasks(quest_id: StringName) -> void:
	var c = _get_controller()
	if c: c.debug_complete_active_tasks(quest_id)

func set_var(quest_id: StringName, key: StringName, value: Variant) -> void:
	var c = _get_controller()
	if c: c.debug_set_variable(quest_id, key, value)

## Forces the flow to jump to a specific node ID (Use Node ID from Editor).
func jump_to_node(node_id: StringName) -> void:
	var c = _get_controller()
	if c: c.jump_to_node(node_id)
