# res://addons/quest_weaver/nodes/flow/random_node/random_node_editor.gd
@tool

class_name RandomNodeEditor

extends NodePropertyEditorBase

signal ports_need_refresh(node_id: String)

const OutputEntryScene = preload(
	"res://addons/quest_weaver/editor/components/random_output_editor_entry.tscn"
)

# --- Specific handlers for the weight SpinBox ---

var _weight_undo_value: int = 0

@onready var outputs_container: VBoxContainer = %OutputsContainer

@onready var add_output_button: Button = %AddOutputButton


func _ready():
	add_output_button.pressed.connect(_on_add_output_pressed)


func set_node_data(node_data: GraphNodeResource):
	super.set_node_data(node_data)
	if not node_data is RandomNodeResource:
		return

	call_deferred(&"_rebuild_outputs_list")


func _rebuild_outputs_list():
	for child in outputs_container.get_children():
		child.queue_free()

	var random_node: RandomNodeResource = edited_node_data
	if not is_instance_valid(random_node):
		return

	for i in range(random_node.outputs.size()):
		var output_port = random_node.outputs[i]
		var entry_instance: HBoxContainer = OutputEntryScene.instantiate()

		# Connect to the "finished" signals of the controls inside the entry
		var name_edit: LineEdit = entry_instance.get_node("PortNameEdit")
		name_edit.text_submitted.connect(func(_text): _on_output_name_confirmed(i, name_edit))
		name_edit.focus_exited.connect(_on_output_name_confirmed.bind(i, name_edit))

		var weight_spinbox: SpinBox = entry_instance.get_node("WeightSpinBox")
		weight_spinbox.focus_entered.connect(_on_weight_edit_started.bind(output_port))
		weight_spinbox.focus_exited.connect(
			_on_weight_edit_finished.bind(i, output_port, weight_spinbox)
		)
		# value_changed is used for live UI updates without creating history
		weight_spinbox.value_changed.connect(_on_weight_value_changed_live.bind(i))

		entry_instance.get_node("RemoveButton").pressed.connect(_on_remove_output_pressed.bind(i))

		outputs_container.add_child(entry_instance)
		entry_instance.display_data(output_port)


func _on_add_output_pressed():
	complex_action_requested.emit(edited_node_data.id, "add_random_output", {})
	call_deferred(&"_rebuild_outputs_list")


func _on_remove_output_pressed(index: int):
	var payload = {"index": index}
	complex_action_requested.emit(edited_node_data.id, "remove_random_output", payload)
	call_deferred(&"_rebuild_outputs_list")


func _on_output_name_confirmed(index: int, name_edit: LineEdit):
	var new_name = name_edit.text
	var random_node: RandomNodeResource = edited_node_data
	if is_instance_valid(random_node) and random_node.outputs[index].port_name != new_name:
		var payload = {"index": index, "new_name": new_name}
		complex_action_requested.emit(edited_node_data.id, "update_random_output_name", payload)


func _on_weight_edit_started(output_port: RandomOutputPort):
	_weight_undo_value = output_port.weight


func _on_weight_value_changed_live(new_weight: float, index: int):
	var random_node: RandomNodeResource = edited_node_data
	if is_instance_valid(random_node) and index < random_node.outputs.size():
		# Directly change the data for live updates of port percentages
		random_node.outputs[index].weight = int(new_weight)
		random_node._update_ports_from_data()  # Update internal port names

		# The 'ports_need_refresh' signal now expects the node's ID as an argument.
		ports_need_refresh.emit(edited_node_data.id)


func _on_weight_edit_finished(index: int, output_port: RandomOutputPort, spinbox: SpinBox):
	var final_weight = int(spinbox.value)

	# Revert the live change before creating the history action
	output_port.weight = _weight_undo_value

	if _weight_undo_value != final_weight:
		# Use output_index so the action handler resolves the target from the editable graph
		property_update_requested.emit(
			edited_node_data.id, "weight", final_weight, null, {"output_index": index}
		)
