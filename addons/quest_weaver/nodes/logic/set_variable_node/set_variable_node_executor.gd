# res://addons/quest_weaver/nodes/logic/set_variable_node/set_variable_node_executor.gd
class_name SetVariableNodeExecutor
extends NodeExecutor


## Applies the configured operator to the GameState variable. Supports SET, ADD, SUBTRACT, MULTIPLY, DIVIDE, TOGGLE.
## Value supports $variable references. Always completes the current node.
func execute(context: ExecutionContext, node: GraphNodeResource, instance: QuestInstance) -> void:
	var var_node = node as SetVariableNodeResource
	if not is_instance_valid(var_node):
		push_error("SetVariableNodeExecutor expects a SetVariableNodeResource.")
		context.quest_controller.complete_node(node)
		return

	var game_state = context.game_state
	var logger = context.logger

	if var_node.variable_name.is_empty() or not is_instance_valid(game_state):
		if is_instance_valid(logger):
			logger.warn(
				"Executor", "SetVariableNode: variable_name is empty or GameState not found."
			)
		context.quest_controller.complete_node(var_node)
		return

	# Parse value (supports numbers, bools, and $variables from Instance/Global)
	var value_to_apply = _get_value_from_string(var_node.value_to_set_string, game_state, instance)

	# Only check for 'null' if the operator actually requires a value (Toggle does not).
	if var_node.operator != var_node.Operator.TOGGLE and value_to_apply == null:
		push_error(
			(
				"SetVariableNode '%s': Could not resolve value for '%s'."
				% [var_node.id, var_node.value_to_set_string]
			)
		)
		context.quest_controller.complete_node(var_node)
		return

	if is_instance_valid(logger):
		var op_name = var_node.Operator.keys()[var_node.operator]
		logger.log(
			"Executor",
			"SetVariableNode: '%s' %s %s" % [var_node.variable_name, op_name, str(value_to_apply)]
		)

	match var_node.operator:
		var_node.Operator.SET:
			game_state.set_variable(var_node.variable_name, value_to_apply)

		var_node.Operator.ADD:
			var current = game_state.get_variable(var_node.variable_name, 0)
			if _is_number(current) and _is_number(value_to_apply):
				game_state.set_variable(var_node.variable_name, current + value_to_apply)

		var_node.Operator.SUBTRACT:
			var current = game_state.get_variable(var_node.variable_name, 0)
			if _is_number(current) and _is_number(value_to_apply):
				game_state.set_variable(var_node.variable_name, current - value_to_apply)

		var_node.Operator.MULTIPLY:
			var current = game_state.get_variable(var_node.variable_name, 1)
			if _is_number(current) and _is_number(value_to_apply):
				game_state.set_variable(var_node.variable_name, current * value_to_apply)

		var_node.Operator.DIVIDE:
			var current = game_state.get_variable(var_node.variable_name, 1)
			if value_to_apply == 0:
				push_error("SetVariableNode '%s': Attempted division by zero!" % var_node.id)
			elif _is_number(current) and _is_number(value_to_apply):
				game_state.set_variable(var_node.variable_name, current / float(value_to_apply))

		var_node.Operator.TOGGLE:
			var current = game_state.get_variable(var_node.variable_name, false)
			if current is bool:
				game_state.set_variable(var_node.variable_name, not current)
			else:
				if is_instance_valid(logger):
					logger.warn(
						"Executor", "SetVariableNode: TOGGLE operator expects a boolean variable."
					)

	context.quest_controller.complete_node(var_node)


func _get_value_from_string(text: String, game_state, instance: QuestInstance) -> Variant:
	# 1. Dynamic Variable Reference
	if text.begins_with("$"):
		var var_name = text.trim_prefix("$")

		# Priority 1: Local Instance Variable (Blueprint Parameters)
		if instance.variables.has(var_name):
			return instance.get_variable(var_name)

		# Priority 2: Global GameState Variable
		if game_state.has_variable(var_name):
			return game_state.get_variable(var_name)

		return null

	# 2. Static Value Parsing
	if text.is_valid_int():
		return text.to_int()
	if text.is_valid_float():
		return text.to_float()
	if text.to_lower() == "true":
		return true
	if text.to_lower() == "false":
		return false

	# Default: String
	return text


func _is_number(v: Variant) -> bool:
	return v is float or v is int
