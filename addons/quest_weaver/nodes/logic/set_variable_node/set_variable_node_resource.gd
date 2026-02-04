# res://addons/quest_weaver/nodes/logic/set_variable_node/set_variable_node_resource.gd
@tool
class_name SetVariableNodeResource
extends GraphNodeResource

## The name of the variable in the GameState to modify.
@export var variable_name: StringName = &""

## The value to set, stored as a string for editor compatibility.
@export var value_to_set_string: String = ""

## Optional: An operator to modify values instead of just overwriting them.
enum Operator { SET, ADD, SUBTRACT, MULTIPLY, DIVIDE, TOGGLE }
@export var operator: Operator = Operator.SET


func _init():
	category = "Logic" 
	input_ports = ["In"]
	_update_ports_from_data()

func _update_ports_from_data() -> void:
	if is_terminal:
		output_ports = []
	else:
		output_ports = ["Out"]

func get_editor_summary() -> String:
	var op_text: String
	match operator:
		Operator.SET: op_text = "="
		Operator.ADD: op_text = "+="
		Operator.SUBTRACT: op_text = "-="
		Operator.MULTIPLY: op_text = "*="
		Operator.DIVIDE: op_text = "/="
		Operator.TOGGLE: op_text = "~="
	
	var var_name_text = variable_name if not variable_name.is_empty() else "???"
	
	# For TOGGLE, we don't need to display a value, keeping the UI cleaner.
	if operator == Operator.TOGGLE:
		return "%s %s" % [var_name_text, op_text]
	
	var value_text = value_to_set_string if not value_to_set_string.is_empty() else "???"
	return "%s %s %s" % [var_name_text, op_text, value_text]

func get_description() -> String:
	return "Sets or modifies a global variable in the GameState (Supports math and toggle operations)."

func get_icon() -> Texture2D:
	return preload("res://addons/quest_weaver/assets/icons/setvar.svg")

# Helper function to parse the string into a variant (same as in ConditionResource).
func _parse_string_to_variant(text: String) -> Variant:
	var parsed_value: Variant = text
	if text.is_valid_int():
		parsed_value = text.to_int()
	elif text.is_valid_float():
		parsed_value = text.to_float()
	elif text.to_lower() == "true":
		parsed_value = true
	elif text.to_lower() == "false":
		parsed_value = false
	return parsed_value

func to_dictionary() -> Dictionary:
	var data = super.to_dictionary()
	data["variable_name"] = self.variable_name
	data["value_to_set_string"] = self.value_to_set_string
	data["operator"] = self.operator
	return data

func from_dictionary(data: Dictionary):
	super.from_dictionary(data)
	self.variable_name = StringName(data.get("variable_name", &""))
	self.value_to_set_string = data.get("value_to_set_string", "")
	self.operator = _defensive_load(data, "operator", Operator.keys(), Operator.SET)
	_update_ports_from_data()

## PRIVATE METHOD: Checks if an integer value is valid for the enum type.
func _defensive_load(data: Dictionary, prop: String, keys: Array, default_val: int) -> int:
	var val = data.get(prop, default_val)
	if val is int and val >= 0 and val < keys.size():
		return val
	return default_val

func determine_default_size() -> QWNodeSizes.Size:
	return QWNodeSizes.Size.SMALL
