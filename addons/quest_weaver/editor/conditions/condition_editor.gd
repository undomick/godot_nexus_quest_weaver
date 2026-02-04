# res://addons/quest_weaver/editor/conditions/condition_editor.gd
@tool
extends PanelContainer

const ConditionEditorScene = preload("res://addons/quest_weaver/editor/conditions/condition_editor.tscn")

signal move_up_requested
signal move_down_requested
signal property_changed(property_name: String, new_value: Variant, target_resource: Resource)
signal rebuild_requested()

@onready var type_picker: OptionButton = %ConditionTypePicker
@onready var property_fields: VBoxContainer = %PropertyFields
@onready var sort_editor: QWSortEditor = find_child("SortEditor", true, false)

var edited_condition: ConditionResource
var _spinbox_undo_values: Dictionary = {}
var _is_setting_up: bool = false

func _ready():
	if is_instance_valid(sort_editor):
		sort_editor.move_up_requested.connect(move_up_requested.emit)
		sort_editor.move_down_requested.connect(move_down_requested.emit)
	
	type_picker.clear()
	for type_name in ConditionResource.ConditionType.keys():
		if type_name == "CHECK_SYNCHRONIZER":
			continue 
		
		var type_value = ConditionResource.ConditionType[type_name]
		type_picker.add_item(type_name.replace("_", " ").capitalize(), type_value)
	
	type_picker.item_selected.connect(_on_type_picker_selected)
	type_picker.tooltip_text = "Select the type of logic check to perform."

func update_sort_index(index: int, total_count: int) -> void:
	if is_instance_valid(sort_editor):
		sort_editor.set_index(index, total_count)
		sort_editor.visible = true
	else:
		# If you use the ConditionEditor for sub-conditions dynamically 
		# where no SortEditor exists, this handles it gracefully.
		#pass
		sort_editor.visible = false

func edit_condition(condition_res: ConditionResource):
	_is_setting_up = true
	self.edited_condition = condition_res
	_rebuild_ui()
	_is_setting_up = false

func _rebuild_ui():
	var previous_setup_state = _is_setting_up
	_is_setting_up = true
	
	for child in property_fields.get_children():
		child.queue_free()
	
	if not is_instance_valid(edited_condition):
		type_picker.select(-1)
		_is_setting_up = previous_setup_state
		return
	
	var item_index = type_picker.get_item_index(edited_condition.type)
	type_picker.select(item_index)
	
	match edited_condition.type:
		ConditionResource.ConditionType.BOOL:
			var checkbox = CheckBox.new()
			checkbox.text = "Returns 'true'"
			checkbox.button_pressed = edited_condition.is_true
			checkbox.toggled.connect(_on_checkbox_toggled.bind("is_true"))
			checkbox.tooltip_text = "If checked, the condition always passes.\nIf unchecked, it always fails."
			add_row("Value", checkbox)
		
		ConditionResource.ConditionType.CHANCE:
			var spinbox = SpinBox.new()
			spinbox.min_value = 0.0; spinbox.max_value = 100.0; spinbox.step = 0.1; spinbox.suffix = "%"
			spinbox.value = edited_condition.chance_percentage
			spinbox.value_changed.connect(func(val):
				if not _is_setting_up: property_changed.emit("chance_percentage", val, edited_condition)
			)
			add_row("Chance", spinbox)
		
		ConditionResource.ConditionType.CHECK_ITEM:
			var item_id_completer = QWConstants.AutoCompleteLineEditScene.instantiate()
			QWEditorUtils.populate_item_completer(item_id_completer)
			item_id_completer.text = edited_condition.item_id
			item_id_completer.text_submitted.connect(func(text): 
				if not _is_setting_up: property_changed.emit("item_id", text, edited_condition)
			)
			add_row("Item ID", item_id_completer)

			var amount_spinbox = SpinBox.new()
			amount_spinbox.min_value = 1; amount_spinbox.step = 1
			amount_spinbox.value = edited_condition.amount
			amount_spinbox.value_changed.connect(func(val): 
				if not _is_setting_up: property_changed.emit("amount", int(val), edited_condition)
			)
			add_row("Amount", amount_spinbox)
		
		ConditionResource.ConditionType.CHECK_QUEST_STATUS:
			var status_picker = OptionButton.new()
			for status_name in QWEnums.QuestState.keys(): 
				status_picker.add_item(status_name)
			status_picker.select(edited_condition.expected_status)
			status_picker.item_selected.connect(_on_option_button_selected.bind("expected_status"))
			add_row("Expected Status", status_picker)
			
			var quest_id_completer = QWConstants.AutoCompleteLineEditScene.instantiate()
			QWEditorUtils.populate_quest_id_completer(quest_id_completer)
			quest_id_completer.text = edited_condition.quest_id
			var filter_edit = quest_id_completer.get_node_or_null("%FilterEdit")
			if is_instance_valid(filter_edit):
				filter_edit.focus_entered.connect(func(): QWEditorUtils.refresh_quest_id_completer_from_active_graph(quest_id_completer))
			quest_id_completer.text_submitted.connect(func(text): 
				if not _is_setting_up: property_changed.emit("quest_id", text, edited_condition)
			)
			add_row("Quest ID", quest_id_completer)
		
		ConditionResource.ConditionType.CHECK_VARIABLE:
			var var_name_edit = LineEdit.new()
			var_name_edit.text = edited_condition.variable_name
			var_name_edit.text_submitted.connect(func(_text): _on_line_edit_confirmed(var_name_edit, "variable_name"))
			var_name_edit.focus_exited.connect(_on_line_edit_confirmed.bind(var_name_edit, "variable_name"))
			add_row("Variable Name", var_name_edit)
			
			var operator_picker = OptionButton.new()
			for op_name in edited_condition.Operator.keys(): operator_picker.add_item(op_name)
			operator_picker.select(edited_condition.operator)
			operator_picker.item_selected.connect(_on_option_button_selected.bind("operator"))
			add_row("Operator", operator_picker)

			var expected_value_edit = LineEdit.new()
			expected_value_edit.placeholder_text = "string, 123, 1.23, true"
			expected_value_edit.text = edited_condition.expected_value_string
			expected_value_edit.text_submitted.connect(func(_text): _on_line_edit_confirmed(expected_value_edit, "expected_value_string"))
			expected_value_edit.focus_exited.connect(_on_line_edit_confirmed.bind(expected_value_edit, "expected_value_string"))
			add_row("Expected Value", expected_value_edit)
		
		ConditionResource.ConditionType.CHECK_OBJECTIVE_STATUS:
			var id_edit = LineEdit.new()
			id_edit.placeholder_text = "Paste Objective ID here..."
			id_edit.text = edited_condition.objective_id
			id_edit.text_submitted.connect(func(_text): _on_line_edit_confirmed(id_edit, "objective_id"))
			id_edit.focus_exited.connect(func(): _on_line_edit_confirmed(id_edit, "objective_id"))
			add_row("Objective ID", id_edit)
			
			var status_picker = OptionButton.new()
			var statuses = ObjectiveResource.Status.keys()
			for status_name in statuses:
				status_picker.add_item(status_name.capitalize())
			status_picker.select(edited_condition.expected_objective_status)
			status_picker.item_selected.connect(_on_option_button_selected.bind("expected_objective_status"))
			add_row("Expected Status", status_picker)
		
		ConditionResource.ConditionType.CHECK_OBJECTIVE_REQUIREMENT:
			var id_edit = LineEdit.new()
			id_edit.placeholder_text = "Target Objective ID..."
			id_edit.text = edited_condition.objective_id
			id_edit.text_submitted.connect(func(_text): _on_line_edit_confirmed(id_edit, "objective_id"))
			id_edit.focus_exited.connect(func(): _on_line_edit_confirmed(id_edit, "objective_id"))
			add_row("Objective ID", id_edit)
			
			var include_inv_checkbox = CheckBox.new()
			include_inv_checkbox.text = "Include Inventory Holdings"
			include_inv_checkbox.button_pressed = edited_condition.include_inventory_holdings
			include_inv_checkbox.toggled.connect(_on_checkbox_toggled.bind("include_inventory_holdings"))
			add_row("Options", include_inv_checkbox)
			
			var has_any_checkbox = CheckBox.new()
			has_any_checkbox.text = "Has Any Progress"
			has_any_checkbox.button_pressed = edited_condition.has_any_progress
			has_any_checkbox.toggled.connect(_on_checkbox_toggled.bind("has_any_progress"))
			has_any_checkbox.tooltip_text = "Pass when player has any items for at least one requirement. Use with GiveTakeItem allow_partial_deposit."
			add_row("", has_any_checkbox)

		ConditionResource.ConditionType.CHECK_SYNCHRONIZER:
			pass

		ConditionResource.ConditionType.COMPOUND:
			var op_picker = OptionButton.new()
			for op_name in edited_condition.LogicOperator.keys(): op_picker.add_item(op_name)
			op_picker.select(edited_condition.logic_operator)
			op_picker.item_selected.connect(_on_option_button_selected.bind("logic_operator"))
			add_row("Logic", op_picker)
			
			for i in range(edited_condition.sub_conditions.size()):
				var sub_condition = edited_condition.sub_conditions[i]
				var sub_editor_container = HBoxContainer.new()
				
				var sub_editor = ConditionEditorScene.instantiate()
				sub_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				sub_editor_container.add_child(sub_editor)
				
				var remove_sub_button = Button.new()
				remove_sub_button.text = "X"
				remove_sub_button.pressed.connect(_on_remove_sub_condition_pressed.bind(i))
				sub_editor_container.add_child(remove_sub_button)
				
				property_fields.add_child(sub_editor_container)
				
				sub_editor.edit_condition(sub_condition)
				
				sub_editor.property_changed.connect(
					func(n, v, r): property_changed.emit(n, v, r)
				)
				sub_editor.rebuild_requested.connect(rebuild_requested.emit)

			var add_button = Button.new()
			add_button.text = "Add Sub-Condition"
			add_button.pressed.connect(_on_add_sub_condition_pressed)
			property_fields.add_child(add_button)
	
	_is_setting_up = previous_setup_state

# --- Signal Handlers ---

func _on_type_picker_selected(index: int):
	if _is_setting_up: return
	var selected_enum_value = type_picker.get_item_id(index)
	
	if is_instance_valid(edited_condition) and edited_condition.type != selected_enum_value:
		property_changed.emit("type", selected_enum_value, edited_condition)
		rebuild_requested.emit()

func _on_checkbox_toggled(is_pressed: bool, property_name: String):
	if _is_setting_up: return
	if is_instance_valid(edited_condition) and edited_condition.get(property_name) != is_pressed:
		property_changed.emit(property_name, is_pressed, edited_condition)

func _on_option_button_selected(index: int, property_name: String):
	if _is_setting_up: return
	if is_instance_valid(edited_condition) and edited_condition.get(property_name) != index:
		property_changed.emit(property_name, index, edited_condition)

func _on_line_edit_confirmed(line_edit: LineEdit, property_name: String):
	if _is_setting_up: return
	var new_text = line_edit.text
	if is_instance_valid(edited_condition) and edited_condition.get(property_name) != new_text:
		property_changed.emit(property_name, new_text, edited_condition)
		
func _on_autocomplete_confirmed(completer: AutoCompleteLineEdit, property_name: String):
	if _is_setting_up: return
	var new_text = completer.text
	if is_instance_valid(edited_condition) and edited_condition.get(property_name) != new_text:
		property_changed.emit(property_name, new_text, edited_condition)

func _connect_spinbox_signals(spinbox: SpinBox, property_name: String) -> void:
	spinbox.focus_entered.connect(_on_spinbox_focus_entered.bind(property_name))
	spinbox.focus_exited.connect(_on_spinbox_focus_exited.bind(spinbox, property_name))
	var line_edit = spinbox.get_line_edit()
	if is_instance_valid(line_edit):
		line_edit.text_submitted.connect(func(_text): _on_spinbox_focus_exited(spinbox, property_name))

func _on_spinbox_focus_entered(property_name: String) -> void:
	if is_instance_valid(edited_condition):
		_spinbox_undo_values[property_name] = edited_condition.get(property_name)

func _on_spinbox_focus_exited(spinbox: SpinBox, property_name: String) -> void:
	if _is_setting_up: return
	var new_value = spinbox.value
	if property_name in ["amount", "sync_value"]:
		new_value = int(new_value)

	var old_value = _spinbox_undo_values.get(property_name)
	
	if is_instance_valid(edited_condition) and old_value != new_value:
		property_changed.emit(property_name, new_value, edited_condition)
		_spinbox_undo_values.erase(property_name)

# --- Handlers for Compound Conditions ---

func _on_add_sub_condition_pressed():
	var new_sub_condition = ConditionResource.new()
	edited_condition.sub_conditions.append(new_sub_condition)
	rebuild_requested.emit()

func _on_remove_sub_condition_pressed(index: int):
	edited_condition.sub_conditions.remove_at(index)
	rebuild_requested.emit()

func add_row(label_text: String, control: Control):
	var row = HBoxContainer.new()
	var label = Label.new()
	label.text = label_text + ": "
	label.custom_minimum_size.x = 120
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	property_fields.add_child(row)
