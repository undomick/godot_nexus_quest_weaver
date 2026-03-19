# res://addons/quest_weaver/systems/managers/quest_sync_manager.gd
class_name QuestSyncManager
extends RefCounted

## Manages synchronization logic using Pattern Matching.
## Uses deferred batching to bundle multiple inputs arriving in the same frame.

var _controller_weak: WeakRef
var _deferred_scheduled: Dictionary = {}  # Key: "node_id|file_id" -> true


func _init(p_controller: QuestController):
	self._controller_weak = weakref(p_controller)


func _get_controller() -> QuestController:
	return _controller_weak.get_ref() as QuestController


## Called by SynchronizeNodeExecutor when an input is received.
## Collects inputs and processes them deferred to bundle signals from the same frame.
func handle_input(
	node_def: SynchronizeNodeResource, instance: QuestInstance, received_on_port: int
) -> void:
	var controller = _get_controller()
	if not controller:
		return

	var node_id = node_def.id
	var logger = controller._get_logger()

	if received_on_port < 0 or received_on_port >= node_def.inputs.size():
		return

	if not node_def.keep_listening:
		var has_fired: bool = instance.get_node_data(node_id, &"_sync_has_fired", false)
		if has_fired:
			return

	if logger:
		logger.log(
			"Flow", "Synchronizer '%s' received input on port %d." % [node_id, received_on_port]
		)

	# 1. Add to pending
	var pending: Array = instance.get_node_data(node_id, &"_sync_pending", [])
	pending.append(received_on_port)
	instance.set_node_data(node_id, &"_sync_pending", pending)

	# 2. Schedule deferred processing (only once per node/instance per batch)
	# Skip during shutdown to avoid deferred calls running after cleanup
	if controller.is_shutting_down():
		return
	var key = "%s|%s" % [node_id, instance.file_id]
	if not _deferred_scheduled.has(key):
		_deferred_scheduled[key] = true
		controller.call_deferred(&"_process_sync_node_batch", node_id, instance)


## Called deferred to process all inputs collected in the current frame.
func process_pending(node_id: StringName, instance: QuestInstance) -> void:
	var controller = _get_controller()
	if not controller:
		return

	var key = "%s|%s" % [node_id, instance.file_id]
	_deferred_scheduled.erase(key)

	var node_def = controller._node_definitions.get(node_id)
	if not node_def or not (node_def is SynchronizeNodeResource):
		return

	var sync_node = node_def as SynchronizeNodeResource
	var logger = controller._get_logger()

	# 1. Get and clear pending
	var pending: Array = instance.get_node_data(node_id, &"_sync_pending", [])
	instance.set_node_data(node_id, &"_sync_pending", [])

	# 2. Merge pending into inputs_received
	var inputs_received: Array = instance.get_node_data(node_id, &"inputs_received", [])
	if inputs_received.size() != sync_node.inputs.size():
		inputs_received = []
		inputs_received.resize(sync_node.inputs.size())
		inputs_received.fill(false)

	for port in pending:
		if port >= 0 and port < inputs_received.size():
			inputs_received[port] = true

	instance.set_node_data(node_id, &"inputs_received", inputs_received)

	# 3. Check Patterns
	var matched_indices: Array[int] = []

	if sync_node.logic_mode == SynchronizeNodeResource.LogicMode.EXCLUSIVE:
		for i in range(sync_node.outputs.size()):
			if _does_pattern_match(sync_node.outputs[i].patterns, inputs_received):
				matched_indices.append(i)
				break
	else:
		for i in range(sync_node.outputs.size()):
			if _does_pattern_match(sync_node.outputs[i].patterns, inputs_received):
				matched_indices.append(i)

	# 4. Fire & Reset
	if not matched_indices.is_empty():
		if logger:
			logger.log("Flow", "  - Synchronizer matched outputs: %s" % str(matched_indices))

		var state_snapshot = inputs_received.duplicate()

		inputs_received.fill(false)
		instance.set_node_data(node_id, &"inputs_received", inputs_received)

		for idx in matched_indices:
			_fire_output(sync_node, instance, idx, state_snapshot, controller)

		if not sync_node.keep_listening:
			instance.set_node_data(node_id, &"_sync_has_fired", true)
			controller.complete_node(sync_node)
	else:
		if logger:
			logger.log("Flow", "  - No pattern matched yet (Waiting).")


func _does_pattern_match(pattern: Array, current_inputs: Array) -> bool:
	var limit = min(pattern.size(), current_inputs.size())

	for i in range(limit):
		var requirement = pattern[i]
		var is_active = current_inputs[i]

		match requirement:
			SynchronizeNodeResource.InputState.REQUIRED:
				if not is_active:
					return false
			SynchronizeNodeResource.InputState.FORBIDDEN:
				if is_active:
					return false
			SynchronizeNodeResource.InputState.IGNORE:
				pass

	return true


func _fire_output(
	node_def: SynchronizeNodeResource,
	instance: QuestInstance,
	output_index: int,
	inputs_state: Array,
	controller: QuestController
) -> void:
	var connections = controller._node_connections.get(node_def.id, [])
	var output_port = node_def.outputs[output_index]

	# Check Output Condition (if any)
	if is_instance_valid(output_port.condition):
		var check_context = {"sync_inputs_received_array": inputs_state}
		if not output_port.condition.check(check_context, instance):
			return  # Condition failed

	for connection in connections:
		if connection.get("from_port", -1) == output_index:
			var to_node = connection.get("to_node", &"")
			var next_node_def = controller._node_definitions.get(to_node)
			if next_node_def:
				var to_port = connection.get("to_port", 0)
				controller._activate_node(next_node_def, to_port)


func clear():
	_deferred_scheduled.clear()
