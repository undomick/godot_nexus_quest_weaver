# res://addons/quest_weaver/core/execution_context.gd
class_name ExecutionContext
extends RefCounted

## A data container that bundles all external dependencies for the execution
## of a quest graph. It is created once and then passed through the execution flow.

var game_state: Node
var services: Node
var logger: QWLogger:
	get:
		if is_instance_valid(services) and services.logger:
			return services.logger
		return null

var quest_controller: QuestController:
	get:
		if _controller_weak:
			return _controller_weak.get_ref() as QuestController
		return null

## Inventory adapter for item-related nodes. Use this instead of accessing controller internals.
var inventory_adapter: QuestInventoryAdapterBase:
	get:
		var c = quest_controller
		return c.get_inventory_adapter() if c else null

## Kill adapter for KILL objectives. Use this instead of accessing controller internals.
var kill_adapter: QuestKillAdapterBase:
	get:
		var c = quest_controller
		return c.get_kill_adapter() if c else null

## Listeners for objective completion callbacks. Key: node_id or objective key.
var item_objective_listeners: Dictionary = {}
## Listeners for kill objective completion callbacks.
var kill_objective_listeners: Dictionary = {}
## Listeners for interact objective completion callbacks.
var interact_objective_listeners: Dictionary = {}
## Listeners for location objective completion callbacks.
var location_objective_listeners: Dictionary = {}

var _controller_weak: WeakRef


func _init(
	p_controller: QuestController, p_game_state: Node, _p_logger: QWLogger, p_services: Node
) -> void:
	self._controller_weak = weakref(p_controller)
	self.game_state = p_game_state
	self.services = p_services


## Clears references and listener dictionaries. Call when execution context is no longer needed.
func cleanup() -> void:
	game_state = null
	services = null
	_controller_weak = null

	item_objective_listeners.clear()
	kill_objective_listeners.clear()
	interact_objective_listeners.clear()
	location_objective_listeners.clear()
