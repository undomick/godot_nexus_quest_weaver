## Cutscene flow requires custom port routing (On Start / On Finish); this API is not exposed publicly.
class_name PlayCutsceneNodeExecutor

extends NodeExecutor

# res://addons/quest_weaver/nodes/action/play_cutscene_node/play_cutscene_node_executor.gd
## Uses QuestController internals (_trigger_next_nodes_from_port) by design.


func execute(context: ExecutionContext, node: GraphNodeResource, instance: QuestInstance) -> void:
	var cutscene_node = node as PlayCutsceneNodeResource
	if not is_instance_valid(cutscene_node):
		return

	var controller = context.quest_controller
	var logger = context.logger
	var root = controller.get_tree().get_root()

	if not root:
		controller._trigger_next_nodes_from_port(cutscene_node, 1)
		controller.complete_node(cutscene_node)
		return

	var anim_player: AnimationPlayer = root.get_node_or_null(cutscene_node.animation_player_path)

	if not is_instance_valid(anim_player):
		push_error(
			(
				"PlayCutsceneNode '%s': AnimationPlayer at path '%s' not found."
				% [cutscene_node.id, cutscene_node.animation_player_path]
			)
		)
		controller._trigger_next_nodes_from_port(cutscene_node, 1)
		controller.complete_node(cutscene_node)
		return

	if not anim_player.has_animation(cutscene_node.animation_name):
		push_error(
			(
				"PlayCutsceneNode '%s': Animation '%s' not found."
				% [cutscene_node.id, cutscene_node.animation_name]
			)
		)
		controller._trigger_next_nodes_from_port(cutscene_node, 1)
		controller.complete_node(cutscene_node)
		return

	# --- GLOBAL LOCK START ---
	if cutscene_node.wait_for_completion:
		var global_bus = controller.get_tree().root.get_node_or_null("QuestWeaverGlobal")
		if is_instance_valid(global_bus):
			global_bus.lock_interaction(cutscene_node.id)
	# -------------------------

	if is_instance_valid(logger):
		logger.log("Executor", "PlayCutscene: Playing '%s'" % cutscene_node.animation_name)

	# Fire "On Start"
	controller._trigger_next_nodes_from_port(cutscene_node, 0)
	anim_player.play(cutscene_node.animation_name)

	if cutscene_node.wait_for_completion:
		await anim_player.animation_finished

		# --- GLOBAL LOCK END ---
		var global_bus = controller.get_tree().root.get_node_or_null("QuestWeaverGlobal")
		if is_instance_valid(global_bus):
			global_bus.unlock_interaction(cutscene_node.id)

		if is_instance_valid(logger):
			logger.log("Executor", "  - Cutscene finished.")

		# Only complete if still active in instance
		if instance.is_node_active(cutscene_node.id):
			controller._trigger_next_nodes_from_port(cutscene_node, 1)  # Port 1: "On Finish"
			controller.complete_node(cutscene_node)
	else:
		# Fire and Forget logic: Hook signal safely
		var callback = func(_anim_name: StringName) -> void:
			if instance.is_node_active(cutscene_node.id):
				controller._trigger_next_nodes_from_port(cutscene_node, 1)
				controller.complete_node(cutscene_node)
		anim_player.animation_finished.connect(callback, CONNECT_ONE_SHOT)
