# res://addons/quest_weaver/nodes/action/play_cutscene_node/play_cutscene_node_editor.gd
@tool
extends NodePropertyEditorBase

@onready var path_edit: LineEdit = %AnimationPlayerPathEdit
@onready var name_edit: LineEdit = %AnimationNameEdit
@onready var wait_checkbox: CheckBox = %WaitForCompletionCheckbox


func _ready() -> void:
	path_edit.text_submitted.connect(func(_text): _on_path_confirmed())
	path_edit.focus_exited.connect(_on_path_confirmed)

	name_edit.text_submitted.connect(func(_text): _on_name_confirmed())
	name_edit.focus_exited.connect(_on_name_confirmed)

	wait_checkbox.toggled.connect(_on_wait_toggled)


func set_node_data(node_data: GraphNodeResource) -> void:
	super.set_node_data(node_data)
	if not node_data is PlayCutsceneNodeResource:
		return

	path_edit.text = str(node_data.animation_player_path)
	name_edit.text = str(node_data.animation_name)
	wait_checkbox.button_pressed = node_data.wait_for_completion


func _on_path_confirmed() -> void:
	var new_text = path_edit.text
	if (
		is_instance_valid(edited_node_data)
		and str(edited_node_data.animation_player_path) != new_text
	):
		property_update_requested.emit(
			edited_node_data.id, "animation_player_path", NodePath(new_text), null, {}
		)


func _on_name_confirmed() -> void:
	var new_text = name_edit.text
	if is_instance_valid(edited_node_data) and str(edited_node_data.animation_name) != new_text:
		property_update_requested.emit(
			edited_node_data.id, "animation_name", StringName(new_text), null, {}
		)


func _on_wait_toggled(is_pressed: bool) -> void:
	if is_instance_valid(edited_node_data) and edited_node_data.wait_for_completion != is_pressed:
		property_update_requested.emit(
			edited_node_data.id, "wait_for_completion", is_pressed, null, {}
		)
