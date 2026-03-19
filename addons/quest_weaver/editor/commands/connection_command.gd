# res://addons/quest_weaver/editor/commands/connection_command.gd
@tool
class_name ConnectionCommand
extends EditorCommand

var _editor: QuestWeaverEditor
var _graph: QuestGraphResource
var _from_node: StringName
var _from_port: int
var _to_node: StringName
var _to_port: int
var _is_connect_action: bool  # true for connect, false for disconnect


func _init(
	p_editor: QuestWeaverEditor,
	p_graph: QuestGraphResource,
	p_from: StringName,
	p_from_p: int,
	p_to: StringName,
	p_to_p: int,
	p_is_connect: bool
):
	self._editor = p_editor
	self._graph = p_graph
	self._from_node = p_from
	self._from_port = p_from_p
	self._to_node = p_to
	self._to_port = p_to_p
	self._is_connect_action = p_is_connect


func execute() -> void:
	if _is_connect_action:
		_graph.add_connection(_from_node, _from_port, _to_node, _to_port)
	else:
		_graph.remove_connection(_from_node, _from_port, _to_node, _to_port)


func undo() -> void:
	if _is_connect_action:
		_graph.remove_connection(_from_node, _from_port, _to_node, _to_port)
	else:
		_graph.add_connection(_from_node, _from_port, _to_node, _to_port)
