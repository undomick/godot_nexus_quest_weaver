# res://addons/quest_weaver/systems/managers/quest_scope_manager.gd
class_name QuestScopeManager
extends RefCounted

## Manages Scopes. Stores iteration counts in QuestInstance variables.

var _controller_weak: WeakRef

# Static Cache: { StringName: { "start_node_id": StringName, "nodes_in_scope": Array[StringName], "end_node_ids": Array[StringName] } }
var _scope_definitions: Dictionary = {}


func _init(p_controller: QuestController):
	self._controller_weak = weakref(p_controller)


func _get_controller() -> QuestController:
	return _controller_weak.get_ref() as QuestController


# --- 1. Initialization (Builds map of nodes inside each scope) ---


func initialize_scope_definitions(
	node_definitions: Dictionary, node_connections: Dictionary
) -> void:
	_scope_definitions.clear()

	var start_nodes_by_id: Dictionary = {}
	var end_nodes_by_id: Dictionary = {}

	for node_def in node_definitions.values():
		if node_def is StartScopeNodeResource:
			start_nodes_by_id[node_def.scope_id] = node_def
		elif node_def is EndScopeNodeResource:
			if not end_nodes_by_id.has(node_def.scope_id):
				end_nodes_by_id[node_def.scope_id] = []
			end_nodes_by_id[node_def.scope_id].append(node_def)

	for scope_id in start_nodes_by_id:
		var start_node = start_nodes_by_id[scope_id]
		var end_nodes = end_nodes_by_id.get(scope_id, [])

		if end_nodes.is_empty():
			continue

		# Typed Array definition
		var nodes_in_scope: Array[StringName] = []
		var queue: Array[StringName] = [start_node.id]
		var visited: Dictionary = {start_node.id: true}

		while not queue.is_empty():
			var current_id: StringName = queue.pop_front()
			var def = node_definitions.get(current_id)

			var is_end = def is EndScopeNodeResource and def.scope_id == scope_id
			if not is_end:
				nodes_in_scope.append(current_id)

			var conns = node_connections.get(current_id, [])
			for c in conns:
				var next_id: StringName = StringName(c.get("to_node", &""))
				var next_def = node_definitions.get(next_id)
				var boundary = false
				if next_def:
					if (
						(next_def is EndScopeNodeResource and next_def.scope_id == scope_id)
						or (next_def is StartScopeNodeResource and next_def.scope_id == scope_id)
					):
						boundary = true

				if not visited.has(next_id) and not boundary:
					visited[next_id] = true
					queue.append(next_id)

		var end_node_ids: Array[StringName] = []
		for end_node in end_nodes:
			end_node_ids.append(end_node.id)

		_scope_definitions[scope_id] = {
			"start_node_id": start_node.id,
			"nodes_in_scope": nodes_in_scope,
			"end_node_ids": end_node_ids
		}


# --- 2. Runtime Logic (Instance Based) ---


func handle_start_scope(node: StartScopeNodeResource, instance: QuestInstance) -> bool:
	var scope_id = node.scope_id
	# IMPORTANT: Explicit cast to StringName for the variable key
	var var_key = StringName("_scope_%s_executions" % scope_id)

	# Get current count from instance (default 0)
	var current_executions = instance.get_variable(var_key, 0)
	var max_executions = node.max_executions

	var limit_reached = max_executions > 0 and current_executions >= max_executions

	if not limit_reached:
		current_executions += 1
		instance.set_variable(var_key, current_executions)
		return true

	return false


func handle_reset_scope(
	reset_node: ResetProgressNodeResource, instance: QuestInstance
) -> Array[StringName]:
	var scope_id = reset_node.target_scope_id
	var definition = _scope_definitions.get(scope_id)

	if not definition:
		return []

	var nodes_to_reset: Array[StringName] = []
	nodes_to_reset.assign(definition.nodes_in_scope)
	# Include EndScope nodes for cleanup (cached at init, O(1) per scope)
	var end_node_ids: Array = definition.get("end_node_ids", [])
	for end_id in end_node_ids:
		nodes_to_reset.append(end_id)

	# If restarting, reset the execution counter in the Instance
	if reset_node.restart_scope_on_completion:
		var var_key = StringName("_scope_%s_executions" % scope_id)
		instance.set_variable(var_key, 0)

	return nodes_to_reset


func get_start_node_id_for_scope(scope_id: StringName) -> StringName:
	var def = _scope_definitions.get(scope_id)
	return def.get("start_node_id", &"") if def else &""


## Returns node IDs for scope cleanup (same as handle_reset_scope without restart logic).
## Used by Cancel Scope Node.
func get_nodes_for_scope_cleanup(scope_id: StringName) -> Array[StringName]:
	var definition = _scope_definitions.get(scope_id)
	if not definition:
		return []
	var result: Array[StringName] = []
	result.assign(definition.nodes_in_scope)
	var end_node_ids: Array = definition.get("end_node_ids", [])
	for end_id in end_node_ids:
		result.append(end_id)
	return result


func clear() -> void:
	_scope_definitions.clear()
