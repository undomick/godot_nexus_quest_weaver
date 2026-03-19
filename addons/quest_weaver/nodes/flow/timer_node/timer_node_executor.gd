## Uses QuestController internals (_timer_manager) by design.
## Non-blocking timer requires manager coordination; these APIs are not exposed publicly.
class_name TimerNodeExecutor
extends NodeExecutor


func execute(context: ExecutionContext, node: GraphNodeResource, instance: QuestInstance) -> void:
	var timer_node = node as TimerNodeResource
	var controller = context.quest_controller
	var logger = context.logger

	if not is_instance_valid(timer_node) or not is_instance_valid(logger):
		return

	logger.log(
		"Flow",
		(
			"TimerNode '%s': Starting %d second timer in instance '%s'."
			% [timer_node.id, timer_node.duration, instance.quest_id]
		)
	)

	# The Manager will handle the instance state updates.
	# We assume TimerManager.start_timer signature will be updated in next step.
	controller._timer_manager.start_timer(timer_node, instance)
