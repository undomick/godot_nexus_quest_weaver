# res://addons/quest_weaver/systems/managers/quest_timer_manager.gd
class_name QuestTimerManager
extends RefCounted

## Manages active TimerNode instances.
## Keeps track of physical Timer nodes, but stores state in the QuestInstance.
## TimerNodeResource.duration is in seconds; ticks map 1:1 to seconds via TICK_INTERVAL.

const TICK_INTERVAL := 1.0  ## Seconds between ticks; duration and ticks are 1:1

# Map: StringName (NodeID) -> Timer (Physical Node)
var _active_timer_nodes: Dictionary = {}
var _controller_weak: WeakRef


func _init(p_controller: QuestController):
	self._controller_weak = weakref(p_controller)


func _get_controller() -> QuestController:
	return _controller_weak.get_ref() as QuestController


## Starts a new timer. Called by TimerNodeExecutor.
func start_timer(node_def: TimerNodeResource, instance: QuestInstance) -> void:
	var controller = _get_controller()
	if not controller:
		return

	# node_def.id is StringName
	if _active_timer_nodes.has(node_def.id):
		remove_timer(node_def.id)

	var timer = Timer.new()
	timer.wait_time = TICK_INTERVAL
	timer.one_shot = false
	timer.timeout.connect(_on_timer_tick.bind(node_def.id))

	controller.add_child(timer)
	_active_timer_nodes[node_def.id] = timer

	# Initialize state in Instance if not present (e.g. restoring)
	var current_ticks = instance.get_node_data(node_def.id, &"ticks", -1)
	if current_ticks == -1:
		instance.set_node_data(node_def.id, &"ticks", 0)

	# Trigger "On Start" output immediately
	controller._trigger_next_nodes_from_port(node_def, 0)

	timer.start()


## Stops and removes the physical timer.
func remove_timer(node_id: StringName) -> bool:
	if _active_timer_nodes.has(node_id):
		var timer = _active_timer_nodes[node_id]
		if is_instance_valid(timer):
			timer.stop()
			timer.queue_free()
		_active_timer_nodes.erase(node_id)
		return true
	return false


## Cleans up all running timers (e.g. on game exit or reload).
func clear_all_timers() -> void:
	for timer in _active_timer_nodes.values():
		if is_instance_valid(timer):
			timer.queue_free()
	_active_timer_nodes.clear()


## Called every second.
func _on_timer_tick(node_id: StringName):
	var controller = _get_controller()
	if not controller:
		remove_timer(node_id)
		return

	# 1. Resolve Instance
	var instance: QuestInstance = controller.get_quest_data_manager().get_instance_for_node(node_id)

	# Safety check: If instance is gone, kill timer
	if not instance:
		remove_timer(node_id)
		return

	# 2. Get/Update State using StringName key
	var ticks = instance.get_node_data(node_id, &"ticks", 0)
	ticks += 1
	instance.set_node_data(node_id, &"ticks", ticks)

	# 3. Get Definition
	var node_def = controller._node_definitions.get(node_id)
	if not node_def:
		remove_timer(node_id)
		return

	var logger = controller._get_logger()
	if logger:
		logger.log(
			"Flow", "  - TimerNode '%s' ticked. (%d/%d)" % [node_id, ticks, node_def.duration]
		)

	# 4. Logic
	controller._trigger_next_nodes_from_port(node_def, 1)  # Port 1: "On Tick"

	if ticks >= node_def.duration:
		if logger:
			logger.log("Flow", "  <- TimerNode '%s' finished." % node_id)

		controller._trigger_next_nodes_from_port(node_def, 2)  # Port 2: "On Finish"

		remove_timer(node_id)

		# Complete the node in the controller
		controller.complete_node(node_def)


## Reconstructs physical timers from loaded instance data.
## Called by PersistenceManager after loading QuestInstances.
func restore_timers_from_instances(active_instances: Dictionary) -> void:
	clear_all_timers()
	var controller = _get_controller()
	if not controller:
		return

	for instance: QuestInstance in active_instances.values():
		# Scan this instance for active nodes that are timers
		for node_id in instance.active_node_ids:
			var node_def = controller._node_definitions.get(node_id)
			if node_def is TimerNodeResource:
				# Restart physical timer without resetting tick count
				start_timer(node_def, instance)
