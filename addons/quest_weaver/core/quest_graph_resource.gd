# res://addons/quest_weaver/core/quest_graph_resource.gd
@tool
class_name QuestGraphResource
extends Resource

## Resource holding the graph structure for a quest: nodes (GraphNodeResource) and connections.
## Serializes via to_dictionary/from_dictionary for save/load and editor import.
##
## Format: { StringName : GraphNodeResource }
@export var nodes: Dictionary = {}

## Format: { "from_node": StringName, "from_port": int, "to_node": StringName, "to_port": int }
@export var connections: Array[Dictionary] = []

@export var editor_scroll_offset: Vector2 = Vector2.ZERO
@export var editor_zoom: float = 1.0


## Adds a node to the graph. Overwrites if ID already exists. Validates node_data and ID.
func add_node(node_data: GraphNodeResource) -> void:
	if not is_instance_valid(node_data) or node_data.id == &"":
		push_error("QuestGraphResource: Attempted to add invalid node data (ID missing).")
		return

	if nodes.has(node_data.id):
		push_warning(
			"QuestGraphResource: Node with ID '%s' already exists. Overwriting." % node_data.id
		)

	nodes[node_data.id] = node_data


## Removes a node and all connections referencing it.
func remove_node(node_id: StringName) -> void:
	if nodes.has(node_id):
		nodes.erase(node_id)

	# Filter connections ensuring we compare StringNames. Use .get() for robust access when keys are from JSON.
	connections = connections.filter(
		func(c: Dictionary) -> bool:
			if not c or not c.has("from_node") or not c.has("to_node"):
				return false
			var from_id = StringName(c.get("from_node", &""))
			var to_id = StringName(c.get("to_node", &""))
			return from_id != node_id and to_id != node_id
	)


## Adds a connection if it does not already exist. No-op for duplicates.
func add_connection(
	from_node: StringName, from_port: int, to_node: StringName, to_port: int
) -> void:
	for c in connections:
		if (
			c.from_node == from_node
			and c.from_port == from_port
			and c.to_node == to_node
			and c.to_port == to_port
		):
			return

	connections.append(
		{"from_node": from_node, "from_port": from_port, "to_node": to_node, "to_port": to_port}
	)


## Removes the first matching connection.
func remove_connection(
	from_node: StringName, from_port: int, to_node: StringName, to_port: int
) -> void:
	for i in range(connections.size() - 1, -1, -1):
		var c = connections[i]
		if (
			c.from_node == from_node
			and c.from_port == from_port
			and c.to_node == to_node
			and c.to_port == to_port
		):
			connections.remove_at(i)
			return


## Removes all connections from the given output port.
func remove_connection_from_output(from_node: StringName, from_port: int) -> void:
	for i in range(connections.size() - 1, -1, -1):
		var c = connections[i]
		if c.from_node == from_node and c.from_port == from_port:
			connections.remove_at(i)


## Serializes the graph to a Dictionary for save/load and import.
func to_dictionary() -> Dictionary:
	var data = {
		"@script_path": get_script().resource_path,
		"connections": self.connections,
		"nodes": {},
		"editor_scroll_offset": self.editor_scroll_offset,
		"editor_zoom": self.editor_zoom
	}

	for node_id in self.nodes:
		var node_resource = self.nodes[node_id]
		if is_instance_valid(node_resource):
			# Node ID is automatically serialized as String by Godot's JSON logic mostly,
			# but internal Dictionary keys remain StringName if stored via store_var.
			data.nodes[node_id] = node_resource.to_dictionary()

	return data


## Deserializes the graph from a Dictionary. Clears existing nodes and connections.
func from_dictionary(data: Dictionary) -> void:
	if not data is Dictionary:
		push_error("QuestGraphResource: from_dictionary requires a valid Dictionary.")
		return
	self.editor_scroll_offset = data.get("editor_scroll_offset", Vector2.ZERO)
	self.editor_zoom = data.get("editor_zoom", 1.0)

	# 1. Clean Connections & Ensure StringName Types
	self.connections.clear()
	var raw_connections = data.get("connections", [])
	for conn in raw_connections:
		if not conn is Dictionary:
			push_warning("QuestGraphResource: Invalid connection entry (not Dictionary). Skipping.")
			continue
		var clean_conn = {
			"from_node": StringName(conn.get("from_node", &"")),
			"from_port": int(conn.get("from_port", 0)),
			"to_node": StringName(conn.get("to_node", &"")),
			"to_port": int(conn.get("to_port", 0))
		}
		self.connections.append(clean_conn)

	# 2. Load Nodes & Ensure Keys are StringName
	self.nodes.clear()
	var nodes_data = data.get("nodes", {})

	for key in nodes_data:
		var node_id = StringName(key)
		var node_dict = nodes_data[key]
		if not node_dict is Dictionary:
			push_warning(
				(
					"QuestGraphResource: Node '%s' has invalid data (not Dictionary). Skipping."
					% node_id
				)
			)
			continue
		var script_path = node_dict.get("@script_path")
		if not script_path:
			push_warning("QuestGraphResource: Node '%s' has no @script_path. Skipping." % node_id)
			continue
		if not ResourceLoader.exists(script_path):
			push_warning(
				(
					"QuestGraphResource: Script path '%s' for node '%s' not found. Skipping."
					% [script_path, node_id]
				)
			)
			continue
		var script = GraphNodeResource.get_script_cached(script_path)
		if not script:
			push_warning(
				(
					"QuestGraphResource: Could not load script '%s' for node '%s'. Skipping."
					% [script_path, node_id]
				)
			)
			continue
		var new_node = script.new()
		new_node.from_dictionary(node_dict)
		# Security check: Ensure internal ID matches the Dictionary Key
		if new_node.id != node_id:
			new_node.id = node_id
		self.add_node(new_node)
