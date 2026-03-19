# res://addons/quest_weaver/nodes/flow/branch_node/branch_node_resource.gd
@tool
class_name BranchNodeResource
extends GraphNodeResource

enum LogicOperator { AND, OR, NAND, NOR }
@export var operator: LogicOperator = LogicOperator.AND
@export var conditions: Array[ConditionResource] = []


func _init() -> void:
	category = "Flow"
	input_ports = ["In"]
	output_ports = ["True", "False"]

	if id.is_empty() and conditions.is_empty():
		add_condition({})


func check_all_conditions(context: ExecutionContext, instance: QuestInstance) -> bool:
	if conditions.is_empty():
		return true

	match operator:
		LogicOperator.AND:
			for condition in conditions:
				if not is_instance_valid(condition) or not condition.check(context, instance):
					return false
			return true

		LogicOperator.OR:
			for condition in conditions:
				if is_instance_valid(condition) and condition.check(context, instance):
					return true
			return false

		LogicOperator.NAND:  # Not AND
			for condition in conditions:
				if not is_instance_valid(condition) or not condition.check(context, instance):
					return true
			return false

		LogicOperator.NOR:  # Not OR
			for condition in conditions:
				if is_instance_valid(condition) and condition.check(context, instance):
					return false
			return true

	return false


func get_editor_summary() -> String:
	if conditions.is_empty():
		return "[NO CONDITIONS!]"

	var summary_lines: Array[String] = []

	var operator_name = LogicOperator.keys()[operator]
	summary_lines.append(operator_name)

	if conditions.size() >= 1:
		var condition1_summary = _format_condition_summary(conditions[0])
		summary_lines.append("1) %s" % condition1_summary)

	if conditions.size() >= 2:
		var condition2_summary = _format_condition_summary(conditions[1])
		summary_lines.append("2) %s" % condition2_summary)

	if conditions.size() > 2:
		var remaining_count = conditions.size() - 2
		var plural_s = "s" if remaining_count > 1 else ""
		summary_lines.append("... and %d more Condition%s" % [remaining_count, plural_s])

	return "\n".join(summary_lines)


func get_description() -> String:
	return "Splits the flow based on conditions (e.g. check variables, items, or quest states)."


func get_icon() -> Texture2D:
	return preload("res://addons/quest_weaver/assets/icons/branch.svg")


func _format_condition_summary(condition: ConditionResource) -> String:
	if not is_instance_valid(condition):
		return "Invalid Condition"

	var result := ""
	match condition.type:
		ConditionResource.ConditionType.BOOL:
			result = "BOOL is %s" % str(condition.is_true).capitalize()
		ConditionResource.ConditionType.CHANCE:
			result = "CHANCE: %s%%" % condition.chance_percentage
		ConditionResource.ConditionType.CHECK_ITEM:
			if condition.item_id.is_empty():
				result = "CHECK_ITEM:\n(ID missing)"
			else:
				result = "CHECK_ITEM:\n%d x '%s'" % [condition.amount, condition.item_id.get_file()]
		ConditionResource.ConditionType.CHECK_QUEST_STATUS:
			var status_name: String
			if (
				condition.expected_status == QWEnums.QuestState.CUSTOM
				and not condition.expected_custom_pool_id.is_empty()
			):
				status_name = str(condition.expected_custom_pool_id)
			else:
				status_name = QWEnums.QuestState.keys()[condition.expected_status].capitalize()
			result = "QUEST_CHECK:\n'%s' is %s" % [condition.quest_id, status_name]
		ConditionResource.ConditionType.CHECK_VARIABLE:
			var op_keys = ["==", "!=", ">", "<", ">=", "<="]
			var op_symbol = op_keys[condition.operator]
			result = (
				"VAR:\n%s %s %s"
				% [condition.variable_name, op_symbol, condition.expected_value_string]
			)
		ConditionResource.ConditionType.CHECK_OBJECTIVE_STATUS:
			var status_name = (
				ObjectiveResource.Status.keys()[condition.expected_objective_status].capitalize()
			)
			result = "OBJECTIVE:\n...%s is %s" % [condition.objective_id.right(4), status_name]
		ConditionResource.ConditionType.COMPOUND:
			var op_name = condition.LogicOperator.keys()[condition.logic_operator]
			result = "COMPOUND:\n%s (%d sub)" % [op_name, condition.sub_conditions.size()]
		ConditionResource.ConditionType.CHECK_SYNCHRONIZER:
			var check_name = (
				condition.CheckType.keys()[condition.check_type].replace("_", " ").capitalize()
			)
			result = "SYNC:\n%s" % check_name
		ConditionResource.ConditionType.CHECK_OBJECTIVE_REQUIREMENT:
			var id_text = (
				condition.objective_id if not condition.objective_id.is_empty() else "(Missing ID)"
			)
			var inv_hint = " (+Inv)" if condition.include_inventory_holdings else ""
			var any_hint = " (any)" if condition.has_any_progress else ""
			result = "REQ MET:\n'%s'%s%s" % [id_text, inv_hint, any_hint]
		_:
			result = "Unknown Condition"
	return result


func add_condition(payload: Dictionary) -> void:
	if payload.has("condition_instance"):
		var condition_instance = payload.get("condition_instance")
		var index = payload.get("index", -1)
		if is_instance_valid(condition_instance):
			if index > -1 and index <= conditions.size():
				conditions.insert(index, condition_instance)
			else:
				conditions.append(condition_instance)
			return

	var new_condition = ConditionResource.new()
	conditions.append(new_condition)


func remove_condition(payload: Dictionary) -> void:
	if payload.has("condition"):
		var condition_instance = payload.get("condition")
		if conditions.has(condition_instance):
			conditions.erase(condition_instance)
			return

	if payload.has("index"):
		var index = payload.get("index")
		if index >= 0 and index < conditions.size():
			conditions.remove_at(index)


func to_dictionary() -> Dictionary:
	var data = super.to_dictionary()
	data["operator"] = self.operator
	var conditions_data = []
	for c in self.conditions:
		if is_instance_valid(c):
			conditions_data.append(c.to_dictionary())
	data["conditions"] = conditions_data
	return data


func from_dictionary(data: Dictionary):
	super.from_dictionary(data)
	self.operator = _defensive_load(data, "operator", LogicOperator.keys(), LogicOperator.AND)

	self.conditions.clear()
	for c_data in data.get("conditions", []):
		var new_c = GraphNodeResource.new_condition_from_path(c_data.get("@script_path"))
		if is_instance_valid(new_c):
			new_c.from_dictionary(c_data)
			self.conditions.append(new_c)


func _defensive_load(data: Dictionary, prop: String, keys: Array, default_val: int) -> int:
	var val = data.get(prop, default_val)
	if val is int and val >= 0 and val < keys.size():
		return val
	return default_val


func determine_default_size() -> QWNodeSizes.Size:
	return QWNodeSizes.Size.LARGE
