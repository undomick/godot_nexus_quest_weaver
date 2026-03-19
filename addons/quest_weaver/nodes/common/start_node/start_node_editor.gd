# res://addons/quest_weaver/nodes/common/start_node/start_node_editor.gd
@tool
extends NodePropertyEditorBase

@onready var category_edit: LineEdit = %CategoryEdit


func _ready() -> void:
	category_edit.text_submitted.connect(func(_text): _on_category_confirmed())
	category_edit.focus_exited.connect(_on_category_confirmed)


func set_node_data(node_data: GraphNodeResource) -> void:
	super.set_node_data(node_data)
	if not node_data is StartNodeResource:
		return

	category_edit.text = node_data.graph_category
	category_edit.placeholder_text = "e.g. Act 1, Side Quests..."


func _on_category_confirmed() -> void:
	var new_text = category_edit.text
	if is_instance_valid(edited_node_data) and edited_node_data.graph_category != new_text:
		property_update_requested.emit(edited_node_data.id, "graph_category", new_text, null, {})
