# res://addons/quest_weaver/core/quest_controller.gd
class_name QuestController
extends Node

# --- SIGNALS ---
signal quest_became_available(quest_id: StringName)
signal quest_started(quest_id: StringName)
signal quest_completed(quest_id: StringName)
signal quest_failed(quest_id: StringName)
signal quest_data_changed(quest_id: StringName)

# --- MANAGER INSTANCES ---
var _timer_manager: QuestTimerManager
var _sync_manager: QuestSyncManager
var _event_manager: QuestEventManager
var _scope_manager: QuestScopeManager
var _persistence_manager: QuestStatePersistenceManager
var _execution_context: ExecutionContext
var _inventory_adapter: QuestInventoryAdapterBase = null
var _kill_adapter: QuestKillAdapterBase = null
var _presentation_manager: PresentationManager
var _logger: QWLogger

# === STATE MANAGEMENT (v1.0) ===

# Holds the runtime data objects (QuestInstance). 
# Key: File ID (String) | Value: QuestInstance
var _active_instances: Dictionary = {}

# === STATIC DEFINITIONS (BLUEPRINTS) ===

# Maps file paths to a list of Node IDs contained within.
# Key: String (Path) | Value: Array[StringName] (Node IDs)
var _quest_node_map: Dictionary = {} 

# Maps Node ID (StringName) -> GraphNodeResource
var _node_definitions: Dictionary = {} 

# Maps Node ID (StringName) -> Array of Connection Dictionaries.
var _node_connections: Dictionary = {} 

# Maps Logical Quest ID (StringName) -> QuestContextNodeResource.
var _id_to_context_node_map: Dictionary = {} 

# Maps Node ID (StringName) -> File ID (StringName). 
var _node_to_file_id_map: Dictionary = {} 

# Cache for Auto-Loading (Logical ID (StringName) -> File Path (String))
var _registry_map: Dictionary = {}

# Startup Queue to handle API calls made before _ready is finished
var _is_initialized: bool = false
var _startup_queue: Array[Callable] = []

# Flag to prevent double cleanup
var _is_shutting_down: bool = false

var _call_stack: Array[Dictionary] = []
var _node_registry: NodeTypeRegistry


# --- INITIALIZATION & LIFECYCLE ---

func _get_services() -> Node:
	var main_loop = Engine.get_main_loop()
	if main_loop and main_loop.root:
		return main_loop.root.get_node_or_null("QuestWeaverServices")
	return null

func _get_logger() -> QWLogger:
	if is_instance_valid(_logger): return _logger
	var services = _get_services()
	if is_instance_valid(services): return services.logger
	return null

func _ready() -> void:	
	var global_bus = get_tree().root.get_node_or_null("QuestWeaverGlobal")
	if is_instance_valid(global_bus):
		global_bus.register_controller(self)
	
	var services = _get_services()
	if services:
		services.register_quest_controller(self)
	
	_initialize_dependencies_and_start()
	_send_debug_message("session_started")

func _on_exit_cleanup() -> void:
	_send_debug_message("session_ended")
	
	if is_instance_valid(_timer_manager): _timer_manager.clear_all_timers()
	if is_instance_valid(_sync_manager): _sync_manager.clear()
	if is_instance_valid(_event_manager): _event_manager.clear()
	if is_instance_valid(_scope_manager): _scope_manager.clear()

	_timer_manager = null
	_sync_manager = null
	_event_manager = null
	_scope_manager = null
	_persistence_manager = null
	_execution_context = null 
	_node_registry = null
	_inventory_adapter = null
	_kill_adapter = null
	_presentation_manager = null
	_logger = null
	
	_active_instances.clear()
	_node_definitions.clear()
	_node_connections.clear()
	_quest_node_map.clear()
	_id_to_context_node_map.clear()
	_node_to_file_id_map.clear()
	
	QWConstants.clear_static_references()

func _initialize_dependencies_and_start() -> void:
	_initialize_managers()
	_register_executors()
	_initialize_inventory_adapter()
	_initialize_kill_adapter()
	_initialize_quest_graphs()
	_scope_manager.initialize_scope_definitions(_node_definitions, _node_connections)
	_connect_global_signals()
	
	var services = _get_services()
	if services and not services.has_game_state():
		print("[QuestController] Waiting for GameState registration...")
		await services.game_state_ready
	
	start_all_loaded_graphs()
	
	# --- PROCESS QUEUE ---
	_is_initialized = true
	if not _startup_queue.is_empty():
		if _logger: _logger.log("System", "Processing %d queued startup commands..." % _startup_queue.size())
		for command in _startup_queue:
			command.call()
		_startup_queue.clear()

func _initialize_managers():
	_persistence_manager = QuestStatePersistenceManager.new()
	_timer_manager = QuestTimerManager.new(self)
	_sync_manager = QuestSyncManager.new(self)
	_event_manager = QuestEventManager.new(self)
	_scope_manager = QuestScopeManager.new(self)
	
	_logger = QWLogger.new()
	_logger.initialize()
	
	var services = _get_services()
	if services:
		services.register_logger(_logger)
		_presentation_manager = PresentationManager.new()
		_presentation_manager.name = "PresentationManager"
		add_child(_presentation_manager)
		services.register_presentation_manager(_presentation_manager)

func _register_executors():
	_node_registry = NodeTypeRegistry.new()
	if not is_instance_valid(_node_registry):
		push_error("QuestController: Could not load NodeTypeRegistry!")

func _initialize_quest_graphs() -> void:
	var logger = _logger
	if not is_instance_valid(logger): return

	logger.log("Flow", "Initializing quest graphs...")
	_load_registry_cache()
	_load_auto_start_graphs()

	if not Engine.is_editor_hint():
		logger.log("Flow", "Skipping editor session data load in exported build.")
		return 

	var settings = QWConstants.get_settings()
	if not is_instance_valid(settings): return

	var paths_to_load: Array[String] = []
	var editor_data_path = settings.editor_data_path
	
	if editor_data_path and ResourceLoader.exists(editor_data_path):
		var editor_data: QuestEditorData = ResourceLoader.load(editor_data_path, "QuestEditorData", ResourceLoader.CACHE_MODE_REPLACE)
		if is_instance_valid(editor_data):
			for path in editor_data.open_files:
				if path is String and not path.is_empty():
					paths_to_load.append(path)
	
	for graph_path in paths_to_load:
		if FileAccess.file_exists(graph_path):
			var graph_res = ResourceLoader.load(graph_path, "QuestGraphResource")
			if is_instance_valid(graph_res):
				graph_res.resource_path = graph_path 
				_load_graph_data(graph_res)

	logger.log("Flow", "Initialization complete.")

func _initialize_inventory_adapter():
	var logger = _logger
	var adapter_path = QWConstants.get_settings().inventory_adapter_script
	
	if adapter_path and not adapter_path.is_empty() and ResourceLoader.exists(adapter_path):
		var adapter_script = load(adapter_path)
		if is_instance_valid(adapter_script):
			_inventory_adapter = adapter_script.new()
			_inventory_adapter.initialize()
			_inventory_adapter.inventory_updated.connect(_check_item_collect_objectives)
			if is_instance_valid(logger):
				logger.log("Inventory", "Inventory Adapter initialized and connected successfully.")
		else:
			if is_instance_valid(logger):
				logger.error("Inventory", "The assigned adapter script could not be instantiated.")
	elif is_instance_valid(logger):
		logger.warn("Inventory", "No Inventory Adapter configured. Item-related quests will not function.")

func _initialize_kill_adapter():
	var logger = _logger
	var adapter_path = QWConstants.get_settings().kill_adapter_script
	if adapter_path and not adapter_path.is_empty() and ResourceLoader.exists(adapter_path):
		var adapter_script = load(adapter_path)
		if is_instance_valid(adapter_script):
			_kill_adapter = adapter_script.new()
			_kill_adapter.initialize()
			_kill_adapter.kills_updated.connect(_check_kill_objectives)
			if is_instance_valid(logger):
				logger.log("Flow", "Kill Adapter initialized and connected successfully.")
		elif is_instance_valid(logger):
			logger.error("Flow", "The assigned kill adapter script could not be instantiated.")
	elif is_instance_valid(logger):
		logger.warn("Flow", "No Kill Adapter configured. KILL objectives use event-based tracking.")

func _connect_global_signals() -> void:
	var event_bus = get_tree().root.get_node_or_null("QuestWeaverGlobal")
	if not is_instance_valid(event_bus):
		push_warning("[QuestController] QuestWeaverGlobal Singleton could not be found.")
		return

	if not event_bus.quest_event_fired.is_connected(_event_manager.on_global_event):
		event_bus.quest_event_fired.connect(_event_manager.on_global_event)
	if not event_bus.interacted_with_object.is_connected(_on_interacted_with_object):
		event_bus.interacted_with_object.connect(_on_interacted_with_object)
	if not event_bus.enemy_was_killed.is_connected(_on_enemy_was_killed):
		event_bus.enemy_was_killed.connect(_on_enemy_was_killed)
	if not event_bus.entered_location.is_connected(_on_entered_location):
		event_bus.entered_location.connect(_on_entered_location)

# --- PUBLIC API ---

func set_quest_available(query_id: StringName) -> void:
	if query_id == &"": return
	
	# Ensure loaded logic (similar to start_quest_id)
	if not _ensure_quest_loaded(query_id):
		if _logger: _logger.warn("Flow", "set_quest_available: Could not load '%s'." % query_id)
		return

	var file_id = _resolve_instance_file_id(query_id)
	var instance = _active_instances.get(file_id)
	
	# Create if missing
	if not instance:
		instance = QuestInstance.new(file_id)
		_active_instances[file_id] = instance
		# Apply logical ID from map if possible
		var ctx = _id_to_context_node_map.get(query_id)
		if ctx: instance.quest_id = ctx.quest_id

	# Only change if currently UNAVAILABLE. 
	if instance.current_status == QWEnums.QuestState.UNAVAILABLE:
		instance.current_status = QWEnums.QuestState.AVAILABLE
		
		var signal_id = instance.quest_id if instance.quest_id != &"" else instance.file_id
		quest_became_available.emit(signal_id)
		quest_data_changed.emit(signal_id)
		
		if _logger: _logger.log("Flow", "Quest '%s' marked as AVAILABLE." % signal_id)

## Getter for Quest Boards
func get_available_quests() -> Array[StringName]:
	var list: Array[StringName] = []
	for instance: QuestInstance in _active_instances.values():
		if instance.current_status == QWEnums.QuestState.AVAILABLE:
			var q_id = instance.quest_id if instance.quest_id != &"" else instance.file_id
			list.append(q_id)
	return list

## Main entry point to activate a quest logic flow.
## Sets status to ACTIVE, registers Logical ID, and emits signals.
func start_quest(context_node: QuestContextNodeResource) -> void:
	var logger = _logger
	
	# 1. Resolve File ID
	var file_id = _node_to_file_id_map.get(context_node.id, &"")
	if file_id == &"":
		if logger: logger.error("Flow", "ContextNode '%s' is not mapped to a file instance." % context_node.id)
		return
		
	# 2. Get or Create Instance
	var instance = _active_instances.get(file_id)
	if not instance:
		instance = QuestInstance.new(file_id)
		_active_instances[file_id] = instance
	
	# 3. Register Logical ID (from Context)
	if not context_node.quest_id.is_empty():
		instance.quest_id = context_node.quest_id

	# 4. Activate Logic (Only if not already running)
	if instance.current_status < QWEnums.QuestState.ACTIVE:
		instance.current_status = QWEnums.QuestState.ACTIVE
		
		if not context_node.log_on_start.is_empty():
			var resolved_log = instance.resolve_text(context_node.log_on_start, null)
			instance.set_variable("_logs", [resolved_log])
		
		if logger: 
			logger.log("Flow", "Quest '%s' (File: %s) set to ACTIVE. LogicID: %s" % [context_node.quest_title, file_id, instance.quest_id])
		
		var signal_id = instance.quest_id if not instance.quest_id.is_empty() else file_id
		quest_started.emit(signal_id)
		quest_data_changed.emit(signal_id)

## Starts a quest using its Logical ID. Auto-loads if registered.
func start_quest_id(quest_id: StringName) -> void:
	if not _is_initialized:
		_startup_queue.append(func(): start_quest_id(quest_id))
		return
	
	if not _ensure_quest_loaded(quest_id):
		if _logger: _logger.warn("Flow", "start_quest_id: Could not find or load quest '%s'." % quest_id)
		return
		
	var context_node = _id_to_context_node_map.get(quest_id)
	if context_node:
		start_quest(context_node) # Internal activation
		_activate_node(context_node)
	else:
		if _logger: _logger.error("Flow", "Loaded graph for '%s' but ContextNode is missing in map." % quest_id)

## Starts a quest using its File ID (filename).
func start_quest_file(file_id: StringName) -> void:
	if not _is_initialized:
		_startup_queue.append(func(): start_quest_file(file_id))
		return
	
	# 1. Check if already loaded/active
	var resolved_id = _resolve_instance_file_id(file_id)
	if _active_instances.has(resolved_id):
		var instance = _active_instances[resolved_id]
		if instance.current_status == QWEnums.QuestState.UNAVAILABLE:
			_start_specific_graph_entry(resolved_id)
		return
			
	# 2. Check Registry (Direct Lookup via FileID key if it matches LogicalID by chance)
	if _registry_map.has(file_id):
		start_sub_graph(_registry_map[file_id])
		return
	
	# 3. Fallback: Search in Registry Values (Paths) to find filename match
	# Note: This loop compares strings
	var file_id_str = String(file_id)
	for path in _registry_map.values():
		if path.get_file().get_basename() == file_id_str:
			start_sub_graph(path)
			return
			
	if _logger: _logger.warn("Flow", "start_quest_file: '%s' not found." % file_id)

## Restarts a quest by Logical ID.
func restart_quest_id(quest_id: StringName) -> void:
	if not _is_initialized:
		_startup_queue.append(func(): restart_quest_id(quest_id))
		return

	var file_id = _resolve_instance_file_id(quest_id)
	
	if file_id == quest_id and not _active_instances.has(file_id):
		start_quest_id(quest_id) # Fallback start
		return
		
	_restart_quest_internal(file_id)

## Restarts a quest by File ID.
func restart_quest_file(file_id: StringName) -> void:
	if not _is_initialized:
		_startup_queue.append(func(): restart_quest_file(file_id))
		return
	_restart_quest_internal(file_id)

## Starts a quest with parameters.
func start_quest_with_parameters(quest_id: StringName, params: Dictionary) -> void:
	if not _is_initialized:
		_startup_queue.append(func(): start_quest_with_parameters(quest_id, params))
		return

	# Ensure loaded (fallback: file_id logic may still work)
	if not _ensure_quest_loaded(quest_id) and _logger:
		_logger.warn("Flow", "start_quest_with_parameters: Could not load '%s'. Attempting file_id fallback." % quest_id)

	var file_id = _resolve_instance_file_id(quest_id)
	
	if not _active_instances.has(file_id):
		var instance = QuestInstance.new(file_id)
		instance.current_status = QWEnums.QuestState.UNAVAILABLE
		_active_instances[file_id] = instance

	var instance: QuestInstance = _active_instances[file_id]
	for key in params:
		instance.set_variable(key, params[key])
	
	if _logger: _logger.log("Flow", "Injected params into '%s': %s" % [file_id, params])

	var context_node = _id_to_context_node_map.get(quest_id)
	if not context_node: context_node = _id_to_context_node_map.get(file_id)
	
	if context_node:
		start_quest(context_node)
		_activate_node(context_node)
	else:
		_start_specific_graph_entry(file_id)

func complete_quest_id(quest_id: StringName, success: bool = true) -> void:
	var action = QuestNodeResource.QuestAction.COMPLETE if success else QuestNodeResource.QuestAction.FAIL
	set_quest_status(quest_id, action)

func complete_quest_file(file_id: StringName, success: bool = true) -> void:
	var action = QuestNodeResource.QuestAction.COMPLETE if success else QuestNodeResource.QuestAction.FAIL
	set_quest_status(file_id, action)

## Returns the rewards summary for a quest: item_id -> total amount.
## Sums all rewards with the same item_id. Rewards with linked_objective_id are only
## included if that objective is COMPLETED in the current instance; main rewards (no link) are always included.
## Lazy-loads the quest from registry if not yet loaded (enables reward_amount for non-started quests).
func get_quest_rewards(query_id: StringName) -> Dictionary:
	if not _id_to_context_node_map.has(query_id):
		_ensure_quest_loaded(query_id)
	var context_node = _id_to_context_node_map.get(query_id)
	if not context_node:
		var file_id = _resolve_instance_file_id(query_id)
		context_node = _id_to_context_node_map.get(file_id)
	var file_id = _resolve_instance_file_id(query_id)
	var instance = _active_instances.get(file_id)
	if not context_node:
		return {}
	var result = {}
	for r in context_node.rewards:
		if not r is Dictionary:
			continue
		var r_id = r.get("id", &"unknown")
		var r_amount = int(r.get("amount", 0))
		if r_id == &"":
			continue
		var linked_obj_id: StringName = r.get("linked_objective_id", &"")
		if linked_obj_id != &"":
			if not is_instance_valid(instance) or instance.get_objective_status(linked_obj_id) != ObjectiveResource.Status.COMPLETED:
				continue
		result[r_id] = result.get(r_id, 0) + r_amount
	return result

## Debug/Cheat Tool: Forces the quest flow to jump to a specific node.
## Stops all currently active nodes in this quest before jumping.
func jump_to_node(node_id: StringName) -> void:
	var file_id = _get_file_id_for_node(node_id)
	var instance = _active_instances.get(file_id)
	var logger = _get_logger()
	
	if not instance:
		if logger: logger.warn("Flow", "Jump failed: No instance found for node '%s'." % node_id)
		return
		
	if logger: logger.log("Flow", ">>> FORCE JUMP to node '%s' in quest '%s'" % [node_id, file_id])
	
	# 1. Stop ALL currently active nodes in this instance
	# (Simulate that we left the previous state)
	for active_id in instance.active_node_ids.duplicate():
		_cleanup_node_runtime(active_id, instance)
	instance.active_node_ids.clear()
	
	# 2. Ensure Quest is Active (if we jump into a inactive quest)
	if instance.current_status != QWEnums.QuestState.ACTIVE:
		instance.current_status = QWEnums.QuestState.ACTIVE
		quest_started.emit(instance.quest_id if not instance.quest_id.is_empty() else file_id)
	
	# 3. Activate Target
	var node_def = _node_definitions.get(node_id)
	if node_def:
		_activate_node(node_def)

func set_quest_status(query_id: StringName, action: QuestNodeResource.QuestAction) -> void:
	var logger = _logger
	if query_id == &"": return
	
	# START Action: Logic is different (Activation)
	if action == QuestNodeResource.QuestAction.START:
		start_quest_id(query_id)
		return

	# Resolve Instance ID (File ID) from Query ID
	var file_id = _resolve_instance_file_id(query_id)

	if not _active_instances.has(file_id):
		if logger: logger.warn("Flow", "Cannot change status of inactive/unknown quest '%s'." % query_id)
		return

	var instance: QuestInstance = _active_instances[file_id]
	var target_status = QWEnums.QuestState.ACTIVE
	
	match action:
		QuestNodeResource.QuestAction.COMPLETE: target_status = QWEnums.QuestState.COMPLETED
		QuestNodeResource.QuestAction.FAIL: target_status = QWEnums.QuestState.FAILED
	
	if instance.current_status != target_status:
		instance.current_status = target_status
		
		if logger: logger.log("Flow", "Quest '%s' status changed to %d." % [query_id, target_status])
		
		# Prefer logic ID for signals
		var signal_id = instance.quest_id if not instance.quest_id.is_empty() else file_id
		
		if target_status == QWEnums.QuestState.COMPLETED:
			quest_completed.emit(signal_id)
		elif target_status == QWEnums.QuestState.FAILED:
			quest_failed.emit(signal_id)

func get_quest_state(query_id: StringName) -> int:
	var file_id = _resolve_instance_file_id(query_id)
	if _active_instances.has(file_id):
		return _active_instances[file_id].current_status
	return QWEnums.QuestState.UNAVAILABLE

func get_quest_data(query_id: StringName) -> Dictionary:
	var result = {}
	
	# 1. Static Data (Title/Description)
	var context_node = _id_to_context_node_map.get(query_id)
	if context_node:
		result["title"] = context_node.quest_title
		result["description"] = context_node.quest_description
		result["quest_type"] = context_node.quest_type
		#result["rewards"] = context_node.rewards_summary
		result["rewards"] = {} 
	
	# 2. Dynamic Data (Status, Logs)
	var file_id = _resolve_instance_file_id(query_id)
	if _active_instances.has(file_id):
		var instance: QuestInstance = _active_instances[file_id]
		result["id"] = query_id # Keep the requested ID
		result["status"] = instance.current_status
		result["log_entries"] = instance.get_variable("_logs", [])
		# Resolve placeholders in title/description (e.g. {objective('id').item(0).name})
		if context_node:
			result["title"] = instance.resolve_text(context_node.quest_title, null)
			var base_desc = context_node.quest_description
			var runtime_desc = instance.get_variable("_description_override", "")
			if not runtime_desc.is_empty():
				result["description"] = runtime_desc
			else:
				result["description"] = instance.resolve_text(base_desc, null)
	else:
		result["id"] = query_id
		result["status"] = QWEnums.QuestState.UNAVAILABLE
		result["log_entries"] = []
	
	return result

func get_all_managed_quests_data() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	var processed_nodes: Dictionary = {} # Deduplication Cache
	
	for q_id in _id_to_context_node_map:
		var context_node = _id_to_context_node_map[q_id]
		
		if processed_nodes.has(context_node):
			continue
		
		processed_nodes[context_node] = true
		
		var primary_id = q_id
		if not context_node.quest_id.is_empty():
			primary_id = context_node.quest_id
			
		list.append(get_quest_data(primary_id))
		
	return list

func get_active_objectives_for_quest(query_id: StringName) -> Array[ObjectiveResource]:
	var objectives: Array[ObjectiveResource] = []
	var file_id = _resolve_instance_file_id(query_id)
	
	if not _active_instances.has(file_id): return objectives
	
	var instance: QuestInstance = _active_instances[file_id]
	
	# Scan active nodes in this instance
	for node_id in instance.active_node_ids:
		var node_def = _node_definitions.get(node_id)
		if node_def is TaskNodeResource:
			# Inject state into temporary objective copies for UI
			for bp_obj in node_def.objectives:
				var obj_status = instance.get_objective_status(bp_obj.id)
				var obj_progress = instance.get_objective_progress(bp_obj.id)
				
				if obj_status == ObjectiveResource.Status.ACTIVE:
					var ui_obj = bp_obj.duplicate()
					ui_obj.current_progress = obj_progress
					ui_obj.status = obj_status
					
					# Resolve Description Override
					ui_obj.description = instance.get_objective_description(bp_obj.id, bp_obj.description)
					
					objectives.append(ui_obj)
					
	return objectives

func get_objective_status(p_objective_id: StringName) -> int:
	if p_objective_id.is_empty(): return ObjectiveResource.Status.INACTIVE
	
	# Search all active instances
	for instance in _active_instances.values():
		var status = instance.get_objective_status(p_objective_id)
		if status != ObjectiveResource.Status.INACTIVE:
			return status
	return ObjectiveResource.Status.INACTIVE

func set_manual_objective_status(objective_id: StringName, new_status: int):
	for instance in _active_instances.values():
		if instance.objective_states.has(objective_id):
			instance.set_objective_status(objective_id, new_status)
			
			var signal_id = instance.quest_id if not instance.quest_id.is_empty() else instance.file_id
			
			# Granular Signal
			var global_bus = get_tree().root.get_node_or_null("QuestWeaverGlobal")
			if global_bus:
				global_bus.quest_objective_state_changed.emit(signal_id, objective_id, new_status)
			
			# Legacy Signal
			quest_data_changed.emit(signal_id)
			
			_check_tasks_in_instance(instance)
			return

func set_quest_description(node_id: StringName, description: String) -> void:
	var file_id = _get_file_id_for_node(node_id)
	if not file_id.is_empty() and _active_instances.has(file_id):
		var instance = _active_instances[file_id]
		instance.set_variable("_description_override", description)
		
		var signal_id = instance.quest_id if not instance.quest_id.is_empty() else file_id
		quest_data_changed.emit(signal_id)

## Convenience: Set description by quest_id, file_id, or node_id.
func set_quest_description_by_quest_id(quest_id: StringName, description: String) -> void:
	var ctx = _id_to_context_node_map.get(quest_id)
	if not ctx:
		var file_id = _resolve_instance_file_id(quest_id)
		ctx = _id_to_context_node_map.get(file_id)
	if not ctx:
		var node_def = _node_definitions.get(quest_id)
		if node_def is QuestContextNodeResource:
			ctx = node_def
	if ctx:
		set_quest_description(ctx.id, description)
	else:
		# Fallback: id might be a node_id (e.g. from TextNode)
		var file_id = _get_file_id_for_node(quest_id)
		if not file_id.is_empty():
			set_quest_description(quest_id, description)

func add_quest_log_entry(node_id: StringName, log_text: String) -> void:
	var file_id = _get_file_id_for_node(node_id)
	if not file_id.is_empty() and _active_instances.has(file_id):
		var instance = _active_instances[file_id]
		var logs: Array = instance.get_variable("_logs", [])
		logs.append(log_text)
		instance.set_variable("_logs", logs)
		
		var signal_id = instance.quest_id if not instance.quest_id.is_empty() else file_id
		quest_data_changed.emit(signal_id)

func force_skip_node(node_id: StringName) -> void:
	var file_id = _get_file_id_for_node(node_id)
	var instance = _active_instances.get(file_id)
	
	if not instance or not instance.is_node_active(node_id): return
	
	var node_def = _node_definitions.get(node_id)
	if not node_def: return

	var logger = _get_logger()
	if logger: logger.log("System", "Force skipping node: %s" % node_id)

	# Cleanup specific blocking behaviors
	if node_def is ShowUIMessageNodeResource:
		if is_instance_valid(_presentation_manager):
			_presentation_manager.force_close_current()
	elif node_def is PlayCutsceneNodeResource:
		var root = get_tree().get_root()
		var anim_player = root.get_node_or_null(node_def.animation_player_path)
		if is_instance_valid(anim_player) and anim_player.is_playing():
			anim_player.seek(anim_player.current_animation_length, true)
			anim_player.stop()

	var global_bus = get_tree().root.get_node_or_null("QuestWeaverGlobal")
	if is_instance_valid(global_bus):
		global_bus.unlock_interaction(node_id)

	complete_node(node_def)

func reset_all_graphs_and_quests():
	var logger = _logger
	if is_instance_valid(logger):
		logger.log("Flow", "Resetting all graphs and quest states.")
	
	_active_instances.clear()
	_timer_manager.clear_all_timers()
	_sync_manager.clear()
	_event_manager.clear()
	_scope_manager.clear()

func start_all_loaded_graphs():
	_ensure_execution_context_exists()
	
	var settings = QWConstants.get_settings()
	if settings and not settings.auto_start_quests.is_empty():
		for raw_path in settings.auto_start_quests:
			if raw_path.is_empty(): continue
			
			var final_path = raw_path
			if raw_path.begins_with("uid://"):
				var id = ResourceLoader.get_resource_uid(raw_path)
				if id != -1: final_path = ResourceUID.get_id_path(id)
			
			if is_instance_valid(_logger):
				_logger.log("System", "Auto-starting: " + final_path)
			_start_specific_graph_entry(final_path)

func start_sub_graph(graph_path: String) -> void:
	if ResourceLoader.exists(graph_path):
		var graph_res = ResourceLoader.load(graph_path)
		_load_graph_data(graph_res)
	else:
		if _logger: _logger.error("System", "Could not load sub-graph resource at '%s'." % graph_path)
		return
	
	var file_id = graph_path.get_file().get_basename()
	
	# Create Instance if missing, initially UNAVAILABLE
	if not _active_instances.has(file_id):
		var instance = QuestInstance.new(file_id)
		instance.current_status = QWEnums.QuestState.UNAVAILABLE
		_active_instances[file_id] = instance
		
		if is_instance_valid(_logger):
			_logger.log("Flow", "Sub-Graph: Created instance '%s' (Status: INACTIVE)." % file_id)
	
	var nodes_in_graph = _quest_node_map.get(graph_path, [])
	
	# Try StartNode
	for node_id in nodes_in_graph:
		var node = _node_definitions.get(node_id)
		if node is StartNodeResource:
			_activate_node(node)
			return
	
	# Fallback: QuestContextNode
	for node_id in nodes_in_graph:
		var node = _node_definitions.get(node_id)
		if node is QuestContextNodeResource:
			if _logger: _logger.warn("Flow", "Sub-graph '%s' has no StartNode. Starting at QuestContextNode." % graph_path)
			_activate_node(node)
			return
			
	if _logger: _logger.error("Flow", "Sub-graph at '%s' has no entry point." % graph_path)

func push_to_call_stack(parent_node_id: StringName):
	var parent_graph_path = _get_quest_path_for_node(parent_node_id)
	if parent_graph_path.is_empty(): return
		
	var child_path = ""
	var node = _node_definitions.get(parent_node_id)
	if node and node is SubGraphNodeResource:
		child_path = node.quest_graph_path
		if child_path.begins_with("uid://"):
			var uid = ResourceLoader.get_resource_uid(child_path)
			if uid != -1: child_path = ResourceUID.get_id_path(uid)
	
	_call_stack.append({
		"parent_node_id": parent_node_id,
		"parent_quest_path": parent_graph_path,
		"child_graph_path": child_path
	})

func pop_from_call_stack():
	if _call_stack.is_empty(): return
	
	var return_info = _call_stack.pop_back()
	var parent_node_id = StringName(return_info.get("parent_node_id"))
	var child_graph_path = return_info.get("child_graph_path")
	
	if child_graph_path:
		_cleanup_graph_instances(child_graph_path)
	
	if is_instance_valid(_logger):
		_logger.log("Flow", "Sub-Graph finished. Returning to parent node '%s'." % parent_node_id)
	
	var parent_def = _node_definitions.get(parent_node_id)
	if parent_def:
		complete_node(parent_def)

func jump_to_anchor(origin_node: GraphNodeResource, anchor_name: String) -> void:
	var current_graph_path = _get_quest_path_for_node(origin_node.id)
	if current_graph_path.is_empty(): return

	var node_ids_in_graph = _quest_node_map.get(current_graph_path, [])
	var target_anchor: AnchorNodeResource = null
	
	for id in node_ids_in_graph:
		var def = _node_definitions.get(id)
		if def is AnchorNodeResource and def.anchor_name == anchor_name:
			target_anchor = def
			break
	
	if target_anchor:
		if is_instance_valid(_logger):
			_logger.log("Flow", "  -> JUMPING to Anchor '%s'." % anchor_name)
		_activate_node(target_anchor)
	else:
		if is_instance_valid(_logger):
			_logger.warn("Flow", "JumpNode '%s' could not find Anchor '%s'." % [origin_node.id, anchor_name])

## Retrieves a runtime variable from a specific quest instance.
## Returns the default value if the quest is not active or the variable doesn't exist.
func get_quest_variable(query_id: StringName, key: StringName, default: Variant = null) -> Variant:
	var file_id = _resolve_instance_file_id(query_id)
	
	if _active_instances.has(file_id):
		var instance: QuestInstance = _active_instances[file_id]
		return instance.get_variable(key, default)
		
	return default

## Returns the current numeric progress of an objective (e.g. 3 out of 5 items).
## Returns 0 if the objective is inactive or not found.
func get_objective_progress(objective_id: StringName) -> int:
	if objective_id == &"": return 0
	
	# Search in active instances
	for instance: QuestInstance in _active_instances.values():
		# Only check if the objective is actually tracked in this instance
		if instance.objective_states.has(objective_id):
			return instance.get_objective_progress(objective_id)
			
	return 0

## Returns progress for a specific target key of an objective (e.g. amount of "wood" collected).
## Returns 0 if the objective is inactive, not found, or the key has no progress.
func get_objective_progress_by_key(objective_id: StringName, target_key: StringName) -> int:
	if objective_id == &"": return 0
	
	for instance: QuestInstance in _active_instances.values():
		if instance.objective_states.has(objective_id):
			return instance.get_objective_progress_by_key(objective_id, target_key)
	return 0

# --- ADAPTER ACCESS (for Executors via ExecutionContext) ---

func get_inventory_adapter() -> QuestInventoryAdapterBase:
	return _inventory_adapter

func get_kill_adapter() -> QuestKillAdapterBase:
	return _kill_adapter

# --- SAVE / LOAD ---

func get_save_data() -> Dictionary:
	return _persistence_manager.save_state(self)

func load_from_data(data: Dictionary):
	_persistence_manager.load_state(self, data)

# --- CORE LOGIC ---

func _activate_node(node_definition: GraphNodeResource, from_input_port: int = 0) -> void:
	var logger = _logger
	if not is_instance_valid(node_definition): return

	var file_id = _node_to_file_id_map.get(node_definition.id, "")
	var instance: QuestInstance = _active_instances.get(file_id)
	
	if not instance and not (node_definition is QuestContextNodeResource):
		if logger: logger.warn("Flow", "Node '%s' activated but no Quest Instance found." % node_definition.id)
		return

	if logger: logger.log("Flow", "-> Activating Node: '%s' (Blueprint) in Instance '%s'" % [node_definition.id, file_id])
	
	_send_debug_message("node_activated", [node_definition.id]) 
	
	if instance:
		# RE-ENTRY CHECK
		if instance.is_node_active(node_definition.id):
			if logger: logger.log("Flow", "   - Node already active. Resetting previous execution state (Re-Entry).")
			_cleanup_node_runtime(node_definition.id, instance)
		
		instance.set_node_active(node_definition.id, true)
		instance.set_node_data(node_definition.id, "_entry_port", from_input_port)
	
	var executor: NodeExecutor = _node_registry.get_executor_for_node(node_definition)
	if executor:
		executor.execute(_execution_context, node_definition, instance)
	else:
		complete_node(node_definition)

func complete_node(node_definition: GraphNodeResource) -> void:
	var logger = _logger
	var file_id = _node_to_file_id_map.get(node_definition.id, &"")
	var instance: QuestInstance = _active_instances.get(file_id)
	
	if logger: logger.log("Flow", "<- Completing Node: '%s'" % node_definition.id)
	
	_send_debug_message("node_completed", [node_definition.id]) 
	
	if instance:
		instance.set_node_active(node_definition.id, false)
	
	if node_definition is EndNodeResource:
		var current_graph_path = _get_quest_path_for_node(node_definition.id)
		_cleanup_graph_instances(current_graph_path)
		
		if not _call_stack.is_empty():
			var top = _call_stack.back()
			if top.child_graph_path == current_graph_path:
				pop_from_call_stack()
				return

	_trigger_next_nodes_from_port(node_definition, 0)

func _mark_node_as_logically_complete(node_definition: GraphNodeResource) -> void:
	_send_debug_message("node_completed", [node_definition.id])
	var file_id = _node_to_file_id_map.get(node_definition.id, &"")
	var instance: QuestInstance = _active_instances.get(file_id)
	if instance:
		instance.set_node_active(node_definition.id, false)

func get_quest_id_for_node(node_id: StringName) -> StringName:
	return _get_file_id_for_node(node_id) 

func _get_file_id_for_node(node_id: StringName) -> StringName:
	return _node_to_file_id_map.get(node_id, "")

func _on_objective_in_node_changed(_new_status: int, node: TaskNodeResource, objective: ObjectiveResource):
	var file_id = _get_file_id_for_node(node.id)
	var instance = _active_instances.get(file_id)
	
	if instance:
		var signal_id = instance.quest_id if not instance.quest_id.is_empty() else instance.file_id
		quest_data_changed.emit(signal_id)
	
		var all_complete = true
		for obj in node.objectives:
			if instance.get_objective_status(obj.id) != ObjectiveResource.Status.COMPLETED:
				all_complete = false
				break
		
		if all_complete:
			complete_node(node)

func _check_tasks_in_instance(instance: QuestInstance):
	for node_id in instance.active_node_ids:
		var node_def = _node_definitions.get(node_id)
		if node_def is TaskNodeResource:
			var all_complete = true
			for obj in node_def.objectives:
				if instance.get_objective_status(obj.id) != ObjectiveResource.Status.COMPLETED:
					all_complete = false
					break
			if all_complete:
				complete_node(node_def)

# --- INTERNAL HELPERS ---

func _load_registry_cache() -> void:
	var settings = QWConstants.get_settings()
	if not is_instance_valid(settings) or settings.quest_registry_path.is_empty():
		return
		
	if ResourceLoader.exists(settings.quest_registry_path):
		var registry = ResourceLoader.load(settings.quest_registry_path)
		if registry and "quest_path_map" in registry:
			# Convert Keys to StringName
			_registry_map.clear()
			for k in registry.quest_path_map:
				_registry_map[StringName(k)] = registry.quest_path_map[k]
			if _logger: _logger.log("System", "Loaded Registry. Known Quests: %d" % _registry_map.size())

func _ensure_quest_loaded(quest_id: StringName) -> bool:
	if _id_to_context_node_map.has(quest_id): return true
	
	if _registry_map.has(quest_id):
		var path = _registry_map[quest_id]
		if ResourceLoader.exists(path):
			if _logger: _logger.log("System", "Auto-Loading quest '%s' from '%s'" % [quest_id, path])
			var res = ResourceLoader.load(path)
			_load_graph_data(res)
			return true
	return false

func _are_all_requirements_met(instance: QuestInstance, obj: ObjectiveResource) -> bool:
	if obj.requirements.is_empty():
		return true 
		
	for req_key in obj.requirements:
		var needed = obj.requirements[req_key]
		var have = instance.get_objective_progress_by_key(obj.id, req_key)
		if have < needed:
			return false
	return true

## Helper to find an ObjectiveResource by its ID within loaded definitions.
func get_objective_resource(obj_id: StringName) -> ObjectiveResource:
	# Search in active nodes first (Fast)
	for instance in _active_instances.values():
		for node_id in instance.active_node_ids:
			var node = _node_definitions.get(node_id)
			if node is TaskNodeResource:
				for obj in node.objectives:
					if obj.id == obj_id: return obj
					
	# Fallback: Brute force search in all loaded definitions (Slow but safe)
	for node in _node_definitions.values():
		if node is TaskNodeResource:
			for obj in node.objectives:
				if obj.id == obj_id: return obj
	return null

func _restart_quest_internal(file_id: StringName) -> void:
	if not _active_instances.has(file_id): return

	var instance: QuestInstance = _active_instances[file_id]
	if _logger: _logger.log("Flow", "Restarting Quest Instance '%s'..." % file_id)
	
	for node_id in instance.active_node_ids.duplicate():
		_cleanup_node_runtime(node_id, instance)
	
	instance.active_node_ids.clear()
	instance.node_states.clear()
	instance.objective_states.clear()
	instance.current_status = QWEnums.QuestState.UNAVAILABLE
	
	# Restart Logic
	var context_node = null
	if not instance.quest_id.is_empty():
		context_node = _id_to_context_node_map.get(instance.quest_id)
	if not context_node:
		context_node = _id_to_context_node_map.get(file_id)
		
	if context_node:
		start_quest(context_node) 
		_activate_node(context_node)
	else:
		_start_specific_graph_entry(file_id)

func _resolve_instance_file_id(query_id: StringName) -> StringName:
	# 1. Active File ID?
	if _active_instances.has(query_id): return query_id
	
	# 2. Active Logical ID?
	for inst in _active_instances.values():
		if inst.quest_id == query_id: return inst.file_id

	# 3. Static Definition? (Loaded but inactive)
	if _id_to_context_node_map.has(query_id):
		var context = _id_to_context_node_map[query_id]
		var fid = _node_to_file_id_map.get(context.id)
		if fid: return fid

	return query_id

func _cleanup_node_runtime(node_id: StringName, instance: QuestInstance) -> void:
	var node_def = _node_definitions.get(node_id)
	if not node_def: return

	if node_def is TaskNodeResource:
		var executor = _node_registry.get_executor_for_node(node_def)
		if executor and executor.has_method("cleanup_listeners"):
			executor.cleanup_listeners(_execution_context, node_def)
	elif node_def is EventListenerNodeResource:
		_event_manager.unregister_listener(node_def)
	elif node_def is TimerNodeResource:
		_timer_manager.remove_timer(node_id)
	
	instance.set_node_active(node_id, false)

func _ensure_execution_context_exists() -> void:
	if not is_instance_valid(_execution_context):
		var services = _get_services()
		var game_state_instance = null
		if services:
			game_state_instance = services.get_game_state()
		
		_execution_context = ExecutionContext.new(self, game_state_instance, _logger, services)

func _load_auto_start_graphs() -> void:
	var settings = QWConstants.get_settings()
	if not is_instance_valid(settings): return

	var paths: Array[String] = []
	for raw_path in settings.auto_start_quests:
		if not raw_path.is_empty():
			var p = raw_path
			if p.begins_with("uid://"):
				var id = ResourceLoader.get_resource_uid(p)
				if id != -1: p = ResourceUID.get_id_path(id)
			paths.append(p)
	
	for path in paths:
		if ResourceLoader.exists(path):
			var res = ResourceLoader.load(path, "QuestGraphResource")
			_load_graph_data(res)

func _load_graph_data(graph_resource: QuestGraphResource):
	var path = graph_resource.resource_path
	if _quest_node_map.has(path): return 
	
	# Create map entry with typed array
	var node_list: Array[StringName] = []
	_quest_node_map[path] = node_list
	
	var file_id = path.get_file().get_basename()
	
	# 1. Map Context Nodes (Logical ID -> Node Resource)
	for node_id in graph_resource.nodes:
		var node = graph_resource.nodes[node_id]
		if node is QuestContextNodeResource:
			var logical_id = node.quest_id
			if not logical_id.is_empty():
				_id_to_context_node_map[logical_id] = node
			
			# Fallback mapping
			if logical_id != file_id:
				_id_to_context_node_map[file_id] = node
			break
	
	# 2. Register Nodes
	for node_id in graph_resource.nodes:
		var node = graph_resource.nodes[node_id]
		if is_instance_valid(node):
			# Ensure GiveTakeItem output_ports match allow_partial_deposit (handles Godot native load)
			if node is GiveTakeItemNodeResource and node.has_method("_update_ports_from_data"):
				node._update_ports_from_data()
			_node_definitions[node_id] = node
			node_list.append(node_id)
			_node_to_file_id_map[node_id] = file_id 

	for connection in graph_resource.connections:
		var from_id = StringName(connection.get("from_node")) # Cast explicit
		if not _node_connections.has(from_id):
			_node_connections[from_id] = []
		_node_connections[from_id].append(connection)

func _start_specific_graph_entry(graph_path: String) -> void:
	if not _quest_node_map.has(graph_path):
		if ResourceLoader.exists(graph_path):
			var res = ResourceLoader.load(graph_path)
			_load_graph_data(res)
	
	var file_id = StringName(graph_path.get_file().get_basename())
	var nodes = _quest_node_map.get(graph_path, [])
	var start_node_def: StartNodeResource = null
	
	for id in nodes:
		var node = _node_definitions.get(id)
		if node is StartNodeResource:
			start_node_def = node
			break
	
	if start_node_def:
		if not _active_instances.has(file_id):
			var instance = QuestInstance.new(file_id)
			instance.current_status = QWEnums.QuestState.ACTIVE
			_active_instances[file_id] = instance
			
			if is_instance_valid(_logger):
				_logger.log("Flow", "Auto-Start: Created implicit instance for '%s'." % file_id)
				
			quest_started.emit(file_id)
			quest_data_changed.emit(file_id)
		
		_activate_node(start_node_def)
	else:
		if is_instance_valid(_logger):
			_logger.warn("Flow", "Auto-start graph '%s' has no StartNode." % graph_path)

func _trigger_next_nodes_from_port(from_node: GraphNodeResource, from_port_index: int):
	var logger = _logger
	if logger: logger.log("Flow", "    - Triggering next nodes from '%s' port %d..." % [from_node.id, from_port_index])
	
	var connections = _node_connections.get(from_node.id, [])
	var triggered_count = 0
	for connection in connections:
		if connection.get("from_port") == from_port_index:
			var next_node_id = connection.get("to_node")
			var to_port = connection.get("to_port", 0)
			var next_node_def = _node_definitions.get(next_node_id)
			if next_node_def:
				_activate_node(next_node_def, to_port)
				triggered_count += 1
	# Only Success (port 0) must be connected for non-terminal nodes; Partial/Failure are optional
	if logger and triggered_count == 0 and from_node is GiveTakeItemNodeResource and from_port_index == 0:
		logger.warn("Flow", "    - No connections from '%s' Success port. Connect the Success output." % from_node.id)

func _process_sync_node_batch(node_id: StringName, instance: QuestInstance) -> void:
	if is_instance_valid(_sync_manager):
		_sync_manager.process_pending(node_id, instance)

func _cleanup_graph_instances(graph_path: String) -> void:
	var file_id_to_cleanup = graph_path.get_file().get_basename()
	
	if _active_instances.has(file_id_to_cleanup):
		var instance = _active_instances[file_id_to_cleanup]
		
		for node_id in instance.active_node_ids:
			_cleanup_node_runtime(node_id, instance)
		
		instance.active_node_ids.clear()
		
		var keep_in_memory = not instance.quest_id.is_empty() or \
							 instance.current_status != QWEnums.QuestState.UNAVAILABLE
		
		if keep_in_memory:
			if is_instance_valid(_logger):
				_logger.log("System", "Graph finished but Instance '%s' kept in memory (Status: %d)." % [file_id_to_cleanup, instance.current_status])
		else:
			_active_instances.erase(file_id_to_cleanup)
			if is_instance_valid(_logger):
				_logger.log("System", "Graph finished and Instance '%s' garbage collected." % file_id_to_cleanup)

func _get_quest_path_for_node(node_id: StringName) -> String:
	for path in _quest_node_map:
		if _quest_node_map[path].has(node_id):
			return path
	return ""

func _on_interacted_with_object(interacted_node: Node):
	if not is_instance_valid(_execution_context): return
	var path = str(interacted_node.get_path())
	
	if _execution_context.interact_objective_listeners.has(path):
		var global_bus = get_tree().root.get_node_or_null("QuestWeaverGlobal")
		var wrappers = _execution_context.interact_objective_listeners[path]
		for w in wrappers:
			var obj: ObjectiveResource = w.objective
			var instance: QuestInstance = _active_instances.get(w.quest_id)
			if not instance: instance = _active_instances.get(w.file_id)

			if instance:
				instance.set_objective_status(obj.id, ObjectiveResource.Status.COMPLETED)
				
				# Granular State Signal
				if global_bus:
					var sig_id = instance.quest_id if not instance.quest_id.is_empty() else instance.file_id
					global_bus.quest_objective_state_changed.emit(sig_id, obj.id, ObjectiveResource.Status.COMPLETED)
				
				_check_tasks_in_instance(instance)

func _on_enemy_was_killed(enemy_id: StringName):
	if not is_instance_valid(_execution_context): return
	if is_instance_valid(_kill_adapter): return  # Adapter handles progress via _check_kill_objectives
	
	# Key lookup with StringName cast
	if _execution_context.kill_objective_listeners.has(String(enemy_id)):
		var wrappers = _execution_context.kill_objective_listeners[String(enemy_id)]
		var global_bus = get_tree().root.get_node_or_null("QuestWeaverGlobal")
		
		for w in wrappers:
			var obj: ObjectiveResource = w.objective
			var instance = _active_instances.get(w.file_id)
			var target_key = w.get("target_key", enemy_id) 
			
			if instance:
				var current = instance.get_objective_progress_by_key(obj.id, target_key)
				var progress_amount = current + 1
				if obj.track_progress_since_activation:
					var snapshot_key = StringName("start_amount_%s_%s" % [obj.id, target_key])
					var start_amount = instance.get_node_data(w.task_node_id, snapshot_key, 0)
					progress_amount = max(0, (current + 1) - start_amount)
				progress_amount = min(progress_amount, obj.requirements.get(target_key, 1))
				instance.set_objective_progress_by_key(obj.id, target_key, progress_amount)
				
				var signal_id = instance.quest_id if instance.quest_id != &"" else instance.file_id
				var required_for_this = obj.requirements.get(target_key, 1)
				
				if global_bus:
					global_bus.quest_objective_progress_changed.emit(signal_id, obj.id, progress_amount, required_for_this)
				quest_data_changed.emit(signal_id)
				
				# CHECK IF ALL REQUIREMENTS MET
				if _are_all_requirements_met(instance, obj):
					instance.set_objective_status(obj.id, ObjectiveResource.Status.COMPLETED)
					if global_bus:
						global_bus.quest_objective_state_changed.emit(signal_id, obj.id, ObjectiveResource.Status.COMPLETED)
					_check_tasks_in_instance(instance)

func _on_entered_location(location_id: String):
	if not is_instance_valid(_execution_context): return
	
	if _execution_context.location_objective_listeners.has(location_id):
		var global_bus = get_tree().root.get_node_or_null("QuestWeaverGlobal")
		var wrappers = _execution_context.location_objective_listeners[location_id]
		
		for w in wrappers:
			var obj: ObjectiveResource = w.objective
			var instance = _active_instances.get(w.file_id)
			
			if instance:
				instance.set_objective_status(obj.id, ObjectiveResource.Status.COMPLETED)
				
				var signal_id = instance.quest_id if not instance.quest_id.is_empty() else instance.file_id
				
				if global_bus:
					global_bus.quest_objective_state_changed.emit(signal_id, obj.id, ObjectiveResource.Status.COMPLETED)
				
				_check_tasks_in_instance(instance)

func _check_item_collect_objectives():
	if not is_instance_valid(_execution_context) or not is_instance_valid(_inventory_adapter): return
	var global_bus = get_tree().root.get_node_or_null("QuestWeaverGlobal")
	
	# Iterate all tracked items
	var item_ids_str = _execution_context.item_objective_listeners.keys()
	
	for item_id_str in item_ids_str:
		var item_id = StringName(item_id_str)
		var current_inv_amount = _inventory_adapter.count_item(item_id_str)
		var wrappers = _execution_context.item_objective_listeners[item_id_str]
		
		for w in wrappers:
			var obj: ObjectiveResource = w.objective
			if obj.complete_on_delivery:
				continue  # Progress only from GiveTakeItem; no auto-complete from inventory
			var instance = _active_instances.get(_resolve_instance_file_id(w.file_id)) # Resolve safely
			if not instance: continue
			
			# Snapshot Logic per Item
			var snapshot_key = StringName("start_amount_%s_%s" % [obj.id, item_id])
			var start_amount = instance.get_node_data(w.task_node_id, snapshot_key, 0)
			
			# Calculate Quest Progress (Delta)
			var progress_amount = current_inv_amount
			if obj.track_progress_since_activation:
				progress_amount = max(0, current_inv_amount - start_amount)
			
			# Get Target
			var required = obj.requirements.get(item_id, 1)
			
			# Clamp to required
			progress_amount = min(progress_amount, required)
			
			# Update Instance State
			var stored_progress = instance.get_objective_progress_by_key(obj.id, item_id)
			
			if stored_progress != progress_amount:
				instance.set_objective_progress_by_key(obj.id, item_id, progress_amount)
				
				var signal_id = instance.quest_id if instance.quest_id != &"" else instance.file_id
				if global_bus:
					global_bus.quest_objective_progress_changed.emit(signal_id, obj.id, progress_amount, required)
				quest_data_changed.emit(signal_id)
				
			# Check Completion
			if _are_all_requirements_met(instance, obj):
				if instance.get_objective_status(obj.id) != ObjectiveResource.Status.COMPLETED:
					instance.set_objective_status(obj.id, ObjectiveResource.Status.COMPLETED)
					var sig_id = instance.quest_id if instance.quest_id != &"" else instance.file_id
					if global_bus:
						global_bus.quest_objective_state_changed.emit(sig_id, obj.id, ObjectiveResource.Status.COMPLETED)
					quest_data_changed.emit(sig_id)
					_check_tasks_in_instance(instance)

func _check_kill_objectives():
	if not is_instance_valid(_execution_context) or not is_instance_valid(_kill_adapter): return
	var global_bus = get_tree().root.get_node_or_null("QuestWeaverGlobal")
	var enemy_ids_str = _execution_context.kill_objective_listeners.keys()
	for enemy_id_str in enemy_ids_str:
		var enemy_id = StringName(enemy_id_str)
		var current_count = _kill_adapter.count_kill(enemy_id_str)
		var wrappers = _execution_context.kill_objective_listeners[enemy_id_str]
		for w in wrappers:
			var obj: ObjectiveResource = w.objective
			var instance = _active_instances.get(_resolve_instance_file_id(w.file_id))
			if not instance: continue
			var snapshot_key = StringName("start_amount_%s_%s" % [obj.id, enemy_id])
			var start_amount = instance.get_node_data(w.task_node_id, snapshot_key, 0)
			var progress_amount = current_count
			if obj.track_progress_since_activation:
				progress_amount = max(0, current_count - start_amount)
			var required = obj.requirements.get(enemy_id, 1)
			progress_amount = min(progress_amount, required)
			var stored_progress = instance.get_objective_progress_by_key(obj.id, enemy_id)
			if stored_progress != progress_amount:
				instance.set_objective_progress_by_key(obj.id, enemy_id, progress_amount)
				var signal_id = instance.quest_id if instance.quest_id != &"" else instance.file_id
				if global_bus:
					global_bus.quest_objective_progress_changed.emit(signal_id, obj.id, progress_amount, required)
				quest_data_changed.emit(signal_id)
			if _are_all_requirements_met(instance, obj):
				if instance.get_objective_status(obj.id) != ObjectiveResource.Status.COMPLETED:
					instance.set_objective_status(obj.id, ObjectiveResource.Status.COMPLETED)
					var sig_id = instance.quest_id if instance.quest_id != &"" else instance.file_id
					if global_bus:
						global_bus.quest_objective_state_changed.emit(sig_id, obj.id, ObjectiveResource.Status.COMPLETED)
					quest_data_changed.emit(sig_id)
					_check_tasks_in_instance(instance)

func _send_debug_message(message: String, data: Array = []) -> void:
	if not OS.is_debug_build(): return
	if not EngineDebugger.is_active(): return
	EngineDebugger.send_message("quest_weaver:%s" % message, data)

# --- SHUTDOWN LOGIC ---

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if not _is_shutting_down:
			shutdown()
	elif what == NOTIFICATION_EXIT_TREE:
		if not _is_shutting_down:
			_on_exit_cleanup()

func shutdown() -> void:
	_send_debug_message("session_ended")
	
	if is_instance_valid(_timer_manager): _timer_manager.clear_all_timers()
	if is_instance_valid(_execution_context):
		_execution_context.cleanup()
		_execution_context = null
	_active_instances.clear()
	_node_definitions.clear()
	QWConstants.clear_static_references()

# --- DEBUG API (Developer Tools) ---

## Prints the full internal state of a quest instance to the console (JSON formatted).
func debug_dump_quest_state(query_id: StringName) -> void:
	var file_id = _resolve_instance_file_id(query_id)
	if not _active_instances.has(file_id):
		print("[QW Debug] Quest '%s' not found or inactive." % query_id)
		return

	var instance: QuestInstance = _active_instances[file_id]
	var data = instance.get_save_data()
	print(JSON.stringify(data, "\t"))

## Instantly completes all objectives of currently ACTIVE task nodes in a quest.
func debug_complete_active_tasks(query_id: StringName) -> void:
	var file_id = _resolve_instance_file_id(query_id)
	if not _active_instances.has(file_id): return

	var instance: QuestInstance = _active_instances[file_id]
	var modified = false

	# Iterate over a copy of active nodes
	for node_id in instance.active_node_ids.keys():
		var node_def = _node_definitions.get(node_id)
		
		if node_def is TaskNodeResource:
			for objective in node_def.objectives:
				if instance.get_objective_status(objective.id) != ObjectiveResource.Status.COMPLETED:
					instance.set_objective_status(objective.id, ObjectiveResource.Status.COMPLETED)
					print("[QW Debug] Force completed objective '%s' in quest '%s'" % [objective.id, query_id])
					modified = true
	
	if modified:
		var signal_id = instance.quest_id if not instance.quest_id.is_empty() else instance.file_id
		quest_data_changed.emit(signal_id)
		_check_tasks_in_instance(instance)

## Sets a quest variable directly (bypassing normal logic flow).
func debug_set_variable(query_id: StringName, key: StringName, value: Variant) -> void:
	var file_id = _resolve_instance_file_id(query_id)
	if _active_instances.has(file_id):
		var instance = _active_instances[file_id]
		instance.set_variable(key, value)
		print("[QW Debug] Set variable '%s' = %s in quest '%s'" % [key, value, query_id])
