# res://addons/quest_weaver/nodes/logic/text_node/text_node_editor.gd
@tool
extends NodePropertyEditorBase

@onready var target_picker: OptionButton = %TargetPicker
@onready var content_edit: TabFocusTextEdit = %ContentEdit


func _ready() -> void:
	target_picker.item_selected.connect(_on_target_selected)
	content_edit.focus_exited.connect(_on_content_confirmed)


func set_node_data(node_data: GraphNodeResource) -> void:
	super.set_node_data(node_data)
	if not node_data is TextNodeResource:
		return

	target_picker.clear()
	for target_name in node_data.TextTarget.keys():
		var display_name = (
			target_name.replace("SET_", "").replace("ADD_TO_", "").replace("_", " ").capitalize()
		)
		target_picker.add_item(display_name)
	target_picker.select(node_data.target_property)
	content_edit.text = node_data.text_content


func _on_target_selected(index: int) -> void:
	if is_instance_valid(edited_node_data) and edited_node_data.target_property != index:
		property_update_requested.emit(edited_node_data.id, "target_property", index, null, {})


func _on_content_confirmed() -> void:
	var new_text = content_edit.text
	if is_instance_valid(edited_node_data) and edited_node_data.text_content != new_text:
		property_update_requested.emit(edited_node_data.id, "text_content", new_text, null, {})
