# res://addons/quest_weaver/systems/managers/quest_event_manager.gd
class_name QuestEventManager

extends RefCounted

var _event_listeners: Dictionary = {}

var _controller_weak: WeakRef

## Manages global event listeners.
## Stores mapping: EventName -> List of NodeIDs.

# Map: StringName -> Array[StringName]


func _init(p_controller: QuestController):
	self._controller_weak = weakref(p_controller)


func _get_controller() -> QuestController:
	return _controller_weak.get_ref() as QuestController


func register_listener(listener_node: EventListenerNodeResource) -> void:
	var evt: StringName = listener_node.event_name
	if not _event_listeners.has(evt):
		var list: Array[StringName] = []
		_event_listeners[evt] = list

	if not listener_node.id in _event_listeners[evt]:
		_event_listeners[evt].append(listener_node.id)


func unregister_listener(listener_node: EventListenerNodeResource) -> void:
	var evt: StringName = listener_node.event_name
	if _event_listeners.has(evt):
		_event_listeners[evt].erase(listener_node.id)
		if _event_listeners[evt].is_empty():
			_event_listeners.erase(evt)


func on_global_event(event_name: StringName, payload: Dictionary) -> void:
	var controller = _get_controller()
	if not controller:
		return

	if not _event_listeners.has(event_name):
		return

	# Typed Array for performance
	var listeners: Array[StringName] = []
	listeners.assign(_event_listeners[event_name].duplicate())

	for node_id: StringName in listeners:
		# 1. Resolve Instance
		var instance: QuestInstance = controller.get_quest_data_manager().get_instance_for_node(
			node_id
		)

		# If instance or node is not active, ignore/cleanup
		if not instance or not instance.is_node_active(node_id):
			continue

		var node_def = controller.get_quest_data_manager().get_node_definition(node_id)
		if node_def is EventListenerNodeResource:
			# 2. Check Conditions (Instance-aware)
			var condition_passes = true
			if node_def.use_simple_conditions:
				condition_passes = _check_simple_conditions(node_def.simple_conditions, payload)
			else:
				if is_instance_valid(node_def.payload_condition):
					condition_passes = node_def.payload_condition.check(payload, instance)

			# 3. Trigger
			if condition_passes:
				var logger = controller._get_logger()
				if logger:
					logger.log(
						"Flow", "Event '%s' triggered listener '%s'." % [event_name, node_id]
					)

				if node_def.keep_listening:
					controller._trigger_next_nodes_from_port(node_def, 0)
				else:
					# One-shot: Remove from my list and complete node
					_event_listeners[event_name].erase(node_id)
					controller.complete_node(node_def)


func clear() -> void:
	_event_listeners.clear()


## Removes all event listeners for nodes in the given set. Use Dictionary for O(1) lookup.
func remove_listeners_for_quest(nodes_in_quest: Dictionary) -> void:
	for evt in _event_listeners.keys():
		var list = _event_listeners[evt]
		for i in range(list.size() - 1, -1, -1):
			if nodes_in_quest.has(list[i]):
				list.remove_at(i)


# --- Helper for Simple Conditions ---
func _check_simple_conditions(conditions: Array[Dictionary], payload: Dictionary) -> bool:
	if conditions.is_empty():
		return true

	for c in conditions:
		var key = c.get("key", "")
		var op = c.get("op", 0)
		var val_str = c.get("value", "")

		if key.is_empty():
			continue

		# Special handling for "HAS" (SimpleOperator.HAS)
		if op == EventListenerNodeResource.SimpleOperator.HAS:
			if not payload.has(key):
				return false
			continue

		if not payload.has(key):
			# If key is missing, only NOT_EQUALS (1) should pass
			if op != QWConditionLogic.Op.NOT_EQUALS:
				return false
			continue

		var actual = payload[key]
		var expected = QWConditionLogic.parse_string_to_variant(val_str)

		if not QWConditionLogic.compare(actual, expected, op):
			return false

	return true
