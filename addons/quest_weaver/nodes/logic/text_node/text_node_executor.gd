# res://addons/quest_weaver/nodes/logic/text_node/text_node_executor.gd
class_name TextNodeExecutor
extends NodeExecutor


func execute(context: ExecutionContext, node: GraphNodeResource, instance: QuestInstance) -> void:
	var text_node = node as TextNodeResource
	if not is_instance_valid(text_node):
		context.quest_controller.complete_node(node)
		return

	# Resolve Placeholders (Context is null here, so only Global/Instance vars work)
	var final_text = instance.resolve_text(text_node.text_content)

	match text_node.target_property:
		TextNodeResource.TextTarget.ADD_TO_QUEST_LOG:
			context.quest_controller.get_quest_data_manager().add_quest_log_entry(
				text_node.id, final_text
			)
		TextNodeResource.TextTarget.SET_QUEST_DESCRIPTION:
			context.quest_controller.get_quest_data_manager().set_quest_description(
				text_node.id, final_text
			)

	context.quest_controller.complete_node(node)
