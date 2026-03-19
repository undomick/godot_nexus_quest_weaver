# res://addons/quest_weaver/editor/qw_clipboard.gd
@tool
class_name QWClipboard
extends RefCounted

## Manages the entire Copy & Paste logic for the Quest Editor.
## Handles deep duplication of nodes and their sub-resources (Conditions, Objectives)
## to ensure unique IDs and independent instances.

var _clipboard_data: Dictionary = {}
var _node_registry: NodeTypeRegistry


func initialize(p_node_registry: NodeTypeRegistry) -> void:
	self._node_registry = p_node_registry


func is_empty() -> bool:
	return _clipboard_data.is_empty()


## Clears clipboard. Call before shutdown to release references (e.g. ConditionResource) and avoid leaks.
func clear() -> void:
	_clipboard_data.clear()


func copy_selection_to_clipboard(
	selected_nodes_data: Array[GraphNodeResource], connections: Array[Dictionary]
) -> void:
	if selected_nodes_data.is_empty():
		_clipboard_data.clear()
		return

	const DEFAULT_NODE_VISUAL_SIZE := Vector2(200, 100)
	var copied_node_ids_set: Dictionary = {}  # StringName -> true for O(1) lookup
	var bounding_rect: Rect2
	var first = true

	for node_data in selected_nodes_data:
		copied_node_ids_set[node_data.id] = true
		# Default node size for bounding box calculation
		var node_visual_rect = Rect2(node_data.graph_position, DEFAULT_NODE_VISUAL_SIZE)
		if first:
			bounding_rect = node_visual_rect
			first = false
		else:
			bounding_rect = bounding_rect.merge(node_visual_rect)

	# Only copy connections that exist between the selected nodes
	var copied_connections: Array[Dictionary] = []
	for connection in connections:
		if (
			copied_node_ids_set.has(connection.from_node)
			and copied_node_ids_set.has(connection.to_node)
		):
			copied_connections.append(connection)

	_clipboard_data = {
		"nodes": selected_nodes_data,
		"connections": copied_connections,
		"bounding_rect_center": bounding_rect.get_center()
	}


func get_paste_data(paste_position: Vector2) -> Dictionary:
	if is_empty():
		return {}
	if not is_instance_valid(_node_registry):
		return {}

	var original_nodes: Array[GraphNodeResource] = _clipboard_data.get("nodes", [])
	var original_connections: Array[Dictionary] = _clipboard_data.get("connections", [])
	var original_center: Vector2 = _clipboard_data.get("bounding_rect_center", Vector2.ZERO)

	var new_id_map: Dictionary = {}
	var new_nodes_data: Array[GraphNodeResource] = []

	for original_node_data in original_nodes:
		# Perform a deep copy to ensure sub-resources (Objectives, Conditions) are unique
		var new_node: GraphNodeResource = _deep_duplicate_node_recursively(original_node_data)
		if not is_instance_valid(new_node):
			continue
		var old_id = original_node_data.id

		# Generate a new unique ID for the pasted node
		var type_name = _node_registry.get_name_for_script(new_node.get_script()).to_snake_case()
		var new_id = "%s_%d_%d" % [type_name, int(Time.get_unix_time_from_system()), randi()]
		new_node.id = new_id
		new_id_map[old_id] = new_id

		# Calculate new position relative to the mouse pointer
		var relative_pos = original_node_data.graph_position - original_center
		new_node.graph_position = paste_position + relative_pos

		new_nodes_data.append(new_node)

	# Reconstruct connections with the new IDs
	var new_connections_data: Array[Dictionary] = []
	for original_conn in original_connections:
		var old_from_node = original_conn.get("from_node")
		var old_to_node = original_conn.get("to_node")
		var new_from_node = new_id_map.get(old_from_node)
		var new_to_node = new_id_map.get(old_to_node)

		if new_from_node and new_to_node:
			new_connections_data.append(
				{
					"from_node": new_from_node,
					"from_port": original_conn.get("from_port"),
					"to_node": new_to_node,
					"to_port": original_conn.get("to_port")
				}
			)

	return {"nodes": new_nodes_data, "connections": new_connections_data}


# --- PRIVATE HELPER FUNCTIONS ---


func _deep_duplicate_node_recursively(original_node: GraphNodeResource) -> GraphNodeResource:
	if not is_instance_valid(original_node):
		return null

	var new_node: GraphNodeResource = original_node.duplicate(true)

	# Perform deep copies for specific node types that contain sub-resources.
	# This prevents pasted nodes from sharing references with the originals.

	if new_node is TaskNodeResource:
		var new_objectives: Array[ObjectiveResource] = []
		for objective in new_node.objectives:
			var new_objective: ObjectiveResource = objective.duplicate(true)
			# Objectives need unique IDs too
			new_objective.id = "objective_%d_%d" % [int(Time.get_unix_time_from_system()), randi()]
			new_objectives.append(new_objective)
		new_node.objectives = new_objectives

	elif new_node is BranchNodeResource:
		var new_conditions: Array[ConditionResource] = []
		for condition in new_node.conditions:
			var dup = _deep_duplicate_condition_recursively(condition)
			if is_instance_valid(dup):
				new_conditions.append(dup)
		new_node.conditions = new_conditions

	elif new_node is ParallelNodeResource:
		var new_outputs: Array[ParallelOutputPort] = []
		for port in new_node.outputs:
			var new_port = port.duplicate(true)
			if is_instance_valid(new_port.condition):
				new_port.condition = _deep_duplicate_condition_recursively(new_port.condition)
			new_outputs.append(new_port)
		new_node.outputs = new_outputs

	elif new_node is RandomNodeResource:
		var new_outputs: Array[RandomOutputPort] = []
		for port in new_node.outputs:
			new_outputs.append(port.duplicate(true))
		new_node.outputs = new_outputs

	elif new_node is SynchronizeNodeResource:
		var new_inputs: Array[SynchronizeInputPort] = []
		for port in new_node.inputs:
			new_inputs.append(port.duplicate(true))
		new_node.inputs = new_inputs

		var new_outputs: Array[SynchronizeOutputPort] = []
		for port in new_node.outputs:
			var new_port = port.duplicate(true)
			if is_instance_valid(new_port.condition):
				new_port.condition = _deep_duplicate_condition_recursively(new_port.condition)
			new_outputs.append(new_port)
		new_node.outputs = new_outputs

	elif new_node is EventListenerNodeResource:
		if is_instance_valid(new_node.payload_condition):
			new_node.payload_condition = _deep_duplicate_condition_recursively(
				new_node.payload_condition
			)

	return new_node


func _deep_duplicate_condition_recursively(
	original_condition: ConditionResource
) -> ConditionResource:
	if not is_instance_valid(original_condition):
		return null

	var new_condition: ConditionResource = original_condition.duplicate(true)

	# Handle recursive structures (Compound Conditions)
	if new_condition.type == ConditionResource.ConditionType.COMPOUND:
		var new_sub_conditions: Array[ConditionResource] = []
		for sub_con in new_condition.sub_conditions:
			var dup = _deep_duplicate_condition_recursively(sub_con)
			if is_instance_valid(dup):
				new_sub_conditions.append(dup)
		new_condition.sub_conditions = new_sub_conditions

	return new_condition
