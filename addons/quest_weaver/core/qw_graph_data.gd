# res://addons/quest_weaver/core/qw_graph_data.gd
@tool
class_name QWGraphData
extends Node

## Central cache for Quest graph resources in the editor.
## Manages clean/dirty instances, active graph selection, and persistence.
## Call clear_all() before plugin shutdown to release references.

signal graph_dirty_status_changed(path: String, is_dirty: bool)
signal active_graph_changed(new_graph_resource: QuestGraphResource)
signal graph_was_saved(path: String)

var _clean_instances: Dictionary = {}
var _dirty_instances: Dictionary = {}
var _active_graph_path: String = ""


func set_active_graph(path: String) -> void:
	if _active_graph_path == path and not path.is_empty():
		return

	_active_graph_path = path

	if path.is_empty():
		active_graph_changed.emit(null)
	else:
		if not _clean_instances.has(path):
			_load_graph_from_disk(path)
		active_graph_changed.emit(get_graph(path))


func get_active_graph() -> QuestGraphResource:
	return get_graph(_active_graph_path)


func get_active_graph_path() -> String:
	return _active_graph_path


func get_graph(path: String) -> QuestGraphResource:
	if path.is_empty():
		return null
	if _dirty_instances.has(path):
		return _dirty_instances[path]
	return _clean_instances.get(path)


func update_view_state(path: String, scroll: Vector2, zoom: float) -> void:
	for instances in [_clean_instances, _dirty_instances]:
		if instances.has(path):
			var instance = instances[path]
			if is_instance_valid(instance):
				instance.editor_scroll_offset = scroll
				instance.editor_zoom = zoom


func make_active_graph_editable() -> QuestGraphResource:
	if _active_graph_path.is_empty():
		return null

	if _dirty_instances.has(_active_graph_path):
		return _dirty_instances[_active_graph_path]

	var clean_instance = _clean_instances.get(_active_graph_path)
	if not is_instance_valid(clean_instance):
		return null

	var shadow_copy: QuestGraphResource = clean_instance.duplicate(true)
	_dirty_instances[_active_graph_path] = shadow_copy

	graph_dirty_status_changed.emit(_active_graph_path, true)

	return shadow_copy


func save_active_graph() -> bool:
	if _active_graph_path.is_empty():
		return false
	if not has_unsaved_changes(_active_graph_path):
		if _clean_instances.has(_active_graph_path):
			# Emit to sync UI when graph is already clean.
			graph_was_saved.emit(_active_graph_path)
			graph_dirty_status_changed.emit(_active_graph_path, false)
			return true
		return false
	return _save_graph_to_path(_active_graph_path)


func save_graph(path: String) -> bool:
	if path.is_empty() or not has_unsaved_changes(path):
		return false
	return _save_graph_to_path(path)


func discard_changes(path: String) -> void:
	if _dirty_instances.has(path):
		_dirty_instances.erase(path)
		if _active_graph_path == path:
			active_graph_changed.emit(get_graph(path))
		graph_dirty_status_changed.emit(path, false)


func close_graph(path: String) -> void:
	if _clean_instances.has(path):
		_clean_instances.erase(path)
	if _dirty_instances.has(path):
		_dirty_instances.erase(path)
	if _active_graph_path == path:
		set_active_graph("")


## Clears all cached graphs. Call before plugin shutdown to release references and avoid resource leaks.
func clear_all() -> void:
	_clean_instances.clear()
	_dirty_instances.clear()
	_active_graph_path = ""


func has_unsaved_changes(path: String) -> bool:
	return _dirty_instances.has(path)


## Emits graph_dirty_status_changed for the active graph if it has unsaved changes.
## Call after redo to ensure the UI shows the modified state.
func notify_dirty_status_if_unsaved() -> void:
	if not _active_graph_path.is_empty() and _dirty_instances.has(_active_graph_path):
		graph_dirty_status_changed.emit(_active_graph_path, true)


func get_all_unsaved_paths() -> Array[String]:
	var typed_paths: Array[String] = []
	for path in _dirty_instances.keys():
		typed_paths.append(path)
	return typed_paths


func _save_graph_to_path(path: String) -> bool:
	var dirty_graph = _dirty_instances[path]
	_validate_and_clean_graph_data(dirty_graph)
	var data_to_save = dirty_graph.to_dictionary()
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("QWGraphData: Could not open '%s' for writing." % path)
		return false
	file.store_var(data_to_save, true)
	file.close()
	_clean_instances[path] = dirty_graph
	_dirty_instances.erase(path)
	graph_dirty_status_changed.emit(path, false)
	graph_was_saved.emit(path)
	return true


func _load_graph_from_disk(path: String) -> void:
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var data = file.get_var(true)
	file.close()
	if not data is Dictionary:
		return
	var editable_instance = QuestGraphResource.new()
	editable_instance.from_dictionary(data)
	var nodes_data = data.get("nodes", {})
	if nodes_data is Dictionary and nodes_data.size() > 0 and editable_instance.nodes.is_empty():
		push_warning("QWGraphData: Loaded '%s' but nodes failed to load. Skipping." % path)
		return
	_clean_instances[path] = editable_instance


func _validate_and_clean_graph_data(graph: QuestGraphResource) -> bool:
	if not is_instance_valid(graph):
		return false
	# Ensure GiveTakeItem (and similar) nodes have correct output_ports before validating connections.
	# Otherwise connections from port 1 (Partial) would be dropped when output_ports.size() was 2.
	for node in graph.nodes.values():
		if is_instance_valid(node) and node.has_method("_update_ports_from_data"):
			node._update_ports_from_data()
	var original_connections = graph.connections
	var connections_before_clean = original_connections.duplicate(true)
	var cleaned_connections: Array[Dictionary] = []
	var seen_hashes: Dictionary = {}
	var changes_made := false
	for conn in connections_before_clean:
		if not conn or not conn.has_all(["from_node", "from_port", "to_node", "to_port"]):
			changes_made = true
			continue
		var from_node_id = conn.from_node
		var from_port_idx = conn.from_port
		var to_node_id = conn.to_node
		var to_port_idx = conn.to_port
		if not graph.nodes.has(from_node_id) or not graph.nodes.has(to_node_id):
			changes_made = true
			continue
		var from_node_data: GraphNodeResource = graph.nodes[from_node_id]
		var to_node_data: GraphNodeResource = graph.nodes[to_node_id]
		if (
			from_port_idx >= from_node_data.output_ports.size()
			or to_port_idx >= to_node_data.input_ports.size()
		):
			changes_made = true
			continue
		var conn_hash: String = (
			"%s|%s->%s|%s" % [from_node_id, from_port_idx, to_node_id, to_port_idx]
		)
		if not seen_hashes.has(conn_hash):
			cleaned_connections.append(conn)
			seen_hashes[conn_hash] = true
		else:
			changes_made = true
	if cleaned_connections.size() != original_connections.size() or changes_made:
		graph.connections = cleaned_connections
		return true
	return false
