# res://addons/quest_weaver/core/benchmarks/qw_performance_benchmark.gd
extends Node

## Performance benchmark for QuestWeaver core hot paths.
## Run via: Run Current Scene (benchmark_runner.tscn) or as main scene.
## Output: operation,iterations,median_us,p99_us to console.

const ITERATIONS_SMALL = 10_000
const ITERATIONS_LARGE = 100_000

var _controller: QuestController
var _quest_ids: Array[StringName] = []
var _objective_ids: Array[StringName] = []


func _ready() -> void:
	_controller = _find_controller()
	if not _controller:
		push_error("QW Benchmark: QuestController not found. Add QuestController as child.")
		return
	# Wait for controller to initialize
	await get_tree().process_frame
	await get_tree().process_frame
	# Allow controller to finish async init
	await get_tree().create_timer(1.5).timeout
	_run_benchmarks()


func _find_controller() -> QuestController:
	if has_node("QuestController"):
		return get_node("QuestController") as QuestController
	for child in get_children():
		if child is QuestController:
			return child
		var found = child.find_child("QuestController", true, false)
		if found and found is QuestController:
			return found
	return null


func _run_benchmarks() -> void:
	_prepare_test_data()
	print("\n=== QuestWeaver Performance Benchmark ===\n")
	print("operation,iterations,median_us,p99_us")
	_benchmark(
		"get_quest_state",
		ITERATIONS_SMALL,
		func() -> void:
			if _quest_ids.is_empty():
				return
			var q = _quest_ids[0]
			_controller.get_quest_data_manager().get_quest_state(q)
	)
	_benchmark(
		"get_objective_progress",
		ITERATIONS_SMALL,
		func() -> void:
			if _objective_ids.is_empty():
				return
			_controller.get_objective_manager().get_objective_progress(_objective_ids[0])
	)
	_benchmark(
		"get_objective_progress_by_key",
		ITERATIONS_SMALL,
		func() -> void:
			if _objective_ids.is_empty():
				return
			_controller.get_objective_manager().get_objective_progress_by_key(
				_objective_ids[0], &"wood"
			)
	)
	_benchmark(
		"get_objective_status",
		ITERATIONS_SMALL,
		func() -> void:
			if _objective_ids.is_empty():
				return
			_controller.get_objective_manager().get_objective_status(_objective_ids[0])
	)
	_benchmark(
		"get_quest_data",
		ITERATIONS_SMALL,
		func() -> void:
			if _quest_ids.is_empty():
				return
			_controller.get_quest_data_manager().get_quest_data(_quest_ids[0])
	)
	_benchmark(
		"get_active_quests",
		ITERATIONS_SMALL,
		func() -> void: _controller.get_quest_pool_manager().get_active_quests()
	)
	_benchmark(
		"_resolve_instance_file_id",
		ITERATIONS_LARGE,
		func() -> void:
			if _quest_ids.is_empty():
				return
			_controller._resolve_instance_file_id(_quest_ids[0])
	)
	print("\n=== Benchmark Complete ===\n")


func _prepare_test_data() -> void:
	_quest_ids.clear()
	_objective_ids.clear()
	var pool_mgr = _controller.get_quest_pool_manager()
	var data_mgr = _controller.get_quest_data_manager()
	var obj_mgr = _controller.get_objective_manager()
	for q in pool_mgr.get_active_quests():
		_quest_ids.append(q)
	for q in pool_mgr.get_available_quests():
		if not _quest_ids.has(q):
			_quest_ids.append(q)
	for q in pool_mgr.get_completed_quests():
		if not _quest_ids.has(q):
			_quest_ids.append(q)
	if _quest_ids.is_empty():
		var all_data = data_mgr.get_all_managed_quests_data()
		for d in all_data:
			var qid = d.get("id", &"")
			if not qid.is_empty():
				_quest_ids.append(qid)
				break
	var objectives = (
		obj_mgr.get_active_objectives_for_quest(_quest_ids[0]) if not _quest_ids.is_empty() else []
	)
	for obj in objectives:
		_objective_ids.append(obj.id)
	if _objective_ids.is_empty():
		_objective_ids.append(&"obj_1")


func _benchmark(name: String, iterations: int, op: Callable) -> void:
	var times: Array[int] = []
	times.resize(iterations)
	for i in range(iterations):
		var t0 = Time.get_ticks_usec()
		op.call()
		times[i] = Time.get_ticks_usec() - t0
	times.sort()
	var median = times[iterations / 2] if iterations > 0 else 0
	var p99_idx = int(iterations * 0.99)
	var p99 = times[p99_idx] if p99_idx < iterations else times[-1]
	print("%s,%d,%d,%d" % [name, iterations, median, p99])
