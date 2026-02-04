# res://addons/quest_weaver/systems/managers/quest_state_persistence_manager.gd
class_name QuestStatePersistenceManager
extends RefCounted

const SAVE_VERSION = "1.0"

func save_state(controller: QuestController) -> Dictionary:
	var instances_data: Array[Dictionary] = []
	for instance: QuestInstance in controller._active_instances.values():
		if is_instance_valid(instance):
			instances_data.append(instance.get_save_data())
	
	return {
		"version": SAVE_VERSION,
		"instances": instances_data
	}

func load_state(controller: QuestController, data: Dictionary) -> void:
	var logger = controller._get_logger()
	if logger: logger.log("SaveLoad", "Loading quest state...")

	controller.reset_all_graphs_and_quests()
	
	var instances_data = data.get("instances", [])
	if not instances_data is Array: return

	for inst_data in instances_data:
		var instance = QuestInstance.new(&"") 
		instance.load_save_data(inst_data)
		
		# Validation 1: Check if the Quest File still exists
		if not controller._id_to_context_node_map.has(instance.file_id) and not controller._node_to_file_id_map.values().has(instance.file_id):
			if logger: logger.warn("SaveLoad", "Loaded quest '%s' but no definition found. Skipping." % instance.file_id)
			continue
		
		# Validation 2: Check if the Nodes inside still exist (Update protection)
		_sanitize_instance_data(controller, instance)
		
		controller._active_instances[instance.file_id] = instance

	# Restore Runtime Hooks
	if is_instance_valid(controller._timer_manager):
		controller._timer_manager.restore_timers_from_instances(controller._active_instances)
		
	_restore_event_listeners(controller)
	
	# Notify UI
	for file_id in controller._active_instances:
		var inst = controller._active_instances[file_id]
		var signal_id = inst.quest_id if inst.quest_id != &"" else inst.file_id
		controller.quest_data_changed.emit(signal_id)

	if logger: logger.log("SaveLoad", "Load complete. %d quests restored." % controller._active_instances.size())

func _restore_event_listeners(controller: QuestController) -> void:
	var event_manager = controller._event_manager
	if not is_instance_valid(event_manager): return
	
	event_manager.clear()
	
	for instance: QuestInstance in controller._active_instances.values():
		for node_id in instance.active_node_ids:
			# Safety check: if node does not exist in definition, skip
			var node_def = controller._node_definitions.get(node_id)
			if not node_def: continue
			
			if node_def is EventListenerNodeResource:
				event_manager.register_listener(node_def)
			elif node_def is TaskNodeResource:
				if is_instance_valid(controller._execution_context):
					TaskNodeExecutor.register_listeners(controller._execution_context, node_def, instance)

# Removes stale nodes from save data to prevent crashes
func _sanitize_instance_data(controller: QuestController, instance: QuestInstance) -> void:
	var nodes_to_remove: Array[StringName] = []
	var logger = controller._get_logger()
	
	# 1. Check Active Nodes
	for node_id in instance.active_node_ids.keys():
		if not controller._node_definitions.has(node_id):
			nodes_to_remove.append(node_id)
	
	for invalid_id in nodes_to_remove:
		instance.active_node_ids.erase(invalid_id)
		if logger:
			logger.warn("SaveLoad", "Sanitized savegame: Node '%s' in quest '%s' no longer exists. Removed from active state." % [invalid_id, instance.file_id])

	# 2. Check Node States
	nodes_to_remove.clear()
	for node_id in instance.node_states.keys():
		if not controller._node_definitions.has(node_id):
			nodes_to_remove.append(node_id)
			
	for invalid_id in nodes_to_remove:
		instance.node_states.erase(invalid_id)
