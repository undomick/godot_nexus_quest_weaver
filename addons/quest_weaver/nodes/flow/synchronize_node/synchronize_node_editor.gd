# res://addons/quest_weaver/nodes/flow/synchronize_node/synchronize_node_editor.gd
@tool

class_name SynchronizeNodeEditor

extends NodePropertyEditorBase

signal ports_need_refresh

var _is_setting_up := false

@onready var keep_listening_checkbox: CheckBox = %KeepListeningCheckbox

@onready var add_input_button: Button = %AddInputButton

@onready var add_output_button: Button = %AddOutputButton

@onready var logic_option_button: OptionButton = %LogicOptionButton

@onready var matrix_container: GridContainer = %MatrixContainer2


func _ready():
	if is_instance_valid(keep_listening_checkbox):
		keep_listening_checkbox.toggled.connect(_on_keep_listening_toggled)
	add_input_button.pressed.connect(_on_add_input_pressed)
	add_output_button.pressed.connect(_on_add_output_pressed)

	if not logic_option_button.item_selected.is_connected(_on_logic_mode_changed):
		logic_option_button.item_selected.connect(_on_logic_mode_changed)


func set_node_data(node_data: GraphNodeResource):
	_is_setting_up = true
	super.set_node_data(node_data)
	if not node_data is SynchronizeNodeResource:
		_is_setting_up = false
		return

	if is_instance_valid(keep_listening_checkbox):
		keep_listening_checkbox.button_pressed = node_data.keep_listening
	if is_instance_valid(logic_option_button):
		logic_option_button.select(node_data.logic_mode)

	_rebuild_ui()
	_is_setting_up = false


func _on_keep_listening_toggled(pressed: bool) -> void:
	if _is_setting_up:
		return
	if is_instance_valid(edited_node_data) and edited_node_data is SynchronizeNodeResource:
		if edited_node_data.keep_listening != pressed:
			property_update_requested.emit(edited_node_data.id, "keep_listening", pressed, null, {})


func _on_logic_mode_changed(index: int) -> void:
	if _is_setting_up:
		return
	if is_instance_valid(edited_node_data):
		property_update_requested.emit(edited_node_data.id, "logic_mode", index, null, {})


func _rebuild_ui():
	if not is_instance_valid(edited_node_data):
		return
	var sync_node: SynchronizeNodeResource = edited_node_data

	# Ensure container exists
	if not is_instance_valid(matrix_container):
		return

	for child in matrix_container.get_children():
		child.queue_free()

	# Transposed Layout:
	# Columns = Corner(1) + N Outputs + InputDelete(1)
	var col_count = sync_node.outputs.size() + 2
	matrix_container.columns = max(1, col_count)

	# ============================================================
	# ROW 1: HEADER (Output Names)
	# ============================================================

	# 1. Corner Top-Left
	var corner_tl = Label.new()
	corner_tl.text = "In \\ Out"  # Inputs are Rows, Outputs are Cols
	corner_tl.modulate = Color(1, 1, 1, 0.5)
	corner_tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	matrix_container.add_child(corner_tl)

	# 2. Output Names (Horizontal Header)
	for out_idx in range(sync_node.outputs.size()):
		var out_port = sync_node.outputs[out_idx]
		var name_edit = LineEdit.new()
		name_edit.text = out_port.port_name
		name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_edit.tooltip_text = "Rename Output Port"
		name_edit.custom_minimum_size.x = 60
		name_edit.expand_to_text_length = true

		name_edit.text_submitted.connect(func(t): _on_output_name_changed(t, out_idx))
		name_edit.focus_exited.connect(func(): _on_output_name_changed(name_edit.text, out_idx))

		matrix_container.add_child(name_edit)

	# 3. Corner Top-Right (Empty)
	var corner_tr = Control.new()
	matrix_container.add_child(corner_tr)

	# ============================================================
	# ROW 2..N: BODY (Input Rows)
	# ============================================================
	for in_idx in range(sync_node.inputs.size()):
		var input_port = sync_node.inputs[in_idx]

		# 1. Input Name (Left Column)
		var name_edit = LineEdit.new()
		name_edit.text = input_port.port_name
		name_edit.custom_minimum_size.x = 80
		name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_edit.text_submitted.connect(func(t): _on_input_name_changed(t, in_idx))
		name_edit.focus_exited.connect(func(): _on_input_name_changed(name_edit.text, in_idx))
		matrix_container.add_child(name_edit)

		# 2. Matrix Cells (Iterate Outputs for this Input)
		for out_idx in range(sync_node.outputs.size()):
			var out_port = sync_node.outputs[out_idx]

			var current_state = SynchronizeNodeResource.InputState.IGNORE
			if in_idx < out_port.patterns.size():
				current_state = out_port.patterns[in_idx]

			var btn = Button.new()
			btn.custom_minimum_size = Vector2(32, 32)
			btn.flat = false
			_update_pattern_button_visual(btn, current_state)

			btn.pressed.connect(_on_pattern_cycle.bind(out_idx, in_idx, current_state))
			matrix_container.add_child(btn)

		# 3. Remove Input Button (Right Column)
		var del_btn = Button.new()
		del_btn.text = "X"
		del_btn.tooltip_text = "Delete Input"
		del_btn.pressed.connect(_on_remove_input_pressed.bind(in_idx))
		matrix_container.add_child(del_btn)

	# ============================================================
	# ROW N+1: FOOTER (Output Deletion)
	# ============================================================

	# 1. Corner Bottom-Left
	var corner_bl = Control.new()
	matrix_container.add_child(corner_bl)

	# 2. Output Delete Buttons (Bottom Row)
	for out_idx in range(sync_node.outputs.size()):
		var del_btn = Button.new()
		del_btn.text = "X"
		del_btn.tooltip_text = "Delete Output Column"
		# Styling removed to match side buttons
		del_btn.pressed.connect(_on_remove_output_pressed.bind(out_idx))
		matrix_container.add_child(del_btn)

	# 3. Corner Bottom-Right
	var corner_br = Control.new()
	matrix_container.add_child(corner_br)


func _update_pattern_button_visual(btn: Button, state: int):
	match state:
		SynchronizeNodeResource.InputState.IGNORE:
			btn.text = "-"
			btn.modulate = Color(1, 1, 1, 0.3)
			btn.tooltip_text = "Ignore this input"
		SynchronizeNodeResource.InputState.REQUIRED:
			btn.text = "✓"
			btn.modulate = Color.GREEN
			btn.tooltip_text = "Input REQUIRED"
		SynchronizeNodeResource.InputState.FORBIDDEN:
			btn.text = "X"
			btn.modulate = Color.RED
			btn.tooltip_text = "Input FORBIDDEN"


func _on_pattern_cycle(out_idx: int, in_idx: int, current_state: int):
	var next_state = (current_state + 1) % 3

	var payload = {"output_index": out_idx, "input_index": in_idx, "state": next_state}
	complex_action_requested.emit(edited_node_data.id, "update_sync_pattern", payload)


# --- Input Handlers ---


func _on_add_input_pressed():
	complex_action_requested.emit(edited_node_data.id, "add_sync_input", {})


func _on_remove_input_pressed(index: int):
	var payload = {"index": index}
	complex_action_requested.emit(edited_node_data.id, "remove_sync_input", payload)


func _on_input_name_changed(new_name: String, index: int):
	if _is_setting_up:
		return
	var payload = {"index": index, "new_name": new_name}
	complex_action_requested.emit(edited_node_data.id, "update_sync_input_name", payload)


# --- Output Handlers ---


func _on_add_output_pressed():
	complex_action_requested.emit(edited_node_data.id, "add_sync_output", {})


func _on_remove_output_pressed(index: int):
	complex_action_requested.emit(edited_node_data.id, "remove_sync_output", {"index": index})


func _on_output_name_changed(new_name: String, index: int):
	if _is_setting_up:
		return
	var payload = {"index": index, "new_name": new_name}
	complex_action_requested.emit(edited_node_data.id, "update_sync_output_name", payload)
