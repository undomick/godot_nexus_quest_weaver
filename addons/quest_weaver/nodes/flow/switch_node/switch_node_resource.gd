@tool
class_name SwitchNodeResource
extends GraphNodeResource

## Variable-based multi-way branch. Reads a GameState variable and routes to the matching case or Default.

@export var variable_name: StringName = &""
@export var cases: Array[SwitchCasePort] = []


func _init() -> void:
	category = "Flow"
	input_ports = ["In"]
	if id.is_empty() and cases.is_empty():
		var c1 = SwitchCasePort.new()
		c1.value_string = "1"
		c1.port_name = &"Case 1"
		var c2 = SwitchCasePort.new()
		c2.value_string = "2"
		c2.port_name = &"Case 2"
		cases.append(c1)
		cases.append(c2)
	_update_ports_from_data()


func _update_ports_from_data() -> void:
	output_ports.clear()
	for c in cases:
		if is_instance_valid(c):
			output_ports.append(c.port_name)
	output_ports.append(&"Default")


func get_editor_summary() -> String:
	var var_text = String(variable_name) if not variable_name.is_empty() else "[No Variable]"
	return "Var: %s\n%d cases + Default" % [var_text, cases.size()]


func get_display_name() -> String:
	return "Switch"


func get_description() -> String:
	return "Branches flow based on a variable value. Routes to the matching case or Default when no match."


func get_icon() -> Texture2D:
	return preload("res://addons/quest_weaver/assets/icons/branch.svg")


func add_switch_case(_payload: Dictionary = {}) -> void:
	var new_case = SwitchCasePort.new()
	new_case.value_string = str(cases.size() + 1)
	new_case.port_name = StringName("Case %s" % (char(65 + cases.size())))
	cases.append(new_case)
	_update_ports_from_data()


func remove_switch_case(payload: Dictionary) -> void:
	var idx: int = payload.get("index", -1)
	if idx >= 0 and idx < cases.size():
		cases.remove_at(idx)
		_update_ports_from_data()


func update_switch_case_value(payload: Dictionary) -> void:
	var idx: int = payload.get("index", -1)
	if idx >= 0 and idx < cases.size() and payload.has("new_value"):
		cases[idx].value_string = str(payload["new_value"])


func update_switch_case_name(payload: Dictionary) -> void:
	var idx: int = payload.get("index", -1)
	if idx >= 0 and idx < cases.size() and payload.has("new_name"):
		cases[idx].port_name = StringName(str(payload["new_name"]))
		_update_ports_from_data()


func to_dictionary() -> Dictionary:
	var data = super.to_dictionary()
	data["variable_name"] = variable_name
	var cases_data: Array = []
	for c in cases:
		if is_instance_valid(c):
			cases_data.append(c.to_dictionary())
	data["cases"] = cases_data
	return data


func from_dictionary(data: Dictionary) -> void:
	super.from_dictionary(data)
	variable_name = StringName(data.get("variable_name", &""))
	cases.clear()
	for c_data in data.get("cases", []):
		var script = GraphNodeResource.get_script_cached(c_data.get("@script_path", ""))
		var new_c: SwitchCasePort = script.new() if script else SwitchCasePort.new()
		new_c.from_dictionary(c_data)
		cases.append(new_c)
	_update_ports_from_data()


func _validate(_context: Dictionary) -> Array[ValidationResult]:
	var results: Array[ValidationResult] = []
	if variable_name.is_empty():
		results.append(
			ValidationResult.new(
				ValidationResult.Severity.ERROR, "Switch: Variable name is not set.", id
			)
		)
	return results


func determine_default_size() -> QWNodeSizes.Size:
	return QWNodeSizes.Size.LARGE
