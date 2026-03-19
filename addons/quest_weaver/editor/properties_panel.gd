# res://addons/quest_weaver/editor/properties_panel.gd
@tool

extends PanelContainer

signal property_update_requested(
	node_id: StringName,
	property_name: String,
	new_value: Variant,
	sub_resource: Resource,
	extra: Dictionary
)

signal property_preview_requested(node_id: StringName, property_name: String, value: Variant)

signal complex_action_requested(node_id: StringName, action: String, payload: Dictionary)

signal dive_in_requested(graph_path: String)

signal node_ports_changed(node_id: StringName)

# --- Dependencies & State ---
var node_registry: NodeTypeRegistry

var data_manager: QWGraphData

var editor_plugin

var current_editor_instance: Node

var _inspected_node_data: GraphNodeResource

var _editor_scene_cache: Dictionary = {}  # editor_path -> PackedScene

var _last_refreshed_graph_path: String = ""

# --- UI References ---
@onready var node_type_label: Label = %NodeTypeLabel

@onready var editor_host: VBoxContainer = %PropertyFieldsContainer

@onready var no_selection_label: Label = %NoSelectionLabel


func _ready() -> void:
	# Removed window specific signals (close_requested etc.)
	_update_visibility()


func initialize(
	p_node_registry: NodeTypeRegistry, p_data_manager: QWGraphData, p_editor_plugin
) -> void:
	self.node_registry = p_node_registry
	self.data_manager = p_data_manager
	self.editor_plugin = p_editor_plugin


func inspect_node(node_data: GraphNodeResource) -> void:
	if not is_instance_valid(node_data):
		clear_inspection()
		return
	if not is_instance_valid(data_manager) or not is_instance_valid(node_registry):
		return

	self._inspected_node_data = node_data
	_update_visibility()

	var active_path = data_manager.get_active_graph_path()
	if active_path != _last_refreshed_graph_path:
		QWEditorUtils.refresh_quest_id_cache_for_graph(data_manager.get_active_graph())
		_last_refreshed_graph_path = active_path

	if is_instance_valid(current_editor_instance):
		current_editor_instance.queue_free()
		current_editor_instance = null

	for child in editor_host.get_children():
		child.queue_free()

	var node_script = node_data.get_script()
	node_type_label.text = node_registry.get_name_for_script(node_script)

	var editor_path = node_registry.get_editor_path_for_script(node_script)

	if not editor_path.is_empty() and ResourceLoader.exists(editor_path):
		if not _editor_scene_cache.has(editor_path):
			var loaded = load(editor_path)
			if is_instance_valid(loaded) and loaded is PackedScene:
				_editor_scene_cache[editor_path] = loaded
		var editor_scene = _editor_scene_cache.get(editor_path)
		if not is_instance_valid(editor_scene):
			return
		current_editor_instance = editor_scene.instantiate()

		if current_editor_instance.has_signal(&"property_update_requested"):
			current_editor_instance.connect(
				&"property_update_requested",
				func(
					id: StringName, prop: String, val: Variant, sub_res: Resource, extra: Dictionary
				):
					property_update_requested.emit(id, prop, val, sub_res, extra)
			)
		if current_editor_instance.has_signal(&"property_preview_requested"):
			current_editor_instance.connect(
				&"property_preview_requested",
				func(id: StringName, prop: String, val: Variant):
					property_preview_requested.emit(id, prop, val)
			)
		if current_editor_instance.has_signal(&"complex_action_requested"):
			current_editor_instance.complex_action_requested.connect(complex_action_requested.emit)
		if current_editor_instance.has_signal(&"dive_in_requested"):
			current_editor_instance.dive_in_requested.connect(dive_in_requested.emit)
		if current_editor_instance.has_signal(&"ports_need_refresh"):
			current_editor_instance.ports_need_refresh.connect(
				func(id): node_ports_changed.emit(id)
			)

		editor_host.add_child(current_editor_instance)
		current_editor_instance.call_deferred(&"set_node_data", node_data)
	else:
		var id_label = Label.new()
		id_label.text = node_data.id


func clear_inspection() -> void:
	_inspected_node_data = null
	# Use free() not queue_free(): during editor shutdown deferred calls may not run; immediate release avoids ConditionResource leak
	if is_instance_valid(current_editor_instance):
		current_editor_instance.free()
		current_editor_instance = null
	var children = editor_host.get_children()
	for child in children:
		if is_instance_valid(child):
			child.free()
	_update_visibility()


func refresh_inspected_node() -> void:
	if not is_instance_valid(_inspected_node_data):
		return
	var current_graph = data_manager.get_active_graph()
	if not is_instance_valid(current_graph):
		return
	var fresh_node_data = current_graph.nodes.get(_inspected_node_data.id)
	if is_instance_valid(fresh_node_data):
		inspect_node(fresh_node_data)


func get_inspected_node_id() -> StringName:
	if is_instance_valid(_inspected_node_data):
		return _inspected_node_data.id
	return &""


# --- Helper ---
func _update_visibility() -> void:
	var has_target = is_instance_valid(_inspected_node_data)

	if is_instance_valid(editor_host):
		editor_host.visible = has_target

	if is_instance_valid(node_type_label):
		node_type_label.visible = has_target

	if is_instance_valid(no_selection_label):
		no_selection_label.visible = not has_target
