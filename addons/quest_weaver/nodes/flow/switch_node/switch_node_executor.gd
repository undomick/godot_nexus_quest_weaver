## Uses QuestController internals (_node_connections, _node_definitions, _activate_node) by design.
## Variable-based branching requires direct connection lookup.
class_name SwitchNodeExecutor
extends NodeExecutor


func execute(context: ExecutionContext, node: GraphNodeResource, instance: QuestInstance) -> void:
	var switch_node = node as SwitchNodeResource
	if not is_instance_valid(switch_node):
		context.quest_controller.complete_node(node)
		return

	var controller = context.quest_controller
	var actual_value = _get_variable_value(context, instance, switch_node.variable_name)

	var port_index: int = switch_node.cases.size()
	for i in range(switch_node.cases.size()):
		var c: SwitchCasePort = switch_node.cases[i]
		if not is_instance_valid(c):
			continue
		var expected = QWConditionLogic.parse_string_to_variant(c.value_string)
		if actual_value == expected or _values_equal(actual_value, expected):
			port_index = i
			break

	var connections = controller._node_connections.get(switch_node.id, [])
	for connection in connections:
		if connection.from_port == port_index:
			var next_def = controller._node_definitions.get(connection.to_node)
			if next_def:
				controller._activate_node(next_def, connection.to_port)
			break

	controller._mark_node_as_logically_complete(switch_node)


func _get_variable_value(
	context: ExecutionContext, instance: QuestInstance, var_name: StringName
) -> Variant:
	if instance and instance.variables.has(var_name):
		return instance.get_variable(var_name)
	if is_instance_valid(context.game_state) and context.game_state.variables.has(var_name):
		return context.game_state.get_variable(var_name)
	return null


func _values_equal(a: Variant, b: Variant) -> bool:
	if a == null and b == null:
		return true
	if a == null or b == null:
		return false
	if typeof(a) != typeof(b):
		if (a is int or a is float) and (b is int or b is float):
			return float(a) == float(b)
		return false
	return a == b
