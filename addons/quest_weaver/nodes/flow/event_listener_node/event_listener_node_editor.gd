# res://addons/quest_weaver/nodes/flow/event_listener_node/event_listener_node_editor.gd
@tool

extends NodePropertyEditorBase

const SimpleConditionEntryScene = preload(
	"res://addons/quest_weaver/editor/components/simple_condition_entry.tscn"
)

const AdvancedConditionEditorScene = preload(
	"res://addons/quest_weaver/editor/conditions/condition_editor.tscn"
)

var _is_setting_up := false

@onready var event_name_edit: LineEdit = %EventNameEdit

@onready var keep_listening_checkbox: CheckBox = %KeepListeningCheckbox

@onready var simple_mode_checkbox: CheckBox = %SimpleModeCheckBox

@onready var simple_conditions_container: VBoxContainer = %SimpleConditionsContainer

@onready var add_simple_condition_button: Button = %AddSimpleConditionButton

@onready var advanced_condition_container: VBoxContainer = %ConditionContainer


func _ready() -> void:
	event_name_edit.text_submitted.connect(func(_text): _on_event_name_confirmed())
	event_name_edit.focus_exited.connect(_on_event_name_confirmed)
	simple_mode_checkbox.toggled.connect(_on_simple_mode_toggled)
	add_simple_condition_button.pressed.connect(_on_add_simple_condition_pressed)
	keep_listening_checkbox.toggled.connect(_on_keep_listening_toggled)


func set_node_data(node_data: GraphNodeResource) -> void:
	_is_setting_up = true
	super.set_node_data(node_data)
	if not node_data is EventListenerNodeResource:
		_is_setting_up = false
		return

	event_name_edit.text = node_data.event_name
	simple_mode_checkbox.button_pressed = node_data.use_simple_conditions
	keep_listening_checkbox.button_pressed = node_data.keep_listening

	_rebuild_ui()
	_is_setting_up = false


func _on_keep_listening_toggled(pressed: bool) -> void:
	if _is_setting_up:
		return
	if is_instance_valid(edited_node_data):
		property_update_requested.emit(edited_node_data.id, "keep_listening", pressed, null, {})


func _rebuild_ui():
	var use_simple = simple_mode_checkbox.button_pressed
	simple_conditions_container.visible = use_simple
	add_simple_condition_button.visible = use_simple
	advanced_condition_container.visible = not use_simple

	if use_simple:
		_rebuild_simple_conditions_list()
	else:
		_rebuild_advanced_condition_editor()


func _rebuild_simple_conditions_list():
	for child in simple_conditions_container.get_children():
		child.queue_free()

	var listener_node = edited_node_data as EventListenerNodeResource
	for i in range(listener_node.simple_conditions.size()):
		var condition_data = listener_node.simple_conditions[i]
		var entry_instance = SimpleConditionEntryScene.instantiate()

		entry_instance.changed.connect(_on_simple_condition_changed.bind(i))
		entry_instance.removed.connect(_on_simple_condition_removed.bind(i))

		simple_conditions_container.add_child(entry_instance)
		entry_instance.set_data(condition_data)


func _rebuild_advanced_condition_editor():
	for child in advanced_condition_container.get_children():
		child.queue_free()

	var listener_node = edited_node_data as EventListenerNodeResource
	if (
		not is_instance_valid(listener_node)
		or not is_instance_valid(listener_node.payload_condition)
	):
		return

	var editor_instance = AdvancedConditionEditorScene.instantiate()
	advanced_condition_container.add_child(editor_instance)

	editor_instance.edit_condition(listener_node.payload_condition)

	editor_instance.property_changed.connect(
		func(prop_name, new_value, _target_res):
			property_update_requested.emit(
				edited_node_data.id, prop_name, new_value, null, {"payload_condition": true}
			)
	)

	editor_instance.rebuild_requested.connect(_rebuild_advanced_condition_editor)


func _on_event_name_confirmed():
	if _is_setting_up:
		return
	var new_text = event_name_edit.text
	if is_instance_valid(edited_node_data) and edited_node_data.event_name != new_text:
		property_update_requested.emit(
			edited_node_data.id, "event_name", StringName(new_text), null, {}
		)


func _on_simple_mode_toggled(is_pressed: bool):
	if _is_setting_up:
		return
	if is_instance_valid(edited_node_data) and edited_node_data.use_simple_conditions != is_pressed:
		property_update_requested.emit(
			edited_node_data.id, "use_simple_conditions", is_pressed, null, {}
		)
	_rebuild_ui()


func _on_add_simple_condition_pressed():
	if _is_setting_up:
		return
	if not is_instance_valid(edited_node_data):
		return
	complex_action_requested.emit(edited_node_data.id, "add_simple_condition", {})


func _on_simple_condition_changed(new_data: Dictionary, index: int):
	if _is_setting_up:
		return
	if not is_instance_valid(edited_node_data):
		return
	complex_action_requested.emit(
		edited_node_data.id, "update_simple_condition", {"index": index, "new_data": new_data}
	)


func _on_simple_condition_removed(index: int):
	if _is_setting_up:
		return
	if not is_instance_valid(edited_node_data):
		return
	complex_action_requested.emit(edited_node_data.id, "remove_simple_condition", {"index": index})
