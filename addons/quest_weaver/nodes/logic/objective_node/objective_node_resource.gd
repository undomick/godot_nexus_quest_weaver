# res://addons/quest_weaver/nodes/logic/objective_node/objective_node_resource.gd
@tool
class_name ObjectiveNodeResource
extends GraphNodeResource

enum Action { COMPLETE, FAIL, RESET }

# The ID of the objective to be completed.
@export var target_objective_id: StringName = &""

@export var action: Action = Action.COMPLETE

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
	var action_text = Action.keys()[action].capitalize()
	
	var line2: String
	if target_objective_id.is_empty():
		line2 = "[WARN]Target: (Not Set)"
	else:
		line2 = "'%s'" % target_objective_id
	
	return "%s:\n%s" % [action_text, line2]

func get_display_name() -> String:
	return "Set Objective Node"

func get_description() -> String:
	return "Changes the status of a specific manual objective (Complete, Fail, or Reset)."

func get_icon() -> Texture2D:
	return preload("res://addons/quest_weaver/assets/icons/complete_quest.svg")

func to_dictionary() -> Dictionary:
	var data = super.to_dictionary()
	data["target_objective_id"] = self.target_objective_id
	data["action"] = self.action
	return data

func from_dictionary(data: Dictionary):
	super.from_dictionary(data)
	self.target_objective_id = StringName(data.get("target_objective_id", &""))
	self.action = data.get("action", Action.COMPLETE)
	_update_ports_from_data()

func _validate(_context: Dictionary) -> Array[ValidationResult]:
	var results: Array[ValidationResult] = []
	if target_objective_id.is_empty():
		results.append(ValidationResult.new(ValidationResult.Severity.ERROR, "Set Objective: Target Objective ID is not set.", id))
		
	return results

func determine_default_size() -> QWNodeSizes.Size:
	return QWNodeSizes.Size.SMALL
