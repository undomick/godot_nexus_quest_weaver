# res://addons/quest_weaver/core/quest_controller.gd
class_name QuestController

extends Node

# --- SIGNALS ---
signal quest_became_available(quest_id: StringName)

signal quest_started(quest_id: StringName)

signal quest_completed(quest_id: StringName)

signal quest_failed(quest_id: StringName)

signal quest_data_changed(quest_id: StringName)

## Emitted when active objective markers (waypoints for map/minimap) may have changed.
## Connect to refresh your map UI. Use get_objective_manager().get_active_objective_markers().
signal quest_markers_changed

## Emitted when a quest is successfully accepted (started) via start_quest_id.
signal quest_accepted(quest_id: StringName)

## Emitted when the player explicitly rejects an AVAILABLE quest via reject_quest_id.
signal quest_rejected(quest_id: StringName)

# --- MANAGER INSTANCES ---
var _timer_manager: QuestTimerManager

var _sync_manager: QuestSyncManager

var _event_manager: QuestEventManager

var _scope_manager: QuestScopeManager

var _persistence_manager: QuestStatePersistenceManager

var _pool_manager: QuestPoolManager

var _objective_manager: QuestObjectiveManager

var _data_manager: QuestDataManager

var _execution_context: ExecutionContext

var _presentation_manager: PresentationManager

var _inventory_adapter: QuestInventoryAdapterBase = null

var _kill_adapter: QuestKillAdapterBase = null

var _logger: QWLogger

# Provides O(1) instance lookup via internal registry.
var _pool_registry: QuestPoolRegistry

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

# O(1) lookup: File basename (StringName) -> File Path (String). Populated in _load_registry_cache.
var _file_basename_to_path: Dictionary = {}

# O(1) lookup: Logical/File ID (StringName) -> File ID (StringName). Populated on load and instance registration.
var _logical_id_to_file_id: Dictionary = {}

# Startup Queue to handle API calls made before _ready is finished
var _is_initialized: bool = false

var _startup_queue: Array[Callable] = []

# Flag to prevent double cleanup
var _is_shutting_down: bool = false

# Cached reference to QuestWeaverGlobal event bus
var _event_bus_cache: Node = null

## True when global signals (quest_event_fired, interacted_with_object, etc.) were connected.
## When false, interaction/location/kill objectives will not trigger from the event bus.
var _event_bus_connected: bool = false

var _call_stack: Array[Dictionary] = []

var _node_registry: NodeTypeRegistry

var _debug_helper: QuestControllerDebug

## Optional acceptance conditions per quest. Key: quest_id (StringName) -> Array[Callable].
## Each Callable must return bool. All must return true for can_accept_quest to pass.
var _acceptance_conditions: Dictionary = {}

# O(1) lookup: Objective ID (StringName) -> ObjectiveResource. Built in _load_graph_data.
var _objective_id_to_resource: Dictionary = {}

# O(1) lookup: Objective ID (StringName) -> File ID (StringName). Populated when TaskNode registers listeners.
var _objective_id_to_file_id: Dictionary = {}

# O(1) lookup: Node ID (StringName) -> Quest path (String). Populated in _load_graph_data.
var _node_id_to_quest_path: Dictionary = {}

# O(1) anchor lookup: graph_path (String) -> { anchor_name (String) -> AnchorNodeResource }. Populated in _load_graph_data.
var _anchor_name_to_node: Dictionary = {}

# === STATE MANAGEMENT (v1.5 - Pool Pattern) ===

# Manages five predefined pools (UNAVAILABLE, AVAILABLE, ACTIVE, COMPLETED, FAILED).

# === STATIC DEFINITIONS (BLUEPRINTS) ===

# Maps file paths to a list of Node IDs contained within.

# --- INITIALIZATION & LIFECYCLE ---


func _get_services() -> Node:
	var main_loop = Engine.get_main_loop()
	if main_loop and main_loop.root:
		return main_loop.root.get_node_or_null("QuestWeaverServices")
	return null


func _get_logger() -> QWLogger:
	if is_instance_valid(_logger):
		return _logger
	var services = _get_services()
	if is_instance_valid(services):
		return services.logger
	return null


func _get_event_bus() -> Node:
	if is_instance_valid(_event_bus_cache):
		return _event_bus_cache
	if is_inside_tree():
		_event_bus_cache = get_tree().root.get_node_or_null("QuestWeaverGlobal")
	return _event_bus_cache


func _ready() -> void:
	quest_data_changed.connect(_emit_markers_changed)
	var global_bus = _get_event_bus()
	if is_instance_valid(global_bus):
		global_bus.register_controller(self)

	var services = _get_services()
	if services:
		services.register_quest_controller(self)

	_initialize_dependencies_and_start()
	_send_debug_message("session_started")
	if OS.is_debug_build():
		_register_performance_monitors()


func _register_performance_monitors() -> void:
	Performance.add_custom_monitor(
		"QuestWeaver/RuntimeTotal",
		func() -> float: return float(_pool_registry.get_instance_count())
	)
	Performance.add_custom_monitor(
		"QuestWeaver/StateActive",
		func() -> float:
			return float(
				_pool_registry.get_pool_for_state(QWEnums.QuestState.ACTIVE).get_instance_count()
			)
	)
	Performance.add_custom_monitor(
		"QuestWeaver/StateCompleted",
		func() -> float:
			return float(
				_pool_registry.get_pool_for_state(QWEnums.QuestState.COMPLETED).get_instance_count()
			)
	)
	Performance.add_custom_monitor(
		"QuestWeaver/StateFailed",
		func() -> float:
			return float(
				_pool_registry.get_pool_for_state(QWEnums.QuestState.FAILED).get_instance_count()
			)
	)
	Performance.add_custom_monitor(
		"QuestWeaver/StateAvailable",
		func() -> float:
			return float(
				_pool_registry.get_pool_for_state(QWEnums.QuestState.AVAILABLE).get_instance_count()
			)
	)
	Performance.add_custom_monitor(
		"QuestWeaver/StateUnavailable",
		func() -> float:
			return float(
				(
					_pool_registry
					. get_pool_for_state(QWEnums.QuestState.UNAVAILABLE)
					. get_instance_count()
				)
			)
	)


func _unregister_performance_monitors() -> void:
	for id in [
		"QuestWeaver/RuntimeTotal",
		"QuestWeaver/StateActive",
		"QuestWeaver/StateCompleted",
		"QuestWeaver/StateFailed",
		"QuestWeaver/StateAvailable",
		"QuestWeaver/StateUnavailable"
	]:
		if Performance.has_custom_monitor(id):
			Performance.remove_custom_monitor(id)


func _emit_markers_changed(_sid: StringName) -> void:
	quest_markers_changed.emit()


## Returns true if the controller is shutting down. Managers use this to avoid scheduling deferred work during cleanup.
func is_shutting_down() -> bool:
	return _is_shutting_down


## Returns true if QuestWeaverGlobal event bus was found and signals were connected.
## When false, interaction/location/kill objectives will not receive events.
func is_event_bus_connected() -> bool:
	return _event_bus_connected


## Returns the pool manager for quest status queries (get_available_quests, move_quest_to_custom_pool, etc.).
func get_quest_pool_manager() -> QuestPoolManager:
	return _pool_manager


## Returns the objective manager for objective queries and status updates.
func get_objective_manager() -> QuestObjectiveManager:
	return _objective_manager


## Returns the data manager for quest data, instance lookups, and presentation helpers.
func get_quest_data_manager() -> QuestDataManager:
	return _data_manager


## Full cleanup when exiting the tree. Clears all managers, maps, and sets references to null.
## Use this for scene/node teardown (NOTIFICATION_EXIT_TREE).
## For programmatic "soft" shutdown (e.g. WM_CLOSE_REQUEST), prefer [method shutdown] which keeps manager instances but clears runtime state.
func _on_exit_cleanup() -> void:
	_is_shutting_down = true
	if OS.is_debug_build():
		_unregister_performance_monitors()
	_send_debug_message("session_ended")

	if is_instance_valid(_timer_manager):
		_timer_manager.clear_all_timers()
	if is_instance_valid(_sync_manager):
		_sync_manager.clear()
	if is_instance_valid(_event_manager):
		_event_manager.clear()
	if is_instance_valid(_scope_manager):
		_scope_manager.clear()
	if is_instance_valid(_presentation_manager):
		_presentation_manager.force_close_current()

	if is_instance_valid(_execution_context):
		_execution_context.cleanup()

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
	_event_bus_cache = null

	if is_instance_valid(_pool_registry):
		_pool_registry.clear_all()
	_node_definitions.clear()
	_node_connections.clear()
	_quest_node_map.clear()
	_id_to_context_node_map.clear()
	_node_to_file_id_map.clear()
	_logical_id_to_file_id.clear()
	_objective_id_to_resource.clear()
	_objective_id_to_file_id.clear()
	_node_id_to_quest_path.clear()
	_registry_map.clear()
	_file_basename_to_path.clear()
	_anchor_name_to_node.clear()

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

	# --- DEBUG: Register and sync instances to editor viewer
	_send_debug_message("register", [get_instance_id()])
	for inst in _pool_registry.get_all_instances():
		_send_instance_update(inst)

	# --- PROCESS QUEUE ---
	_is_initialized = true
	if not _startup_queue.is_empty():
		var queue_copy = _startup_queue.duplicate()
		_startup_queue.clear()
		if _logger:
			_logger.log("System", "Processing %d queued startup commands..." % queue_copy.size())
		for command in queue_copy:
			command.call()


func _initialize_managers() -> void:
	_pool_registry = QuestPoolRegistry.new()
	_debug_helper = QuestControllerDebug.new(self)
	_persistence_manager = QuestStatePersistenceManager.new()
	_pool_manager = QuestPoolManager.new(self)
	_objective_manager = QuestObjectiveManager.new(self)
	_data_manager = QuestDataManager.new(self)
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


func _register_executors() -> void:
	_node_registry = NodeTypeRegistry.new()
	if not is_instance_valid(_node_registry):
		push_error("QuestController: Could not load NodeTypeRegistry!")


func _initialize_quest_graphs() -> void:
	var logger = _logger
	if not is_instance_valid(logger):
		return

	logger.log("Flow", "Initializing quest graphs...")
	_load_registry_cache()
	_load_auto_start_graphs()

	if not Engine.is_editor_hint():
		logger.log("Flow", "Skipping editor session data load in exported build.")
		return

	var settings = QWConstants.get_settings()
	if not is_instance_valid(settings):
		return

	var paths_to_load: Array[String] = []
	var editor_data_path = settings.editor_data_path

	if editor_data_path and ResourceLoader.exists(editor_data_path):
		var editor_data: QuestEditorData = ResourceLoader.load(
			editor_data_path, "QuestEditorData", ResourceLoader.CACHE_MODE_REPLACE
		)
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


func _initialize_inventory_adapter() -> void:
	var logger = _logger
	var settings = QWConstants.get_settings()
	if not is_instance_valid(settings):
		return
	var adapter_path = settings.inventory_adapter_script

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
		logger.warn(
			"Inventory", "No Inventory Adapter configured. Item-related quests will not function."
		)


func _initialize_kill_adapter() -> void:
	var logger = _logger
	var settings = QWConstants.get_settings()
	if not is_instance_valid(settings):
		return
	var adapter_path = settings.kill_adapter_script
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
	_event_bus_connected = false
	var event_bus = _get_event_bus()
	if not is_instance_valid(event_bus):
		push_warning(
			"[QuestController] QuestWeaverGlobal Singleton could not be found. Interaction/location/kill objectives will not trigger."
		)
		return

	if not event_bus.quest_event_fired.is_connected(_event_manager.on_global_event):
		event_bus.quest_event_fired.connect(_event_manager.on_global_event)
	if not event_bus.interacted_with_object.is_connected(_on_interacted_with_object):
		event_bus.interacted_with_object.connect(_on_interacted_with_object)
	if not event_bus.enemy_was_killed.is_connected(_on_enemy_was_killed):
		event_bus.enemy_was_killed.connect(_on_enemy_was_killed)
	if not event_bus.entered_location.is_connected(_on_entered_location):
		event_bus.entered_location.connect(_on_entered_location)
	_event_bus_connected = true


# --- PUBLIC API ---


## Main entry point to activate a quest logic flow.
## Sets status to ACTIVE, registers Logical ID, and emits signals.
func start_quest(context_node: QuestContextNodeResource) -> void:
	var logger = _logger

	# 1. Resolve File ID
	var file_id = _node_to_file_id_map.get(context_node.id, &"")
	if file_id.is_empty():
		if logger:
			logger.error(
				"Flow", "ContextNode '%s' is not mapped to a file instance." % context_node.id
			)
		return

	# 2. Get or Create Instance
	var instance = _get_or_create_instance(file_id, context_node.quest_id)
	# Register Logical ID if not already set
	if not context_node.quest_id.is_empty():
		instance.quest_id = context_node.quest_id
		_update_logical_id_map(instance.quest_id, file_id)

	# 4. Activate Logic (Only if not already running)
	if instance.current_status < QWEnums.QuestState.ACTIVE:
		_pool_registry.move_instance_to_pool(instance, QWEnums.QuestState.ACTIVE)

		if not context_node.log_on_start.is_empty():
			var resolved_log = instance.resolve_text(context_node.log_on_start, null)
			instance.set_variable("_logs", [resolved_log])

		if logger:
			logger.log(
				"Flow",
				(
					"Quest '%s' (File: %s) set to ACTIVE. LogicID: %s"
					% [context_node.quest_title, file_id, instance.quest_id]
				)
			)

		var signal_id = _get_signal_id_for_instance(instance)
		quest_started.emit(signal_id)
		quest_accepted.emit(signal_id)
		quest_data_changed.emit(signal_id)
		_send_instance_update(instance)


## Returns true if the quest can be accepted (AVAILABLE, not rejected, all acceptance conditions pass).
func can_accept_quest(quest_id: StringName) -> bool:
	if not _is_valid_quest_id(quest_id):
		return false
	if not _ensure_quest_loaded(quest_id):
		return false
	var file_id = _resolve_instance_file_id(quest_id)
	var instance = _pool_registry.get_instance_by_file_id(file_id)
	if not instance:
		return false
	if instance.current_status != QWEnums.QuestState.AVAILABLE:
		return false
	if instance.rejected_by_player:
		return false
	var conditions: Array = (
		_acceptance_conditions.get(quest_id, []) + _acceptance_conditions.get(file_id, [])
	)
	for cond in conditions:
		if cond is Callable and cond.is_valid() and not cond.call():
			return false
	return true


## Marks an AVAILABLE quest as rejected by the player. Emits quest_rejected. Quest stays AVAILABLE but rejected_by_player is set.
func reject_quest_id(quest_id: StringName) -> void:
	if not _is_valid_quest_id(quest_id):
		push_warning("[QuestController] reject_quest_id called with empty quest_id.")
		return
	if not _is_initialized:
		_startup_queue.append(func(): reject_quest_id(quest_id))
		return
	if not _ensure_quest_loaded(quest_id):
		return
	var file_id = _resolve_instance_file_id(quest_id)
	var instance = _pool_registry.get_instance_by_file_id(file_id)
	if not instance:
		return
	if instance.current_status != QWEnums.QuestState.AVAILABLE:
		return
	instance.rejected_by_player = true
	var signal_id = _get_signal_id_for_instance(instance)
	quest_rejected.emit(signal_id)
	quest_data_changed.emit(signal_id)
	_send_instance_update(instance)
	if _logger:
		_logger.log("Flow", "Quest '%s' rejected by player." % signal_id)


## Adds a Callable condition for accepting a quest. The Callable must return bool.
func add_acceptance_condition(quest_id: StringName, condition: Callable) -> void:
	if not _is_valid_quest_id(quest_id):
		return
	if not _acceptance_conditions.has(quest_id):
		_acceptance_conditions[quest_id] = []
	_acceptance_conditions[quest_id].append(condition)


## Clears all acceptance conditions for a quest. Removes entries for both quest_id and file_id,
## matching the lookup logic in can_accept_quest.
func clear_acceptance_conditions(quest_id: StringName) -> void:
	if quest_id.is_empty():
		return
	_acceptance_conditions.erase(quest_id)
	var file_id = _resolve_instance_file_id(quest_id)
	if not file_id.is_empty() and file_id != quest_id:
		_acceptance_conditions.erase(file_id)


## Returns true if the player previously rejected this quest while it was AVAILABLE.
func was_quest_rejected(quest_id: StringName) -> bool:
	var file_id = _resolve_instance_file_id(quest_id)
	var instance = _pool_registry.get_instance_by_file_id(file_id)
	return instance != null and instance.rejected_by_player


## Starts a quest using its Logical ID. Auto-loads if registered. Fails if can_accept_quest returns false.
func start_quest_id(quest_id: StringName) -> void:
	if not _is_valid_quest_id(quest_id):
		push_warning("[QuestController] start_quest_id called with empty quest_id.")
		return
	if not _is_initialized:
		_startup_queue.append(func(): start_quest_id(quest_id))
		return

	if not _ensure_quest_loaded(quest_id):
		if _logger:
			_logger.warn("Flow", "start_quest_id: Could not find or load quest '%s'." % quest_id)
		return

	var context_node = _id_to_context_node_map.get(quest_id)
	if context_node:
		start_quest(context_node)  # Internal activation
		_activate_node(context_node)
	else:
		if _logger:
			_logger.error(
				"Flow", "Loaded graph for '%s' but ContextNode is missing in map." % quest_id
			)


## Starts a quest using its File ID (filename).
func start_quest_file(file_id: StringName) -> void:
	if not _is_valid_quest_id(file_id):
		push_warning("[QuestController] start_quest_file called with empty file_id.")
		return
	if not _is_initialized:
		_startup_queue.append(func(): start_quest_file(file_id))
		return

	# 1. Check if already loaded/active
	var resolved_id = _resolve_instance_file_id(file_id)
	if _pool_registry.has_instance(resolved_id):
		var instance = _pool_registry.get_instance_by_file_id(resolved_id)
		if instance.current_status == QWEnums.QuestState.UNAVAILABLE:
			_start_specific_graph_entry(resolved_id)
		return

	# 2. Check Registry (Direct Lookup via FileID key if it matches LogicalID by chance)
	if _registry_map.has(file_id):
		start_sub_graph(_registry_map[file_id])
		return

	# 3. Fallback: O(1) lookup via file basename
	var path = _file_basename_to_path.get(file_id, "")
	if not path.is_empty():
		start_sub_graph(path)
		return

	if _logger:
		_logger.warn("Flow", "start_quest_file: '%s' not found." % file_id)


## Restarts a quest by Logical ID.
func restart_quest_id(quest_id: StringName) -> void:
	if not _is_valid_quest_id(quest_id):
		push_warning("[QuestController] restart_quest_id called with empty quest_id.")
		return
	if not _is_initialized:
		_startup_queue.append(func(): restart_quest_id(quest_id))
		return

	var file_id = _resolve_instance_file_id(quest_id)

	if file_id == quest_id and not _pool_registry.has_instance(file_id):
		start_quest_id(quest_id)  # Fallback start
		return

	_restart_quest_internal(file_id)


## Restarts a quest by File ID. Clears active nodes and objective state, then reactivates.
func restart_quest_file(file_id: StringName) -> void:
	if not _is_valid_quest_id(file_id):
		push_warning("[QuestController] restart_quest_file called with empty file_id.")
		return
	if not _is_initialized:
		_startup_queue.append(func(): restart_quest_file(file_id))
		return
	_restart_quest_internal(file_id)


## Starts a quest with parameters.
func start_quest_with_parameters(quest_id: StringName, params: Dictionary) -> void:
	if not _is_valid_quest_id(quest_id):
		push_warning("[QuestController] start_quest_with_parameters called with empty quest_id.")
		return
	if not _is_initialized:
		_startup_queue.append(func(): start_quest_with_parameters(quest_id, params))
		return

	# Ensure loaded (fallback: file_id logic may still work)
	if not _ensure_quest_loaded(quest_id) and _logger:
		_logger.warn(
			"Flow",
			(
				"start_quest_with_parameters: Could not load '%s'. Attempting file_id fallback."
				% quest_id
			)
		)

	var file_id = _resolve_instance_file_id(quest_id)
	var instance = _get_or_create_instance(file_id, quest_id)
	for key in params:
		instance.set_variable(key, params[key])

	if _logger:
		_logger.log("Flow", "Injected params into '%s': %s" % [file_id, params])

	var context_node = _id_to_context_node_map.get(quest_id)
	if not context_node:
		context_node = _id_to_context_node_map.get(file_id)

	if context_node:
		start_quest(context_node)
		_activate_node(context_node)
	else:
		_start_specific_graph_entry(file_id)


func complete_quest_id(quest_id: StringName, success: bool = true) -> void:
	if not _is_valid_quest_id(quest_id):
		push_warning("[QuestController] complete_quest_id called with empty quest_id.")
		return
	var action = (
		QuestNodeResource.QuestAction.COMPLETE if success else QuestNodeResource.QuestAction.FAIL
	)
	set_quest_status(quest_id, action)


func complete_quest_file(file_id: StringName, success: bool = true) -> void:
	if not _is_valid_quest_id(file_id):
		push_warning("[QuestController] complete_quest_file called with empty file_id.")
		return
	var action = (
		QuestNodeResource.QuestAction.COMPLETE if success else QuestNodeResource.QuestAction.FAIL
	)
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
	if not context_node:
		return {}
	var file_id = _resolve_instance_file_id(query_id)
	var instance = _pool_registry.get_instance_by_file_id(file_id)
	var result = {}
	for r in context_node.rewards:
		if not r is Dictionary:
			continue
		var r_id = r.get("id", &"unknown")
		var r_amount = int(r.get("amount", 0))
		if r_id.is_empty():
			continue
		var linked_obj_id: StringName = r.get("linked_objective_id", &"")
		if not linked_obj_id.is_empty():
			if (
				not is_instance_valid(instance)
				or (
					instance.get_objective_status(linked_obj_id)
					!= ObjectiveResource.Status.COMPLETED
				)
			):
				continue
		result[r_id] = result.get(r_id, 0) + r_amount
	return result


## Debug/Cheat Tool: Forces the quest flow to jump to a specific node.
## Stops all currently active nodes in this quest before jumping.
func jump_to_node(node_id: StringName) -> void:
	var file_id = _get_file_id_for_node(node_id)
	var instance = _pool_registry.get_instance_by_file_id(file_id)
	var logger = _get_logger()

	if not instance:
		if logger:
			logger.warn("Flow", "Jump failed: No instance found for node '%s'." % node_id)
		return

	if logger:
		logger.log("Flow", ">>> FORCE JUMP to node '%s' in quest '%s'" % [node_id, file_id])

	# 1. Stop ALL currently active nodes in this instance
	# (Simulate that we left the previous state)
	for active_id in instance.active_node_ids.duplicate():
		_cleanup_node_runtime(active_id, instance)
	instance.active_node_ids.clear()

	# 2. Ensure Quest is Active (if we jump into a inactive quest)
	if instance.current_status != QWEnums.QuestState.ACTIVE:
		_pool_registry.move_instance_to_pool(instance, QWEnums.QuestState.ACTIVE)
		quest_started.emit(_get_signal_id_for_instance(instance))
		_send_instance_update(instance)

	# 3. Activate Target
	var node_def = _node_definitions.get(node_id)
	if node_def:
		_activate_node(node_def)


func set_quest_status(query_id: StringName, action: QuestNodeResource.QuestAction) -> void:
	var logger = _logger
	if query_id.is_empty():
		return

	# START Action: Logic is different (Activation)
	if action == QuestNodeResource.QuestAction.START:
		start_quest_id(query_id)
		return

	# MARK_AVAILABLE Action: Marks quest as available (e.g. for Quest Board)
	if action == QuestNodeResource.QuestAction.MARK_AVAILABLE:
		_pool_manager.set_quest_available(query_id)
		return

	# Resolve Instance ID (File ID) from Query ID
	var file_id = _resolve_instance_file_id(query_id)

	if not _pool_registry.has_instance(file_id):
		if logger:
			logger.warn("Flow", "Cannot change status of inactive/unknown quest '%s'." % query_id)
		return

	var instance: QuestInstance = _pool_registry.get_instance_by_file_id(file_id)
	var target_status = QWEnums.QuestState.ACTIVE

	match action:
		QuestNodeResource.QuestAction.COMPLETE:
			target_status = QWEnums.QuestState.COMPLETED
		QuestNodeResource.QuestAction.FAIL:
			target_status = QWEnums.QuestState.FAILED

	if instance.current_status != target_status:
		_pool_registry.move_instance_to_pool(instance, target_status)

		if logger:
			logger.log("Flow", "Quest '%s' status changed to %d." % [query_id, target_status])

		var signal_id = _get_signal_id_for_instance(instance)

		if target_status == QWEnums.QuestState.COMPLETED:
			quest_completed.emit(signal_id)
		elif target_status == QWEnums.QuestState.FAILED:
			quest_failed.emit(signal_id)
		_send_instance_update(instance)


func force_skip_node(node_id: StringName) -> void:
	var file_id = _get_file_id_for_node(node_id)
	var instance = _pool_registry.get_instance_by_file_id(file_id)

	if not instance or not instance.is_node_active(node_id):
		return

	var node_def = _node_definitions.get(node_id)
	if not node_def:
		return

	var logger = _get_logger()
	if logger:
		logger.log("System", "Force skipping node: %s" % node_id)

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

	var global_bus = _get_event_bus()
	if is_instance_valid(global_bus):
		global_bus.unlock_interaction(node_id)

	complete_node(node_def)


func reset_all_graphs_and_quests() -> void:
	if _is_shutting_down:
		return
	var logger = _logger
	if is_instance_valid(logger):
		logger.log("Flow", "Resetting all graphs and quest states.")

	_pool_registry.clear_all()
	if is_instance_valid(_timer_manager):
		_timer_manager.clear_all_timers()
	if is_instance_valid(_sync_manager):
		_sync_manager.clear()
	if is_instance_valid(_event_manager):
		_event_manager.clear()
	if is_instance_valid(_scope_manager):
		_scope_manager.clear()


func start_all_loaded_graphs() -> void:
	_ensure_execution_context_exists()

	var settings = QWConstants.get_settings()
	if settings and not settings.auto_start_quests.is_empty():
		for raw_path in settings.auto_start_quests:
			if raw_path.is_empty():
				continue

			var final_path = raw_path
			if raw_path.begins_with("uid://"):
				var id = ResourceUID.text_to_id(raw_path)
				if id != ResourceUID.INVALID_ID and ResourceUID.has_id(id):
					final_path = ResourceUID.get_id_path(id)

			if is_instance_valid(_logger):
				_logger.log("System", "Auto-starting: " + final_path)
			_start_specific_graph_entry(final_path)


func start_sub_graph(graph_path: String) -> void:
	if ResourceLoader.exists(graph_path):
		var graph_res = ResourceLoader.load(graph_path, "QuestGraphResource") as QuestGraphResource
		if is_instance_valid(graph_res):
			graph_res.resource_path = graph_path
			_load_graph_data(graph_res)
		else:
			if _logger:
				_logger.error(
					"System", "Sub-graph at '%s' is not a valid QuestGraphResource." % graph_path
				)
			return
	else:
		if _logger:
			_logger.error("System", "Could not load sub-graph resource at '%s'." % graph_path)
		return

	var file_id: StringName = StringName(graph_path.get_file().get_basename())

	# Create Instance if missing, initially UNAVAILABLE
	if not _pool_registry.has_instance(file_id):
		var instance = QuestInstance.new(file_id)
		_pool_registry.add_instance_to_pool(instance, QWEnums.QuestState.UNAVAILABLE)
		_update_logical_id_map(file_id, file_id)

		if is_instance_valid(_logger):
			_logger.log("Flow", "Sub-Graph: Created instance '%s' (Status: INACTIVE)." % file_id)

	var nodes_in_graph = _quest_node_map.get(graph_path, [])
	var fallback_context_node: GraphNodeResource = null

	for node_id in nodes_in_graph:
		var node = _node_definitions.get(node_id)
		if node is StartNodeResource:
			_activate_node(node)
			return
		if node is QuestContextNodeResource:
			fallback_context_node = node

	if fallback_context_node:
		if _logger:
			_logger.warn(
				"Flow",
				"Sub-graph '%s' has no StartNode. Starting at QuestContextNode." % graph_path
			)
		_activate_node(fallback_context_node)
	else:
		if _logger:
			_logger.error("Flow", "Sub-graph at '%s' has no entry point." % graph_path)


func push_to_call_stack(parent_node_id: StringName) -> void:
	var parent_graph_path = _get_quest_path_for_node(parent_node_id)
	if parent_graph_path.is_empty():
		return

	var child_path = ""
	var node = _node_definitions.get(parent_node_id)
	if node and node is SubGraphNodeResource:
		child_path = node.quest_graph_path
		if child_path.begins_with("uid://"):
			var id = ResourceUID.text_to_id(child_path)
			if id != ResourceUID.INVALID_ID and ResourceUID.has_id(id):
				child_path = ResourceUID.get_id_path(id)

	_call_stack.append(
		{
			"parent_node_id": parent_node_id,
			"parent_quest_path": parent_graph_path,
			"child_graph_path": child_path
		}
	)


func pop_from_call_stack() -> void:
	if _call_stack.is_empty():
		return

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
	if current_graph_path.is_empty():
		return

	var anchors_in_graph = _anchor_name_to_node.get(current_graph_path, {})
	var target_anchor: AnchorNodeResource = anchors_in_graph.get(anchor_name) as AnchorNodeResource

	if target_anchor:
		if is_instance_valid(_logger):
			_logger.log("Flow", "  -> JUMPING to Anchor '%s'." % anchor_name)
		_activate_node(target_anchor)
	else:
		if is_instance_valid(_logger):
			_logger.warn(
				"Flow", "JumpNode '%s' could not find Anchor '%s'." % [origin_node.id, anchor_name]
			)


# --- ADAPTER ACCESS (for Executors via ExecutionContext) ---


func get_inventory_adapter() -> QuestInventoryAdapterBase:
	return _inventory_adapter


func get_kill_adapter() -> QuestKillAdapterBase:
	return _kill_adapter


# --- SAVE / LOAD ---

## Returns a Dictionary with all quest instance state for persistence.


func get_save_data() -> Dictionary:
	if not is_instance_valid(_persistence_manager):
		return {}
	return _persistence_manager.save_state(self)


## Restores quest instance state from a previously saved dictionary.
## Returns true on success, false if data format is invalid.
func load_from_data(data: Dictionary) -> bool:
	if not is_instance_valid(_persistence_manager):
		return false
	return _persistence_manager.load_state(self, data)


# --- CORE LOGIC ---

## Activates a node and runs its executor.


## [param instance] can be null for QuestContextNodeResource (entry point) - executors must handle null.
func _activate_node(node_definition: GraphNodeResource, from_input_port: int = 0) -> void:
	var logger = _logger
	if not is_instance_valid(node_definition):
		return

	var file_id = _node_to_file_id_map.get(node_definition.id, &"")
	var instance: QuestInstance = _pool_registry.get_instance_by_file_id(file_id)

	if not instance and not (node_definition is QuestContextNodeResource):
		if logger:
			logger.warn(
				"Flow", "Node '%s' activated but no Quest Instance found." % node_definition.id
			)
		return

	if logger:
		logger.log(
			"Flow",
			"-> Activating Node: '%s' (Blueprint) in Instance '%s'" % [node_definition.id, file_id]
		)

	_send_debug_message("node_activated", [node_definition.id])

	if instance:
		# RE-ENTRY CHECK
		if instance.is_node_active(node_definition.id):
			if logger:
				logger.log(
					"Flow",
					"   - Node already active. Resetting previous execution state (Re-Entry)."
				)
			_cleanup_node_runtime(node_definition.id, instance)

		instance.set_node_active(node_definition.id, true)
		instance.set_node_data(node_definition.id, "_entry_port", from_input_port)

	var executor: NodeExecutor = _node_registry.get_executor_for_node(node_definition)
	if executor:
		executor.execute(_execution_context, node_definition, instance)
	else:
		complete_node(node_definition)

	if instance:
		_send_instance_update(instance)


func complete_node(node_definition: GraphNodeResource) -> void:
	var logger = _logger
	var file_id = _node_to_file_id_map.get(node_definition.id, &"")
	var instance: QuestInstance = _pool_registry.get_instance_by_file_id(file_id)

	if logger:
		logger.log("Flow", "<- Completing Node: '%s'" % node_definition.id)

	_send_debug_message("node_completed", [node_definition.id])

	if instance:
		instance.set_node_active(node_definition.id, false)
		_send_instance_update(instance)

	if node_definition is EndNodeResource:
		var current_graph_path = _get_quest_path_for_node(node_definition.id)
		_cleanup_graph_instances(current_graph_path)

		if not _call_stack.is_empty():
			var top = _call_stack.back()
			if top.get("child_graph_path", "") == current_graph_path:
				pop_from_call_stack()
				return

	_trigger_next_nodes_from_port(node_definition, 0)


func _mark_node_as_logically_complete(node_definition: GraphNodeResource) -> void:
	_send_debug_message("node_completed", [node_definition.id])
	var file_id = _node_to_file_id_map.get(node_definition.id, &"")
	var instance: QuestInstance = _pool_registry.get_instance_by_file_id(file_id)
	if instance:
		instance.set_node_active(node_definition.id, false)
		_send_instance_update(instance)


func _get_file_id_for_node(node_id: StringName) -> StringName:
	return _node_to_file_id_map.get(node_id, &"")


func _get_signal_id_for_instance(instance: QuestInstance) -> StringName:
	return instance.quest_id if not instance.quest_id.is_empty() else instance.file_id


func _is_valid_quest_id(id: StringName) -> bool:
	if id.is_empty():
		return false
	if " " in str(id):
		return not String(id).strip_edges().is_empty()
	return true


func _on_objective_in_node_changed(
	_new_status: int, node: TaskNodeResource, _objective: ObjectiveResource
) -> void:
	var file_id = _get_file_id_for_node(node.id)
	var instance = _pool_registry.get_instance_by_file_id(file_id)

	if instance:
		var signal_id = _get_signal_id_for_instance(instance)
		quest_data_changed.emit(signal_id)

		var all_complete = true
		for obj in node.objectives:
			if instance.get_objective_status(obj.id) != ObjectiveResource.Status.COMPLETED:
				all_complete = false
				break

		if all_complete:
			complete_node(node)


func _check_tasks_in_instance(instance: QuestInstance) -> void:
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
			_registry_map.clear()
			_file_basename_to_path.clear()
			for k in registry.quest_path_map:
				var p: String = registry.quest_path_map[k]
				_registry_map[StringName(k)] = p
				var basename := StringName(p.get_file().get_basename())
				_file_basename_to_path[basename] = p
			if _logger:
				_logger.log("System", "Loaded Registry. Known Quests: %d" % _registry_map.size())


func _ensure_quest_loaded(quest_id: StringName) -> bool:
	if _id_to_context_node_map.has(quest_id):
		return true

	if _registry_map.has(quest_id):
		var path = _registry_map[quest_id]
		if ResourceLoader.exists(path):
			if _logger:
				_logger.log("System", "Auto-Loading quest '%s' from '%s'" % [quest_id, path])
			var res = ResourceLoader.load(path, "QuestGraphResource") as QuestGraphResource
			if is_instance_valid(res):
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


func _restart_quest_internal(file_id: StringName) -> void:
	if not _pool_registry.has_instance(file_id):
		return

	var instance: QuestInstance = _pool_registry.get_instance_by_file_id(file_id)
	if _logger:
		_logger.log("Flow", "Restarting Quest Instance '%s'..." % file_id)

	for node_id in instance.active_node_ids.duplicate():
		_cleanup_node_runtime(node_id, instance)

	instance.active_node_ids.clear()
	instance.node_states.clear()
	instance.objective_states.clear()
	_pool_registry.move_instance_to_pool(instance, QWEnums.QuestState.UNAVAILABLE)

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
	# 1. O(1) cache lookup
	if _logical_id_to_file_id.has(query_id):
		return _logical_id_to_file_id[query_id]
	# 2. Active File ID?
	if _pool_registry.has_instance(query_id):
		return query_id
	# 3. Static Definition? (Loaded but inactive)
	if _id_to_context_node_map.has(query_id):
		var context = _id_to_context_node_map[query_id]
		var fid = _node_to_file_id_map.get(context.id)
		if fid:
			_update_logical_id_map(query_id, fid)
			return fid
	return query_id


func _update_logical_id_map(logical_id: StringName, file_id: StringName) -> void:
	if logical_id.is_empty():
		return
	_logical_id_to_file_id[logical_id] = file_id


func _get_or_create_instance(
	file_id: StringName, optional_logical_id: StringName = &""
) -> QuestInstance:
	var instance = _pool_registry.get_instance_by_file_id(file_id)
	if not instance:
		instance = QuestInstance.new(file_id)
		_pool_registry.add_instance_to_pool(instance, QWEnums.QuestState.UNAVAILABLE)
		_update_logical_id_map(file_id, file_id)
		if not optional_logical_id.is_empty():
			var ctx = _id_to_context_node_map.get(optional_logical_id)
			if ctx:
				instance.quest_id = ctx.quest_id
				if not instance.quest_id.is_empty():
					_update_logical_id_map(instance.quest_id, file_id)
	return instance


func _remove_from_logical_id_map(instance: QuestInstance) -> void:
	_logical_id_to_file_id.erase(instance.file_id)
	if not instance.quest_id.is_empty():
		_logical_id_to_file_id.erase(instance.quest_id)


func _register_objective_instance(objective_id: StringName, file_id: StringName) -> void:
	if objective_id.is_empty():
		return
	_objective_id_to_file_id[objective_id] = file_id


func _unregister_objective_instance(objective_id: StringName) -> void:
	_objective_id_to_file_id.erase(objective_id)


func _cleanup_node_runtime(node_id: StringName, instance: QuestInstance) -> void:
	var node_def = _node_definitions.get(node_id)
	if not node_def:
		return

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
	if not is_instance_valid(settings):
		return

	var paths: Array[String] = []
	for raw_path in settings.auto_start_quests:
		if not raw_path.is_empty():
			var p = raw_path
			if p.begins_with("uid://"):
				var id = ResourceUID.text_to_id(p)
				if id != ResourceUID.INVALID_ID and ResourceUID.has_id(id):
					p = ResourceUID.get_id_path(id)
			paths.append(p)

	for path in paths:
		if ResourceLoader.exists(path):
			var res = ResourceLoader.load(path, "QuestGraphResource") as QuestGraphResource
			if is_instance_valid(res):
				res.resource_path = path
				_load_graph_data(res)


## Loads graph definitions and maps Context Nodes. Only the first QuestContextNode per graph is used
## for logical_id/file_id mapping (one-context-per-quest-file design). Additional ContextNodes in the
## same graph are ignored.
func _load_graph_data(graph_resource: QuestGraphResource) -> void:
	if not is_instance_valid(graph_resource):
		push_error("QuestController: _load_graph_data called with invalid graph_resource.")
		return
	var path = graph_resource.resource_path
	if path.is_empty():
		push_warning("QuestController: Graph has no resource_path. Skipping load.")
		return
	if _quest_node_map.has(path):
		return

	# Create map entry with typed array
	var node_list: Array[StringName] = []
	_quest_node_map[path] = node_list

	var file_id: StringName = StringName(path.get_file().get_basename())

	# 1. Map Context Nodes (Logical ID -> Node Resource)
	for node_id in graph_resource.nodes:
		var node = graph_resource.nodes[node_id]
		if node is QuestContextNodeResource:
			var logical_id = node.quest_id
			if not logical_id.is_empty():
				_id_to_context_node_map[logical_id] = node
				_update_logical_id_map(logical_id, file_id)

			# Fallback mapping
			if logical_id != file_id:
				_id_to_context_node_map[file_id] = node
			_update_logical_id_map(file_id, file_id)
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
			_node_id_to_quest_path[node_id] = path
			_node_to_file_id_map[node_id] = file_id
			if node is TaskNodeResource:
				for obj in node.objectives:
					_objective_id_to_resource[obj.id] = obj
					_objective_id_to_file_id[obj.id] = file_id
			if node is AnchorNodeResource:
				if not _anchor_name_to_node.has(path):
					_anchor_name_to_node[path] = {}
				_anchor_name_to_node[path][node.anchor_name] = node

	for connection in graph_resource.connections:
		var from_val = connection.get("from_node")
		var to_val = connection.get("to_node")
		if (
			from_val == null
			or to_val == null
			or not (from_val is String or from_val is StringName)
			or not (to_val is String or to_val is StringName)
		):
			push_warning(
				"QuestController: Skipping invalid connection (missing or invalid from_node/to_node)."
			)
			continue
		var from_id = StringName(from_val)
		if not _node_connections.has(from_id):
			_node_connections[from_id] = []
		_node_connections[from_id].append(connection)


func _start_specific_graph_entry(graph_path: String) -> void:
	if not _quest_node_map.has(graph_path):
		if ResourceLoader.exists(graph_path):
			var res = ResourceLoader.load(graph_path, "QuestGraphResource") as QuestGraphResource
			if is_instance_valid(res):
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
		if not _pool_registry.has_instance(file_id):
			var instance = QuestInstance.new(file_id)
			_pool_registry.add_instance_to_pool(instance, QWEnums.QuestState.ACTIVE)
			_update_logical_id_map(file_id, file_id)

			if is_instance_valid(_logger):
				_logger.log("Flow", "Auto-Start: Created implicit instance for '%s'." % file_id)

			var instance_for_start = _pool_registry.get_instance_by_file_id(file_id)
			quest_started.emit(file_id)
			quest_data_changed.emit(file_id)
			_send_instance_update(instance_for_start)

		_activate_node(start_node_def)
	else:
		if is_instance_valid(_logger):
			_logger.warn("Flow", "Auto-start graph '%s' has no StartNode." % graph_path)


func _trigger_next_nodes_from_port(from_node: GraphNodeResource, from_port_index: int) -> void:
	var logger = _logger
	if logger:
		logger.log(
			"Flow",
			"    - Triggering next nodes from '%s' port %d..." % [from_node.id, from_port_index]
		)

	var connections = _node_connections.get(from_node.id, [])
	var triggered_count = 0
	for connection in connections:
		if connection.get("from_port") == from_port_index:
			var next_node_id = StringName(connection.get("to_node"))
			var to_port = connection.get("to_port", 0)
			var next_node_def = _node_definitions.get(next_node_id)
			if next_node_def:
				_activate_node(next_node_def, to_port)
				triggered_count += 1
	# Only Success (port 0) must be connected for non-terminal nodes; Partial/Failure are optional
	if (
		logger
		and triggered_count == 0
		and from_node is GiveTakeItemNodeResource
		and from_port_index == 0
	):
		logger.warn(
			"Flow",
			(
				"    - No connections from '%s' Success port. Connect the Success output."
				% from_node.id
			)
		)


## Called by QuestSyncManager via call_deferred to process pending sync operations for a node.
func _process_sync_node_batch(node_id: StringName, instance: QuestInstance) -> void:
	if is_instance_valid(_sync_manager):
		_sync_manager.process_pending(node_id, instance)


func _cleanup_graph_instances(graph_path: String) -> void:
	var file_id_to_cleanup: StringName = StringName(graph_path.get_file().get_basename())

	if _pool_registry.has_instance(file_id_to_cleanup):
		var instance = _pool_registry.get_instance_by_file_id(file_id_to_cleanup)

		for node_id in instance.active_node_ids:
			_cleanup_node_runtime(node_id, instance)

		instance.active_node_ids.clear()

		var keep_in_memory = (
			not instance.quest_id.is_empty()
			or instance.current_status != QWEnums.QuestState.UNAVAILABLE
		)

		if keep_in_memory:
			if is_instance_valid(_logger):
				_logger.log(
					"System",
					(
						"Graph finished but Instance '%s' kept in memory (Status: %d)."
						% [file_id_to_cleanup, instance.current_status]
					)
				)
		else:
			_remove_from_logical_id_map(instance)
			_pool_registry.remove_instance_from_all_pools(file_id_to_cleanup)
			if is_instance_valid(_logger):
				_logger.log(
					"System",
					"Graph finished and Instance '%s' garbage collected." % file_id_to_cleanup
				)


func _get_quest_path_for_node(node_id: StringName) -> String:
	return _node_id_to_quest_path.get(node_id, "")


func _on_interacted_with_object(interacted_node: Node):
	if not is_instance_valid(_execution_context):
		return
	var path = str(interacted_node.get_path())

	if _execution_context.interact_objective_listeners.has(path):
		var global_bus = _get_event_bus()
		var wrappers = _execution_context.interact_objective_listeners[path]
		for w in wrappers:
			var obj: ObjectiveResource = w.objective
			var instance: QuestInstance = _pool_registry.get_instance_by_file_id(w.file_id)

			if instance:
				instance.set_objective_status(obj.id, ObjectiveResource.Status.COMPLETED)

				# Granular State Signal
				if global_bus:
					var sig_id = _get_signal_id_for_instance(instance)
					global_bus.quest_objective_state_changed.emit(
						sig_id, obj.id, ObjectiveResource.Status.COMPLETED
					)

				_check_tasks_in_instance(instance)


func _on_enemy_was_killed(enemy_id: StringName):
	if not is_instance_valid(_execution_context):
		return
	if is_instance_valid(_kill_adapter):
		return  # Adapter handles progress via _check_kill_objectives

	# Key lookup with StringName cast
	if _execution_context.kill_objective_listeners.has(String(enemy_id)):
		var wrappers = _execution_context.kill_objective_listeners[String(enemy_id)]
		var global_bus = _get_event_bus()

		for w in wrappers:
			var obj: ObjectiveResource = w.objective
			var instance = _pool_registry.get_instance_by_file_id(w.file_id)
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

				var signal_id = _get_signal_id_for_instance(instance)
				var required_for_this = obj.requirements.get(target_key, 1)

				if global_bus:
					global_bus.quest_objective_progress_changed.emit(
						signal_id, obj.id, progress_amount, required_for_this
					)
				quest_data_changed.emit(signal_id)

				# CHECK IF ALL REQUIREMENTS MET
				if _are_all_requirements_met(instance, obj):
					instance.set_objective_status(obj.id, ObjectiveResource.Status.COMPLETED)
					if global_bus:
						global_bus.quest_objective_state_changed.emit(
							signal_id, obj.id, ObjectiveResource.Status.COMPLETED
						)
					_check_tasks_in_instance(instance)


func _on_entered_location(location_id: String):
	if not is_instance_valid(_execution_context):
		return

	if _execution_context.location_objective_listeners.has(location_id):
		var global_bus = _get_event_bus()
		var wrappers = _execution_context.location_objective_listeners[location_id]

		for w in wrappers:
			var obj: ObjectiveResource = w.objective
			var instance = _pool_registry.get_instance_by_file_id(w.file_id)

			if instance:
				instance.set_objective_status(obj.id, ObjectiveResource.Status.COMPLETED)

				var signal_id = _get_signal_id_for_instance(instance)

				if global_bus:
					global_bus.quest_objective_state_changed.emit(
						signal_id, obj.id, ObjectiveResource.Status.COMPLETED
					)

				_check_tasks_in_instance(instance)


func _check_item_collect_objectives() -> void:
	if not is_instance_valid(_execution_context) or not is_instance_valid(_inventory_adapter):
		return
	var count_func = func(key_str: StringName) -> int: return _inventory_adapter.count_item(key_str)
	_check_objectives_from_adapter(_execution_context.item_objective_listeners, count_func, true)


func _check_kill_objectives() -> void:
	if not is_instance_valid(_execution_context) or not is_instance_valid(_kill_adapter):
		return
	var count_func = func(key_str: StringName) -> int: return _kill_adapter.count_kill(key_str)
	_check_objectives_from_adapter(_execution_context.kill_objective_listeners, count_func, false)


## Shared logic for adapter-based objective checks (item collect, kill). [param skip_complete_on_delivery] skips
## completion when obj.complete_on_delivery is true (used for ITEM_COLLECT; GiveTakeItem completes those).
func _check_objectives_from_adapter(
	listeners_dict: Dictionary, count_func: Callable, skip_complete_on_delivery: bool
) -> void:
	var global_bus = _get_event_bus()
	for key_str in listeners_dict:
		var target_key = StringName(key_str)
		var current_count = count_func.call(target_key)
		var wrappers = listeners_dict[key_str]
		for w in wrappers:
			var obj: ObjectiveResource = w.objective
			var instance = _pool_registry.get_instance_by_file_id(w.file_id)
			if not instance:
				continue

			var snapshot_key = StringName("start_amount_%s_%s" % [obj.id, target_key])
			var start_amount = instance.get_node_data(w.task_node_id, snapshot_key, 0)
			var progress_amount = current_count
			if obj.track_progress_since_activation:
				progress_amount = max(0, current_count - start_amount)
			var required = obj.requirements.get(target_key, 1)
			progress_amount = min(progress_amount, required)

			var stored_progress = instance.get_objective_progress_by_key(obj.id, target_key)
			if stored_progress != progress_amount:
				instance.set_objective_progress_by_key(obj.id, target_key, progress_amount)
				var signal_id = _get_signal_id_for_instance(instance)
				if global_bus:
					global_bus.quest_objective_progress_changed.emit(
						signal_id, obj.id, progress_amount, required
					)
				quest_data_changed.emit(signal_id)

			if skip_complete_on_delivery and obj.complete_on_delivery:
				continue
			if _are_all_requirements_met(instance, obj):
				if instance.get_objective_status(obj.id) != ObjectiveResource.Status.COMPLETED:
					instance.set_objective_status(obj.id, ObjectiveResource.Status.COMPLETED)
					var sig_id = _get_signal_id_for_instance(instance)
					if global_bus:
						global_bus.quest_objective_state_changed.emit(
							sig_id, obj.id, ObjectiveResource.Status.COMPLETED
						)
					quest_data_changed.emit(sig_id)
					_check_tasks_in_instance(instance)


func _send_debug_message(message: String, data: Array = []) -> void:
	if not OS.is_debug_build():
		return
	if not EngineDebugger.is_active():
		return
	EngineDebugger.send_message("quest_weaver:%s" % message, data)


func _send_instance_update(instance: QuestInstance) -> void:
	if not EngineDebugger.is_active():
		return
	var obj_states: Dictionary = {}
	for k in instance.objective_states:
		obj_states[str(k)] = instance.objective_states[k].duplicate()
	var active_keys: Array = []
	for k in instance.active_node_ids:
		active_keys.append(str(k))
	var payload = {
		"file_id": str(instance.file_id),
		"quest_id": str(instance.quest_id),
		"status": instance.current_status,
		"variables": instance.variables.duplicate(),
		"active_node_ids": active_keys,
		"objective_states": obj_states
	}
	_send_debug_message("instance_update", [payload])


# --- SHUTDOWN LOGIC ---


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if not _is_shutting_down:
			shutdown()
	elif what == NOTIFICATION_EXIT_TREE:
		if not _is_shutting_down:
			_on_exit_cleanup()


## Light shutdown for programmatic teardown (e.g. WM_CLOSE_REQUEST).
## Clears runtime state (instances, definitions, exec context) and all static maps for consistency.
## For full cleanup on scene exit, see [method _on_exit_cleanup].
func shutdown() -> void:
	_is_shutting_down = true
	if OS.is_debug_build():
		_unregister_performance_monitors()
	_send_debug_message("session_ended")

	if is_instance_valid(_timer_manager):
		_timer_manager.clear_all_timers()
	if is_instance_valid(_sync_manager):
		_sync_manager.clear()
	if is_instance_valid(_event_manager):
		_event_manager.clear()
	if is_instance_valid(_scope_manager):
		_scope_manager.clear()
	if is_instance_valid(_presentation_manager):
		_presentation_manager.force_close_current()
	if is_instance_valid(_execution_context):
		_execution_context.cleanup()
		_execution_context = null
	_pool_registry.clear_all()
	_node_definitions.clear()
	_node_connections.clear()
	_quest_node_map.clear()
	_id_to_context_node_map.clear()
	_node_to_file_id_map.clear()
	_logical_id_to_file_id.clear()
	_objective_id_to_resource.clear()
	_objective_id_to_file_id.clear()
	_node_id_to_quest_path.clear()
	_registry_map.clear()
	_file_basename_to_path.clear()
	_anchor_name_to_node.clear()
	QWConstants.clear_static_references()


# --- DEBUG API (Developer Tools) ---
# Delegated to QuestControllerDebug to reduce public method count and file size.
# QuestDebugProxy calls these _debug_* methods.


func _debug_dump_quest_state(query_id: StringName) -> void:
	_debug_helper.dump_quest_state(query_id)


func _debug_complete_active_tasks(query_id: StringName) -> void:
	_debug_helper.complete_active_tasks(query_id)


func _debug_set_variable(query_id: StringName, key: StringName, value: Variant) -> void:
	_debug_helper.set_variable(query_id, key, value)


func _debug_list_quests() -> void:
	_debug_helper.list_quests()


func _debug_list_active_instances() -> void:
	_debug_helper.list_active_instances()
