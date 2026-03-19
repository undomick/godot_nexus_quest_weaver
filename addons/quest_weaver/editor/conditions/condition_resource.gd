# res://addons/quest_weaver/editor/conditions/condition_resource.gd
@tool

class_name ConditionResource

extends Resource

# Note: Local QuestState enum removed. We now use QWEnums.QuestState.

enum ConditionType {
	BOOL,
	CHANCE,
	CHECK_ITEM,
	CHECK_QUEST_STATUS,
	CHECK_VARIABLE,
	CHECK_SYNCHRONIZER,
	CHECK_OBJECTIVE_REQUIREMENT,
	CHECK_OBJECTIVE_STATUS,
	COMPOUND
}

enum Operator { EQUALS, NOT_EQUALS, GREATER_THAN, LESS_THAN, GREATER_OR_EQUAL, LESS_OR_EQUAL }

# --- CheckSynchronizerCondition ---
enum CheckType { RECEIVED_N_INPUTS, RECEIVED_SPECIFIC_INPUT }

# --- CompoundCondition ---
enum LogicOperator { AND, OR }

@export var type: ConditionType = ConditionType.BOOL

# --- BoolCondition ---
@export var is_true: bool = true

# --- CheckItemCondition ---
@export var item_id: StringName = &""

@export var amount: int = 1

# --- CheckQuestStatusCondition ---
@export var quest_id: StringName = &""

# Updated to use Global Enum
@export var expected_status: QWEnums.QuestState = QWEnums.QuestState.COMPLETED

## When expected_status is CUSTOM, specifies which pool. Empty = any custom pool.
@export var expected_custom_pool_id: StringName = &""

# --- CheckVariableCondition ---
@export var variable_name: StringName = &""

@export var expected_value_string: String = ""

@export var operator: Operator = Operator.EQUALS

@export var check_type: CheckType = CheckType.RECEIVED_N_INPUTS

@export var sync_value: int = 1

# --- CheckObjectiveStatusCondition ---
@export var objective_id: StringName = &""

@export var expected_objective_status: ObjectiveResource.Status = ObjectiveResource.Status.COMPLETED

@export var logic_operator: LogicOperator = LogicOperator.AND

@export var sub_conditions: Array[ConditionResource] = []

@export var include_inventory_holdings: bool = false

## If true: passes when player has any progress (potential > 0) for at least one requirement. Use with GiveTakeItem allow_partial_deposit.
@export var has_any_progress: bool = false

# --- ChanceCondition ---
@export_range(0.0, 100.0, 0.1, "suffix:%") var chance_percentage: float = 50.0


func check(context: Variant, instance: QuestInstance = null) -> bool:
	var controller = _get_controller_safely(context)
	var result := false

	match type:
		ConditionType.BOOL:
			result = is_true

		ConditionType.CHANCE:
			result = randf() < (chance_percentage / 100.0)

		ConditionType.CHECK_ITEM:
			if is_instance_valid(controller):
				var adapter = controller.get_inventory_adapter()
				if is_instance_valid(adapter) and not item_id.is_empty():
					result = adapter.check_item(item_id, amount)

		ConditionType.CHECK_QUEST_STATUS:
			if is_instance_valid(controller):
				var dm = controller.get_quest_data_manager()
				var pm = controller.get_quest_pool_manager()
				var current_status = dm.get_quest_state(quest_id)
				if (
					expected_status == QWEnums.QuestState.CUSTOM
					and not expected_custom_pool_id.is_empty()
				):
					result = pm.get_quests_in_pool(expected_custom_pool_id).has(quest_id)
				else:
					result = current_status == expected_status

		ConditionType.CHECK_VARIABLE:
			var actual_value = null
			if instance and instance.variables.has(variable_name):
				actual_value = instance.get_variable(variable_name)
			elif context is RefCounted and context.get("game_state"):
				if is_instance_valid(context.game_state):
					actual_value = context.game_state.get_variable(variable_name)
			var expected_value = QWConditionLogic.parse_string_to_variant(expected_value_string)
			result = QWConditionLogic.compare(actual_value, expected_value, operator)

		ConditionType.CHECK_OBJECTIVE_STATUS:
			if is_instance_valid(controller) and not objective_id.is_empty():
				result = (
					controller.get_objective_manager().get_objective_status(objective_id)
					== expected_objective_status
				)

		ConditionType.CHECK_OBJECTIVE_REQUIREMENT:
			if is_instance_valid(controller) and not objective_id.is_empty() and instance:
				var objective_def = controller.get_objective_manager().get_objective_resource(
					objective_id
				)
				if objective_def:
					var inventory_adapter = controller.get_inventory_adapter()
					if has_any_progress:
						for req_item_id in objective_def.requirements:
							var current_progress = instance.get_objective_progress_by_key(
								objective_id, req_item_id
							)
							var potential = current_progress
							if include_inventory_holdings and is_instance_valid(inventory_adapter):
								potential += inventory_adapter.count_item(req_item_id)
							if potential > 0:
								result = true
								break
					else:
						result = true
						for req_item_id in objective_def.requirements:
							var target_amount = objective_def.requirements[req_item_id]
							var current_progress = instance.get_objective_progress_by_key(
								objective_id, req_item_id
							)
							var potential = current_progress
							if include_inventory_holdings and is_instance_valid(inventory_adapter):
								potential += inventory_adapter.count_item(req_item_id)
							if potential < target_amount:
								result = false
								break

		ConditionType.CHECK_SYNCHRONIZER:
			if context is Dictionary and context.has("sync_inputs_received_array"):
				var received_array: Array = context["sync_inputs_received_array"]
				match check_type:
					CheckType.RECEIVED_N_INPUTS:
						result = received_array.count(true) >= sync_value
					CheckType.RECEIVED_SPECIFIC_INPUT:
						result = (
							sync_value >= 0
							and sync_value < received_array.size()
							and received_array[sync_value]
						)
					_:
						result = false
			else:
				result = false

		ConditionType.COMPOUND:
			if sub_conditions.is_empty():
				result = logic_operator == LogicOperator.AND
			else:
				match logic_operator:
					LogicOperator.AND:
						result = true
						for condition in sub_conditions:
							if (
								not is_instance_valid(condition)
								or not condition.check(context, instance)
							):
								result = false
								break
					LogicOperator.OR:
						result = false
						for condition in sub_conditions:
							if is_instance_valid(condition) and condition.check(context, instance):
								result = true
								break
					_:
						result = false
		_:
			push_error("ConditionResource: Unhandled ConditionType %s" % type)
			result = false

	return result


func _get_controller_safely(context: Variant) -> Node:
	if context is RefCounted and context.get("quest_controller"):
		return context.quest_controller

	var main_loop = Engine.get_main_loop()
	if main_loop and main_loop.root:
		var services = main_loop.root.get_node_or_null("QuestWeaverServices")
		if is_instance_valid(services) and services.quest_controller:
			return services.quest_controller

	return null


func to_dictionary() -> Dictionary:
	var sub_conditions_data = []
	for sub_cond in sub_conditions:
		if is_instance_valid(sub_cond):
			sub_conditions_data.append(sub_cond.to_dictionary())

	return {
		"@script_path": get_script().resource_path,
		"type": self.type,
		"is_true": self.is_true,
		"chance_percentage": self.chance_percentage,
		"item_id": self.item_id,
		"amount": self.amount,
		"quest_id": self.quest_id,
		"expected_status": self.expected_status,
		"expected_custom_pool_id": self.expected_custom_pool_id,
		"variable_name": self.variable_name,
		"expected_value_string": self.expected_value_string,
		"operator": self.operator,
		"check_type": self.check_type,
		"sync_value": self.sync_value,
		"logic_operator": self.logic_operator,
		"objective_id": self.objective_id,
		"expected_objective_status": self.expected_objective_status,
		"include_inventory_holdings": self.include_inventory_holdings,
		"has_any_progress": self.has_any_progress,
		"sub_conditions": sub_conditions_data,
	}


func from_dictionary(data: Dictionary) -> void:
	self.type = _defensive_load(data, "type", ConditionType.keys(), ConditionType.BOOL)
	self.is_true = data.get("is_true", true)
	self.chance_percentage = data.get("chance_percentage", 50.0)
	self.item_id = StringName(data.get("item_id", &""))
	self.amount = data.get("amount", 1)
	self.quest_id = StringName(data.get("quest_id", &""))
	# Updated defensive load for global keys
	self.expected_status = _defensive_load(
		data, "expected_status", QWEnums.QuestState.keys(), QWEnums.QuestState.COMPLETED
	)
	self.expected_custom_pool_id = StringName(data.get("expected_custom_pool_id", &""))
	self.variable_name = StringName(data.get("variable_name", &""))
	self.expected_value_string = data.get("expected_value_string", "")
	self.operator = _defensive_load(data, "operator", Operator.keys(), Operator.EQUALS)
	self.check_type = _defensive_load(
		data, "check_type", CheckType.keys(), CheckType.RECEIVED_N_INPUTS
	)
	self.sync_value = data.get("sync_value", 1)
	self.objective_id = StringName(data.get("objective_id", &""))
	self.expected_objective_status = _defensive_load(
		data,
		"expected_objective_status",
		ObjectiveResource.Status.keys(),
		ObjectiveResource.Status.COMPLETED
	)
	self.logic_operator = _defensive_load(
		data, "logic_operator", LogicOperator.keys(), LogicOperator.AND
	)
	self.include_inventory_holdings = data.get("include_inventory_holdings", false)
	self.has_any_progress = data.get("has_any_progress", false)

	self.sub_conditions.clear()
	var sub_conditions_data = data.get("sub_conditions", [])
	for sub_cond_dict in sub_conditions_data:
		var script_path = sub_cond_dict.get("@script_path")
		if script_path:
			var new_sub_cond = GraphNodeResource.new_condition_from_path(script_path)
			if is_instance_valid(new_sub_cond):
				new_sub_cond.from_dictionary(sub_cond_dict)
				self.sub_conditions.append(new_sub_cond)


func _defensive_load(data: Dictionary, prop: String, keys: Array, default_val: int) -> int:
	var val = data.get(prop, default_val)
	if val is int and val >= 0 and val < keys.size():
		return val
	return default_val
