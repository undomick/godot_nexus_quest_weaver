# res://addons/quest_weaver/editor/commands/create_node_command.gd
@tool
class_name CreateNodeCommand
extends EditorCommand

var _editor: QuestWeaverEditor
var _graph: QuestGraphResource
var _node_script: Script
var _node_position: Vector2
var _connect_data: Dictionary
var _created_node_data: GraphNodeResource


func _init(
	p_editor: QuestWeaverEditor,
	p_graph: QuestGraphResource,
	p_node_script: Script,
	p_node_position: Vector2,
	p_connect_data: Dictionary
):
	self._editor = p_editor
	self._graph = p_graph
	self._node_script = p_node_script
	self._node_position = p_node_position
	self._connect_data = p_connect_data


func execute() -> void:
	if not is_instance_valid(_created_node_data):
		_created_node_data = _node_script.new()
		var type_name = self._editor.node_registry.get_name_for_script(_node_script)

		var new_id = (
			"%s_%d_%d"
			% [type_name.to_snake_case(), Time.get_unix_time_from_system(), randi() & 0xFFFF]
		)
		_created_node_data.id = new_id
		_created_node_data.graph_position = _node_position

	_graph.add_node(_created_node_data)

	if not _connect_data.is_empty():
		var from_node = _connect_data.from_node
		var from_port = _connect_data.from_port
		_graph.add_connection(from_node, from_port, _created_node_data.id, 0)


func undo() -> void:
	if is_instance_valid(_created_node_data):
		_graph.remove_node(_created_node_data.id)


func get_created_node_id() -> StringName:
	return _created_node_data.id if is_instance_valid(_created_node_data) else &""
