# res://addons/quest_weaver/editor/components/synchronize_output_editor_entry.gd
@tool

class_name SynchronizeOutputEditorEntry

extends VBoxContainer

signal remove_requested

signal name_changed(new_name: String)

# FIX: Added target_resource
signal property_changed(property_name: String, new_value: Variant, target_resource: Resource)

signal type_changed(new_script: Script)

var output_port: SynchronizeOutputPort

var _port_name_undo_value: String = ""

@onready var remove_button: Button = %RemoveButton

@onready var port_name_edit: LineEdit = %PortNameEdit

@onready var condition_editor: PanelContainer = %ConditionEditor


func _ready() -> void:
	remove_button.pressed.connect(remove_requested.emit)

	port_name_edit.focus_entered.connect(func(): _port_name_undo_value = port_name_edit.text)
	port_name_edit.text_submitted.connect(func(_text): _on_port_name_confirmed())
	port_name_edit.focus_exited.connect(_on_port_name_confirmed)

	condition_editor.rebuild_requested.connect(func(): type_changed.emit(null))


func display_data(p_output_port: SynchronizeOutputPort) -> void:
	self.output_port = p_output_port
	port_name_edit.text = p_output_port.port_name

	for child in condition_editor.get_children():
		child.queue_free()

	# Note: SyncConditionEditor is specialized and static.
	var specialized_editor = QWConstants.SyncConditionEditorScene.instantiate()
	condition_editor.add_child(specialized_editor)

	specialized_editor.edit_condition(p_output_port.condition)
	# FIX: SyncCondEditor is simple, but we should make it consistent.
	specialized_editor.property_changed.connect(
		func(n, v): property_changed.emit(n, v, p_output_port.condition)
	)


func _on_port_name_confirmed() -> void:
	if not is_instance_valid(output_port):
		return
	var new_name = port_name_edit.text
	if _port_name_undo_value != new_name:
		name_changed.emit(new_name)
