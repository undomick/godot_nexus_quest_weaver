class_name NodeExecutor
extends RefCounted


# Base class for all Executors.
# V1.0 Update: Accepts 'instance' to read/write runtime state.
func execute(context: ExecutionContext, node: GraphNodeResource, _instance: QuestInstance) -> void:
	# Default behavior: Just mark complete
	context.quest_controller.complete_node(node)
