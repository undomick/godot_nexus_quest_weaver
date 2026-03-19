# res://addons/quest_weaver/nodes/logic/quest_node/quest_node_editor.gd
@tool
class_name QuestNodeEditor
extends NodePropertyEditorBase

@onready var target_quest_id_edit: AutoCompleteLineEdit = %TargetQuestIdEdit
@onready var action_picker: OptionButton = %ActionPicker
@onready var pool_picker: OptionButton = %PoolPicker
@onready var pool_picker_row: HBoxContainer = %PoolPickerRow
@onready var terminal_checkbox: CheckBox = %TerminalCheckBox


func _ready() -> void:
	target_quest_id_edit.text_submitted.connect(_on_id_confirmed)
	target_quest_id_edit.focus_exited.connect(func(): _on_id_confirmed(target_quest_id_edit.text))
	target_quest_id_edit.get_node("%FilterEdit").focus_entered.connect(_on_quest_id_focus_entered)
	terminal_checkbox.toggled.connect(_on_terminal_toggled)
	action_picker.item_selected.connect(_on_action_changed)
	pool_picker.item_selected.connect(_on_pool_changed)


func _on_quest_id_focus_entered() -> void:
	QWEditorUtils.refresh_quest_id_completer_from_active_graph(target_quest_id_edit)


func set_node_data(node_data: GraphNodeResource) -> void:
	super.set_node_data(node_data)
	if not node_data is QuestNodeResource:
		return

	QWEditorUtils.populate_quest_id_completer(target_quest_id_edit)
	target_quest_id_edit.text = node_data.target_quest_id

	action_picker.clear()
	for action_name in node_data.QuestAction.keys():
		action_picker.add_item(action_name.capitalize().replace("_", " "))
	action_picker.select(node_data.action)

	_populate_pool_picker()
	pool_picker_row.visible = node_data.action == QuestNodeResource.QuestAction.MOVE_TO_CUSTOM_POOL
	var pool_ids = QWEditorUtils.get_custom_pool_ids_from_settings()
	var idx = pool_ids.find(node_data.custom_pool_id)
	pool_picker.select(maxi(0, idx) if idx >= 0 else 0)

	terminal_checkbox.button_pressed = node_data.is_terminal


func _on_id_confirmed(new_text: String):
	if is_instance_valid(edited_node_data) and edited_node_data.target_quest_id != new_text:
		property_update_requested.emit(
			edited_node_data.id, "target_quest_id", StringName(new_text), null, {}
		)


func _on_action_changed(index: int) -> void:
	if is_instance_valid(edited_node_data) and edited_node_data.action != index:
		property_update_requested.emit(edited_node_data.id, "action", index, null, {})
	pool_picker_row.visible = index == QuestNodeResource.QuestAction.MOVE_TO_CUSTOM_POOL


func _populate_pool_picker() -> void:
	pool_picker.clear()
	for pool_id in QWEditorUtils.get_custom_pool_ids_from_settings():
		pool_picker.add_item(pool_id)
	if pool_picker.item_count == 0:
		pool_picker.add_item("(No pools configured)")


func _on_pool_changed(index: int) -> void:
	if not is_instance_valid(edited_node_data):
		return
	var pool_ids = QWEditorUtils.get_custom_pool_ids_from_settings()
	if index < 0 or index >= pool_ids.size():
		return
	var new_id = pool_ids[index]
	if edited_node_data.custom_pool_id != new_id:
		property_update_requested.emit(edited_node_data.id, "custom_pool_id", new_id, null, {})


func _on_terminal_toggled(pressed: bool) -> void:
	if is_instance_valid(edited_node_data) and edited_node_data.is_terminal != pressed:
		property_update_requested.emit(edited_node_data.id, "is_terminal", pressed, null, {})
