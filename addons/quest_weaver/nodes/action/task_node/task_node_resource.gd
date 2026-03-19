# res://addons/quest_weaver/nodes/action/task_node/task_node_resource.gd
@tool
class_name TaskNodeResource
extends GraphNodeResource

## A list of concrete objectives that must be completed.
@export var objectives: Array[ObjectiveResource] = []


func _init():
	category = "Action"

	if id.is_empty() and objectives.is_empty():
		var new_objective = ObjectiveResource.new()
		new_objective.id = "objective_%d" % Time.get_unix_time_from_system()
		new_objective.description = "New Objective"
		objectives.append(new_objective)

	input_ports = ["In"]
	_update_ports_from_data()


func _update_ports_from_data() -> void:
	if is_terminal:
		output_ports = []
	else:
		output_ports = ["Out"]


func get_editor_summary() -> String:
	if objectives.is_empty():
		return "(No Objectives!)"

	var summary_lines: Array[String] = []

	for i in range(min(objectives.size(), 3)):
		var objective: ObjectiveResource = objectives[i]
		if not is_instance_valid(objective):
			continue

		var trigger_type_name = (
			ObjectiveResource
			. TriggerType
			. keys()[objective.trigger_type]
			. replace("_", " ")
			. capitalize()
		)
		var description_preview: String
		var warning_prefix = ""

		if objective.description.is_empty():
			description_preview = "Missing Objective Title"
			warning_prefix = "[WARN]"
		else:
			description_preview = (
				objective.description.left(30)
				+ ("..." if objective.description.length() > 30 else "")
			)

		var objective_summary = (
			"%s%d) %s:\n   %s" % [warning_prefix, i + 1, description_preview, trigger_type_name]
		)
		summary_lines.append(objective_summary)

	if objectives.size() > 3:
		var remaining_count = objectives.size() - 3
		var plural_s = "s" if remaining_count > 1 else ""
		summary_lines.append("... and %d more Objective%s" % [remaining_count, plural_s])

	return "\n".join(summary_lines)


func get_description() -> String:
	return "A container for active objectives (e.g., 'Kill 5 Rats', 'Collect Wood') that the player must complete."


func get_icon() -> Texture2D:
	return preload("res://addons/quest_weaver/assets/icons/objective.svg")


func add_objective(payload: Dictionary):
	if payload.has("objective_instance"):
		var objective_instance = payload.get("objective_instance")
		if is_instance_valid(objective_instance):
			objectives.append(objective_instance)
			return

	var new_objective = ObjectiveResource.new()
	new_objective.id = "objective_%d" % Time.get_unix_time_from_system()
	new_objective.description = "New Objective"
	objectives.append(new_objective)


func remove_objective(payload: Dictionary):
	if payload.has("objective"):
		objectives.erase(payload["objective"])


func update_objective_description(payload: Dictionary):
	if payload.has("objective") and payload.has("new_description"):
		var objective: ObjectiveResource = payload["objective"]
		objective.description = payload["new_description"]


func update_objective_trigger_type(payload: Dictionary):
	if payload.has("objective") and payload.has("new_type_index"):
		var objective: ObjectiveResource = payload["objective"]
		var new_type_index = payload["new_type_index"]
		var new_type = ObjectiveResource.TriggerType.values()[new_type_index]

		if objective.trigger_type == new_type:
			return

		objective.trigger_type = new_type

		match new_type:
			ObjectiveResource.TriggerType.MANUAL, ObjectiveResource.TriggerType.INTERACT, ObjectiveResource.TriggerType.LOCATION_ENTER:
				pass


func update_objective_trigger_param(payload: Dictionary):
	if payload.has("objective") and payload.has("param_name") and payload.has("param_value"):
		var objective: ObjectiveResource = payload["objective"]
		var param_name = payload["param_name"]
		var param_value = payload["param_value"]

		objective.trigger_params[param_name] = param_value


func update_objective_id(payload: Dictionary):
	if payload.has("objective") and payload.has("new_id"):
		var obj: ObjectiveResource = payload["objective"]
		obj.id = payload["new_id"]


func update_objective_requirements(payload: Dictionary):
	if payload.has("objective") and payload.has("requirements"):
		var obj: ObjectiveResource = payload["objective"]
		# Clone dictionary to ensure unique ref for history
		obj.requirements = payload["requirements"].duplicate()


func to_dictionary() -> Dictionary:
	var data = super.to_dictionary()

	var objectives_data = []
	for objective in self.objectives:
		if is_instance_valid(objective):
			objectives_data.append(objective.to_dictionary())

	data["objectives"] = objectives_data
	return data


func from_dictionary(data: Dictionary):
	super.from_dictionary(data)

	self.objectives.clear()
	var objectives_data = data.get("objectives", [])
	for objective_dict in objectives_data:
		var script_path = objective_dict.get("@script_path")
		if script_path:
			var script = GraphNodeResource.get_script_cached(script_path)
			if script:
				var new_objective = script.new()
				new_objective.from_dictionary(objective_dict)
				self.objectives.append(new_objective)

	_update_ports_from_data()


func _validate(context: Dictionary) -> Array[ValidationResult]:
	var results: Array[ValidationResult] = []
	var item_registry = context.get("item_registry")

	if objectives.is_empty():
		results.append(
			ValidationResult.new(
				ValidationResult.Severity.WARNING,
				"Task Node has no objectives and will complete immediately.",
				id
			)
		)
	else:
		for objective in objectives:
			if not is_instance_valid(objective):
				results.append(
					ValidationResult.new(
						ValidationResult.Severity.ERROR,
						"Task Node contains an invalid/empty Objective.",
						id
					)
				)
				continue

			if objective.id.is_empty():
				results.append(
					ValidationResult.new(
						ValidationResult.Severity.ERROR, "Objective has no ID.", id
					)
				)

			# Validate based on requirements dictionary
			match objective.trigger_type:
				ObjectiveResource.TriggerType.ITEM_COLLECT:
					if objective.requirements.is_empty():
						results.append(
							ValidationResult.new(
								ValidationResult.Severity.ERROR,
								"Objective 'Item Collect': No items defined in requirements.",
								id
							)
						)
					elif is_instance_valid(item_registry):
						for item_id in objective.requirements.keys():
							if not item_registry.find(str(item_id)):
								results.append(
									ValidationResult.new(
										ValidationResult.Severity.WARNING,
										"Item ID '%s' not found in Registry." % item_id,
										id
									)
								)

				ObjectiveResource.TriggerType.KILL:
					if objective.requirements.is_empty():
						results.append(
							ValidationResult.new(
								ValidationResult.Severity.ERROR,
								"Objective 'Kill': No enemies defined in requirements.",
								id
							)
						)

				ObjectiveResource.TriggerType.INTERACT:
					if objective.trigger_params.get("target_path", "").is_empty():
						results.append(
							ValidationResult.new(
								ValidationResult.Severity.ERROR,
								"Objective 'Interact': No Target Path specified.",
								id
							)
						)

				ObjectiveResource.TriggerType.LOCATION_ENTER:
					if objective.trigger_params.get("location_id", "").is_empty():
						results.append(
							ValidationResult.new(
								ValidationResult.Severity.ERROR,
								"Objective 'Location Enter': No Location ID specified.",
								id
							)
						)

	return results


func determine_default_size() -> QWNodeSizes.Size:
	return QWNodeSizes.Size.LARGE
