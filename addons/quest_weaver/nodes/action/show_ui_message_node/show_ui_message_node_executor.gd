# res://addons/quest_weaver/nodes/action/show_ui_message_node/show_ui_message_node_executor.gd
class_name ShowUIMessageNodeExecutor
extends NodeExecutor


func execute(context: ExecutionContext, node: GraphNodeResource, instance: QuestInstance) -> void:
	var msg_node = node as ShowUIMessageNodeResource
	if not is_instance_valid(msg_node):
		return

	var controller = context.quest_controller
	var logger = context.logger

	# --- 1. Suppression Check ---
	var global_bus = context.services.get_tree().root.get_node_or_null("QuestWeaverGlobal")
	if is_instance_valid(global_bus) and global_bus.are_notifications_suppressed:
		if is_instance_valid(logger):
			logger.log("Flow", "Suppressed UI Message '%s' due to global setting." % msg_node.id)
		# Skip logic and complete immediately
		controller.complete_node(msg_node)
		return

	# --- 2. Resolve Text Placeholders ---
	# This enables "Kill {amount} Rats" to become "Kill 5 Rats" using instance variables.
	var final_title = instance.resolve_text(msg_node.title_override)
	var final_message = instance.resolve_text(msg_node.message_override)

	if is_instance_valid(logger):
		logger.log("Executor", "ShowUIMessage: '%s' - '%s'" % [final_title, final_message])

	var presentation_manager = null
	if is_instance_valid(context.services):
		presentation_manager = context.services.presentation_manager

	if not is_instance_valid(presentation_manager):
		push_warning("ShowUIMessageNodeExecutor: PresentationManager not found via Services.")
		controller.complete_node(msg_node)
		return

	# --- 3. Global Lock (If Blocking) ---
	if msg_node.wait_for_completion:
		if is_instance_valid(global_bus):
			global_bus.lock_interaction(msg_node.id)

	# --- 4. Queue Presentation ---
	var presentation_data = {
		"_node_id": msg_node.id,  # Token for signal matching
		"type": msg_node.message_type,
		"title": final_title,
		"message": final_message,
		"anim_in": msg_node.animation_in,
		"ease_in": msg_node.ease_in,
		"per_character_in": msg_node.per_character_in,
		"anim_out": msg_node.animation_out,
		"ease_out": msg_node.ease_out,
		"per_character_out": msg_node.per_character_out,
		"duration_in": msg_node.duration_in,
		"duration_out": msg_node.duration_out,
		"delay_title_message": msg_node.delay_title_message,
		"hold_duration": msg_node.hold_duration,
		"character_stagger_ms": msg_node.character_stagger_ms
	}

	presentation_manager.queue_presentation(presentation_data)

	# --- 5. Wait or Continue ---
	if msg_node.wait_for_completion:
		# Calculate a safety timeout to prevent infinite loops (Expected duration + 5s buffer)
		var expected_duration = (
			msg_node.duration_in + msg_node.hold_duration + msg_node.duration_out
		)
		var timeout_ms = (expected_duration + 5.0) * 1000.0
		var start_time = Time.get_ticks_msec()

		# Wait loop: Only proceed if the signal returns THIS node's ID.
		while true:
			# Safety: Break if manager was destroyed (e.g. scene change)
			if not is_instance_valid(presentation_manager):
				if is_instance_valid(logger):
					logger.warn("Executor", "PresentationManager lost during wait. Aborting wait.")
				break

			# Safety: Break if timeout exceeded
			if (Time.get_ticks_msec() - start_time) > timeout_ms:
				if is_instance_valid(logger):
					logger.warn(
						"Executor", "ShowUIMessage timed out (Signal lost?). Force continuing."
					)
				break

			var finished_id = await presentation_manager.presentation_completed

			if finished_id == msg_node.id:
				break

		# Unlock global input
		if is_instance_valid(global_bus):
			global_bus.unlock_interaction(msg_node.id)

		# Check if node is still active in the instance (it might have been skipped or reset externally)
		if instance.is_node_active(msg_node.id):
			controller.complete_node(msg_node)
	else:
		# Fire and forget
		controller.complete_node(msg_node)
