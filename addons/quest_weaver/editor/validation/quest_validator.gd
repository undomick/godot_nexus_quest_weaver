# res://addons/quest_weaver/editor/validation/quest_validator.gd
@tool

class_name QuestValidator

extends Node

# Session cache: path -> QuestGraphResource (avoids reloading unchanged quests)
static var _graph_cache: Dictionary = {}

var _item_registry: Resource

var _quest_registry: Resource


## Clears the graph cache. Call when quests are saved to avoid stale validation.
static func clear_graph_cache() -> void:
	_graph_cache.clear()


## Validates quests at the given file paths. Returns aggregated ValidationResults.
## Quest display name is derived from path (e.g. path.get_file().get_basename()).
func validate_quests_at_paths(paths: Array[String]) -> Array[ValidationResult]:
	var all_results: Array[ValidationResult] = []
	var settings = QWConstants.get_settings()
	if not is_instance_valid(settings):
		return all_results

	_item_registry = _load_resource(settings.item_registry_path)
	_quest_registry = _load_resource(settings.quest_registry_path)

	for path in paths:
		if path.is_empty() or not ResourceLoader.exists(path):
			var quest_id = path.get_file().get_basename() if not path.is_empty() else "?"
			all_results.append(
				ValidationResult.new(
					ValidationResult.Severity.ERROR,
					"Quest '%s': File not found at '%s'." % [quest_id, path],
					"",
					path,
					""
				)
			)
			continue
		var graph: QuestGraphResource = _graph_cache.get(path)
		if graph == null:
			graph = (
				ResourceLoader.load(path, "QuestGraphResource", ResourceLoader.CACHE_MODE_IGNORE)
				as QuestGraphResource
			)
			if is_instance_valid(graph):
				_graph_cache[path] = graph
		if not is_instance_valid(graph):
			var quest_id = path.get_file().get_basename()
			all_results.append(
				ValidationResult.new(
					ValidationResult.Severity.ERROR,
					"Quest '%s': Failed to load graph from '%s'." % [quest_id, path],
					"",
					path,
					""
				)
			)
			continue
		var results = validate_graph(graph)
		for r in results:
			all_results.append(
				ValidationResult.new(r.severity, r.message, r.node_id, path, r.node_type)
			)
	return all_results


## Validates all quest graphs in the Quest Registry. Iterates by unique quest file path (no duplicates).
func validate_all_quests_in_registry() -> Array[ValidationResult]:
	var all_results: Array[ValidationResult] = []
	var settings = QWConstants.get_settings()
	if not is_instance_valid(settings) or settings.quest_registry_path.is_empty():
		return all_results

	_item_registry = _load_resource(settings.item_registry_path)
	_quest_registry = _load_resource(settings.quest_registry_path)
	if not is_instance_valid(_quest_registry) or not _quest_registry.quest_path_map:
		return all_results

	# Collect unique paths only (no duplicate validation of same file)
	var seen_paths: Dictionary = {}
	for quest_id in _quest_registry.quest_path_map:
		var path: String = _quest_registry.quest_path_map[quest_id]
		if path.is_empty() or seen_paths.has(path):
			continue
		seen_paths[path] = true
		if not ResourceLoader.exists(path):
			all_results.append(
				ValidationResult.new(
					ValidationResult.Severity.ERROR, "File not found at '%s'." % path, "", path, ""
				)
			)
			continue
		var graph: QuestGraphResource = _graph_cache.get(path)
		if graph == null:
			graph = (
				ResourceLoader.load(path, "QuestGraphResource", ResourceLoader.CACHE_MODE_IGNORE)
				as QuestGraphResource
			)
			if is_instance_valid(graph):
				_graph_cache[path] = graph
		if not is_instance_valid(graph):
			all_results.append(
				ValidationResult.new(
					ValidationResult.Severity.ERROR,
					"Failed to load graph from '%s'." % path,
					"",
					path,
					""
				)
			)
			continue
		var results = validate_graph(graph)
		for r in results:
			all_results.append(
				ValidationResult.new(r.severity, r.message, r.node_id, path, r.node_type)
			)
	return all_results


## Exports validation report as JSON or Markdown.
## Returns the report string (in-memory). If output_path is set, attempts to write to file:
## - On success: returns empty string.
## - On failure (FileAccess.open fails): logs error, returns the report content so the caller still has it.
func export_validation_report(format: String = "json", output_path: String = "") -> String:
	var results = validate_all_quests_in_registry()
	var content: String = ""
	if format.to_lower() == "md" or format.to_lower() == "markdown":
		content = _format_report_markdown(results)
	else:
		content = _format_report_json(results)
	if not output_path.is_empty():
		var file = FileAccess.open(output_path, FileAccess.WRITE)
		if file:
			file.store_string(content)
			file.close()
			return ""
		push_error("QuestValidator: Export failed. Failed to write report to '%s'." % output_path)
		return content
	return content


func _format_report_json(results: Array[ValidationResult]) -> String:
	var arr: Array = []
	for r in results:
		arr.append(
			{
				"severity": ValidationResult.Severity.keys()[r.severity],
				"message": r.message,
				"node_id": r.node_id
			}
		)
	return JSON.stringify(arr, "\t")


func _format_report_markdown(results: Array[ValidationResult]) -> String:
	var md := "# Quest Validation Report\n\n"
	if results.is_empty():
		md += "No issues found.\n"
		return md
	var by_severity: Dictionary = {"ERROR": [], "WARNING": [], "INFO": []}
	for r in results:
		var key = ValidationResult.Severity.keys()[r.severity]
		by_severity[key].append(r)
	for sev in ["ERROR", "WARNING", "INFO"]:
		var items = by_severity[sev]
		if items.is_empty():
			continue
		md += "## %s (%d)\n\n" % [sev, items.size()]
		for r in items:
			md += "- %s" % r.message
			if not r.node_id.is_empty():
				md += " (node: `%s`)" % r.node_id
			md += "\n"
		md += "\n"
	return md


func validate_graph(graph: QuestGraphResource) -> Array[ValidationResult]:
	var results: Array[ValidationResult] = []
	if not is_instance_valid(graph):
		return results

	var settings = QWConstants.get_settings()
	if not is_instance_valid(settings):
		return results

	_item_registry = _load_resource(settings.item_registry_path)
	_quest_registry = _load_resource(settings.quest_registry_path)

	results.append_array(_check_for_orphan_nodes(graph))
	results.append_array(_check_for_cycles(graph))
	results.append_array(_check_start_node_count(graph))

	var port_connected_map = _build_port_connection_map(graph)

	# PRE-PASS: Collect valid targets (Anchors and Scopes)
	var valid_anchors: Dictionary = {}
	var valid_scopes: Dictionary = {}

	for node_id in graph.nodes:
		var node = graph.nodes[node_id]
		if node is AnchorNodeResource and not node.anchor_name.is_empty():
			valid_anchors[node.anchor_name] = true
		elif node is StartScopeNodeResource and not node.scope_id.is_empty():
			valid_scopes[node.scope_id] = true

	# MAIN PASS
	for node_id in graph.nodes:
		var node: GraphNodeResource = graph.nodes[node_id]

		if node is BackdropNodeResource or node is CommentNodeResource:
			continue

		results.append_array(_validate_node_connections(node, graph, port_connected_map))
		results.append_array(_validate_node_properties(node))

		# --- NODE SPECIFIC LOGIC ---

		if node is BranchNodeResource:
			for condition in node.conditions:
				results.append_array(_validate_condition(condition, node))

		# Validate Conditions in EventListeners too
		elif node is EventListenerNodeResource:
			if not node.use_simple_conditions and is_instance_valid(node.payload_condition):
				results.append_array(_validate_condition(node.payload_condition, node))

		# Check Jump Targets
		elif node is JumpNodeResource:
			if not node.target_anchor_name.is_empty():
				if not valid_anchors.has(node.target_anchor_name):
					results.append(
						ValidationResult.new(
							ValidationResult.Severity.ERROR,
							(
								"Jump Target '%s' does not exist in this graph."
								% node.target_anchor_name
							),
							str(node_id),
							"",
							_get_node_type_name(node)
						)
					)

		# Check Reset Targets
		elif node is ResetProgressNodeResource:
			if not node.target_scope_id.is_empty():
				if not valid_scopes.has(node.target_scope_id):
					results.append(
						ValidationResult.new(
							ValidationResult.Severity.ERROR,
							(
								"Target Scope '%s' not found (StartScopeNode missing?)."
								% node.target_scope_id
							),
							str(node_id),
							"",
							_get_node_type_name(node)
						)
					)
		# Check Cancel Scope Targets
		elif node is CancelScopeNodeResource:
			if not node.target_scope_id.is_empty():
				if not valid_scopes.has(node.target_scope_id):
					results.append(
						ValidationResult.new(
							ValidationResult.Severity.ERROR,
							(
								"Target Scope '%s' not found (StartScopeNode missing?)."
								% node.target_scope_id
							),
							str(node_id),
							"",
							_get_node_type_name(node)
						)
					)

	return results


# --- HELPER FUNCTIONS ---


func _get_node_type_name(node: GraphNodeResource) -> String:
	if not is_instance_valid(node):
		return ""
	return node.get_display_name()


func _validate_node_properties(node: GraphNodeResource) -> Array[ValidationResult]:
	# We pack the registries into a context dictionary to pass it to the node.
	var context = {"item_registry": _item_registry, "quest_registry": _quest_registry}

	# Delegate the validation logic to the node resource itself.
	var results = node._validate(context)
	var type_name := _get_node_type_name(node)
	for r in results:
		r.node_type = type_name
	# BranchNode conditions are validated in the main loop of validate_graph() to avoid duplication.
	return results


func _validate_condition(
	condition: ConditionResource, node: GraphNodeResource
) -> Array[ValidationResult]:
	var results: Array[ValidationResult] = []
	var node_id_str := str(node.id) if node else ""
	var type_name := _get_node_type_name(node)

	if not is_instance_valid(condition):
		results.append(
			ValidationResult.new(
				ValidationResult.Severity.ERROR,
				"A Condition is invalid/null.",
				node_id_str,
				"",
				type_name
			)
		)
		return results

	match condition.type:
		ConditionResource.ConditionType.CHECK_ITEM:
			var item_id = condition.item_id
			if item_id == &"":
				results.append(
					ValidationResult.new(
						ValidationResult.Severity.ERROR,
						"Check Item Condition: No Item ID specified.",
						node_id_str,
						"",
						type_name
					)
				)

			elif is_instance_valid(_item_registry):
				if _item_registry.has_method(&"find"):
					if not _item_registry.find(str(item_id)):
						results.append(
							ValidationResult.new(
								ValidationResult.Severity.WARNING,
								"Item ID '%s' not found in registry." % item_id,
								node_id_str,
								"",
								type_name
							)
						)

		ConditionResource.ConditionType.CHECK_QUEST_STATUS:
			var target_id = condition.quest_id
			if target_id == &"":
				results.append(
					ValidationResult.new(
						ValidationResult.Severity.ERROR,
						"Check Quest Status: No target Quest ID specified.",
						node_id_str,
						"",
						type_name
					)
				)

			elif (
				is_instance_valid(_quest_registry)
				and not _quest_registry.quest_path_map.has(target_id)
			):
				results.append(
					ValidationResult.new(
						ValidationResult.Severity.WARNING,
						(
							"Check Quest Status: Target Quest ID '%s' not found in Quest Registry."
							% target_id
						),
						node_id_str,
						"",
						type_name
					)
				)

		ConditionResource.ConditionType.CHECK_OBJECTIVE_STATUS:
			if condition.objective_id == &"":
				results.append(
					ValidationResult.new(
						ValidationResult.Severity.ERROR,
						"Check Objective Status: No Objective ID specified.",
						node_id_str,
						"",
						type_name
					)
				)

		ConditionResource.ConditionType.CHECK_OBJECTIVE_REQUIREMENT:
			if condition.objective_id == &"":
				results.append(
					ValidationResult.new(
						ValidationResult.Severity.ERROR,
						"Check Requirement Met: No Objective ID specified.",
						node_id_str,
						"",
						type_name
					)
				)

		ConditionResource.ConditionType.COMPOUND:
			if condition.sub_conditions.is_empty():
				results.append(
					ValidationResult.new(
						ValidationResult.Severity.INFO,
						"Compound Condition is empty.",
						node_id_str,
						"",
						type_name
					)
				)
			else:
				for sub_condition in condition.sub_conditions:
					if is_instance_valid(sub_condition):
						results.append_array(_validate_condition(sub_condition, node))
					else:
						results.append(
							ValidationResult.new(
								ValidationResult.Severity.ERROR,
								"Compound Condition contains an invalid entry.",
								node_id_str,
								"",
								type_name
							)
						)

		_:
			pass

	return results


func _build_port_connection_map(graph: QuestGraphResource) -> Dictionary:
	var map: Dictionary = {}
	for connection in graph.connections:
		var from_node = connection.get("from_node", &"")
		var from_port = connection.get("from_port", -1)
		var key = "%s|%d" % [from_node, from_port]
		map[key] = true
	return map


func _validate_node_connections(
	node: GraphNodeResource, _graph: QuestGraphResource, port_connected_map: Dictionary
) -> Array[ValidationResult]:
	var results: Array[ValidationResult] = []

	if node is BranchNodeResource:
		var true_connected = port_connected_map.get("%s|%d" % [node.id, 0], false)
		var false_connected = port_connected_map.get("%s|%d" % [node.id, 1], false)
		if not true_connected and not false_connected:
			results.append(
				ValidationResult.new(
					ValidationResult.Severity.WARNING,
					"Branch: Both 'True' and 'False' outputs are unconnected.",
					str(node.id),
					"",
					_get_node_type_name(node)
				)
			)
		return results

	if (
		node is EndNodeResource
		or node is RandomNodeResource
		or node is TimerNodeResource
		or node is ParallelNodeResource
		or node is SynchronizeNodeResource
		or node is GiveTakeItemNodeResource
		or node is EventListenerNodeResource
		or node is PlayCutsceneNodeResource
	):
		return results

	for i in range(node.output_ports.size()):
		if not port_connected_map.get("%s|%d" % [node.id, i], false):
			var port_name = node.output_ports[i]
			results.append(
				ValidationResult.new(
					ValidationResult.Severity.WARNING,
					"Output port '%s' is unconnected. Flow stops here." % port_name,
					str(node.id),
					"",
					_get_node_type_name(node)
				)
			)

	return results


# --- GRAPH STRUCTURE RULES ---


func _check_start_node_count(graph: QuestGraphResource) -> Array[ValidationResult]:
	var results: Array[ValidationResult] = []
	var start_nodes: Array = []
	for node_id in graph.nodes:
		var node = graph.nodes[node_id]
		if node is StartNodeResource:
			start_nodes.append(node_id)
	if start_nodes.is_empty():
		results.append(
			ValidationResult.new(
				ValidationResult.Severity.ERROR,
				"Graph has no StartNode. Exactly one is required.",
				"",
				"",
				"Start Node"
			)
		)
	elif start_nodes.size() > 1:
		for nid in start_nodes:
			var n = graph.nodes.get(nid)
			results.append(
				ValidationResult.new(
					ValidationResult.Severity.ERROR,
					"Graph has more than one StartNode. Exactly one is required.",
					str(nid),
					"",
					_get_node_type_name(n) if n else "Start Node"
				)
			)
	return results


# --- Helpers & Algorithms ---


func _check_for_orphan_nodes(graph: QuestGraphResource) -> Array[ValidationResult]:
	var results: Array[ValidationResult] = []
	var all_target_nodes: Dictionary = {}

	# Collect all nodes that are targeted by a connection
	for connection in graph.connections:
		all_target_nodes[connection.to_node] = true

	for node_id in graph.nodes:
		var node = graph.nodes[node_id]

		# If the node has an incoming connection, it is reachable.
		if all_target_nodes.has(node_id):
			continue

		# --- EXCEPTIONS: Nodes that are allowed to be orphans ---

		# 1. Entry Points: Nodes that start execution logic
		if node is StartNodeResource or node is QuestContextNodeResource:
			continue

		# 2. Visual Helpers: Nodes that don't participate in logic flow
		if node is BackdropNodeResource or node is CommentNodeResource:
			continue

		# 3. Generic Check: If a node physically has no input ports,
		#    it cannot receive a connection, so warning is redundant.
		if node.input_ports.is_empty():
			continue

		# If none of the exceptions apply, issue a warning.
		results.append(
			ValidationResult.new(
				ValidationResult.Severity.WARNING,
				"This node is unreachable (no incoming connection).",
				str(node_id),
				"",
				_get_node_type_name(node)
			)
		)

	return results


func _load_resource(path: String) -> Resource:
	if not path.is_empty() and ResourceLoader.exists(path):
		return ResourceLoader.load(path)
	return null


func _check_for_cycles(graph: QuestGraphResource) -> Array[ValidationResult]:
	var results: Array[ValidationResult] = []
	var visited: Dictionary = {}
	var recursion_stack: Dictionary = {}
	var neighbors_cache := _build_neighbors_cache(graph)

	for node_id in graph.nodes:
		visited[node_id] = false
		recursion_stack[node_id] = false

	for node_id in graph.nodes:
		if not visited[node_id]:
			if _is_cyclic_iterative(node_id, visited, recursion_stack, neighbors_cache):
				var n = graph.nodes.get(node_id)
				results.append(
					ValidationResult.new(
						ValidationResult.Severity.ERROR,
						"An infinite loop was detected starting from this node.",
						str(node_id),
						"",
						_get_node_type_name(n) if n else ""
					)
				)
				return results

	return results


func _build_neighbors_cache(graph: QuestGraphResource) -> Dictionary:
	var cache: Dictionary = {}
	for conn in graph.connections:
		var from_id = conn.get("from_node", &"")
		if not cache.has(from_id):
			cache[from_id] = []
		cache[from_id].append(conn.get("to_node", &""))
	return cache


## Iterative DFS for cycle detection. Avoids stack overflow on very deep graphs.
func _is_cyclic_iterative(
	start_node_id: StringName,
	visited: Dictionary,
	recursion_stack: Dictionary,
	neighbors_cache: Dictionary
) -> bool:
	var stack: Array = []
	stack.append({"node": start_node_id, "idx": 0})

	while stack.size() > 0:
		var top = stack[stack.size() - 1]
		var node_id: StringName = top.node
		var idx: int = top.idx

		if idx == 0:
			visited[node_id] = true
			recursion_stack[node_id] = true

		var neighbors: Array = neighbors_cache.get(node_id, [])
		if idx < neighbors.size():
			var neighbor_id: StringName = neighbors[idx]
			stack[stack.size() - 1] = {"node": node_id, "idx": idx + 1}
			if not visited.get(neighbor_id, false):
				stack.append({"node": neighbor_id, "idx": 0})
			elif recursion_stack.get(neighbor_id, false):
				return true
		else:
			recursion_stack[node_id] = false
			stack.pop_back()

	return false
