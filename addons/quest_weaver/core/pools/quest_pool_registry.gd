# res://addons/quest_weaver/core/pools/quest_pool_registry.gd
class_name QuestPoolRegistry
extends RefCounted

## Manages the five predefined quest state pools plus optional additional pools.
## Each QuestInstance exists in exactly one pool at a time.
## Additional pools are loaded from QuestWeaverSettings.additional_pool_scripts.

var _unavailable: BaseQuestPool
var _available: BaseQuestPool
var _active: BaseQuestPool
var _completed: BaseQuestPool
var _failed: BaseQuestPool

# Custom pools: pool_id (StringName) -> BaseQuestPool
var _additional_pools: Dictionary = {}

# O(1) lookup: file_id -> QuestInstance. Updated on add/move.
var _instance_by_file_id: Dictionary = {}

# Mapping state -> pool for move_instance_to_pool
var _pools_by_state: Dictionary = {}

# All pools (core + additional) for iteration
var _all_pools: Array[BaseQuestPool] = []


func _init() -> void:
	_unavailable = BaseQuestPool.new()
	_available = BaseQuestPool.new()
	_active = BaseQuestPool.new()
	_completed = BaseQuestPool.new()
	_failed = BaseQuestPool.new()

	_pools_by_state[QWEnums.QuestState.UNAVAILABLE] = _unavailable
	_pools_by_state[QWEnums.QuestState.AVAILABLE] = _available
	_pools_by_state[QWEnums.QuestState.ACTIVE] = _active
	_pools_by_state[QWEnums.QuestState.COMPLETED] = _completed
	_pools_by_state[QWEnums.QuestState.FAILED] = _failed

	_all_pools = [_unavailable, _available, _active, _completed, _failed]

	_load_additional_pools()


func _load_additional_pools() -> void:
	var settings = QWConstants.get_settings()
	if not is_instance_valid(settings):
		return
	if not settings.additional_pool_scripts is Array:
		return

	for path_or_uid in settings.additional_pool_scripts:
		if not path_or_uid is String or path_or_uid.is_empty():
			continue
		var path = _resolve_path_or_uid(path_or_uid)
		if path.is_empty():
			push_warning("QuestPoolRegistry: Could not resolve pool script: %s" % path_or_uid)
			continue
		if not ResourceLoader.exists(path):
			push_warning("QuestPoolRegistry: Additional pool script not found: %s" % path)
			continue
		var script = (
			ResourceLoader.load(path, "GDScript", ResourceLoader.CACHE_MODE_REPLACE) as GDScript
		)
		if not script:
			push_warning("QuestPoolRegistry: Could not load script as GDScript: %s" % path)
			continue
		var pool = script.new()
		if not pool is BaseQuestPool:
			push_warning("QuestPoolRegistry: Script does not extend BaseQuestPool: %s" % path)
			continue
		var pool_id = StringName(path.get_file().get_basename())
		if _additional_pools.has(pool_id):
			push_warning("QuestPoolRegistry: Duplicate pool ID '%s'. Skipping." % pool_id)
			continue
		_additional_pools[pool_id] = pool
		_all_pools.append(pool)


func _resolve_path_or_uid(path_or_uid: String) -> String:
	if path_or_uid.begins_with("uid://"):
		var id = ResourceUID.text_to_id(path_or_uid)
		if id != ResourceUID.INVALID_ID and ResourceUID.has_id(id):
			return ResourceUID.get_id_path(id)
		return ""
	return path_or_uid


func add_new_pool(pool_id: StringName, pool: BaseQuestPool) -> void:
	if pool_id == &"":
		push_error("QuestPoolRegistry: Cannot add pool with empty ID.")
		return
	if not is_instance_valid(pool):
		push_error("QuestPoolRegistry: Cannot add invalid pool.")
		return
	if _additional_pools.has(pool_id):
		push_warning("QuestPoolRegistry: Pool '%s' already exists. Replacing." % pool_id)
		_all_pools.erase(_additional_pools[pool_id])
	_additional_pools[pool_id] = pool
	_all_pools.append(pool)


func get_pool_for_state(state: int) -> BaseQuestPool:
	return _pools_by_state.get(state, _unavailable)


func get_pool_by_id(pool_id: StringName) -> BaseQuestPool:
	return _additional_pools.get(pool_id) as BaseQuestPool


func get_all_pool_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for pid in _additional_pools.keys():
		result.append(pid)
	return result


func move_instance_to_pool(instance: QuestInstance, target_state: int) -> void:
	if not is_instance_valid(instance) or instance.file_id == &"":
		push_error(
			"QuestPoolRegistry: Cannot move invalid instance or instance with empty file_id."
		)
		return
	if not _pools_by_state.has(target_state):
		push_error("QuestPoolRegistry: Invalid target state %d." % target_state)
		return

	_transfer_instance_to_pool(instance, _pools_by_state[target_state], target_state, &"")


func move_instance_to_custom_pool(instance: QuestInstance, pool_id: StringName) -> void:
	if not is_instance_valid(instance) or instance.file_id == &"":
		push_error(
			"QuestPoolRegistry: Cannot move invalid instance or instance with empty file_id."
		)
		return
	var target_pool = get_pool_by_id(pool_id)
	if not target_pool:
		push_error("QuestPoolRegistry: Unknown custom pool '%s'." % pool_id)
		return

	_transfer_instance_to_pool(instance, target_pool, QWEnums.QuestState.CUSTOM, pool_id)


func _transfer_instance_to_pool(
	instance: QuestInstance,
	target_pool: BaseQuestPool,
	target_status: int,
	custom_pool_id: StringName
) -> void:
	var file_id: StringName = instance.file_id
	_remove_from_any_pool(file_id)
	target_pool.add_instance(instance)
	instance.current_status = target_status
	instance.custom_pool_id = custom_pool_id
	_instance_by_file_id[file_id] = instance


func _remove_from_any_pool(file_id: StringName) -> void:
	for pool in _all_pools:
		if pool.is_instance_inside(file_id):
			pool.remove_instance(file_id)
			return


func add_instance_to_pool(instance: QuestInstance, target_state: int) -> void:
	if not is_instance_valid(instance) or instance.file_id == &"":
		push_error("QuestPoolRegistry: Cannot add invalid instance or instance with empty file_id.")
		return
	if not _pools_by_state.has(target_state):
		push_error("QuestPoolRegistry: Invalid target state %d." % target_state)
		return

	_transfer_instance_to_pool(instance, _pools_by_state[target_state], target_state, &"")


func add_instance_to_custom_pool(instance: QuestInstance, pool_id: StringName) -> void:
	if not is_instance_valid(instance) or instance.file_id == &"":
		push_error("QuestPoolRegistry: Cannot add invalid instance or instance with empty file_id.")
		return
	var target_pool = get_pool_by_id(pool_id)
	if not target_pool:
		push_error("QuestPoolRegistry: Unknown custom pool '%s'." % pool_id)
		return

	_transfer_instance_to_pool(instance, target_pool, QWEnums.QuestState.CUSTOM, pool_id)


func remove_instance_from_all_pools(file_id: StringName) -> QuestInstance:
	if file_id == &"":
		return null

	for pool in _all_pools:
		if pool.is_instance_inside(file_id):
			var instance = pool.remove_instance(file_id)
			_instance_by_file_id.erase(file_id)
			if instance:
				instance.custom_pool_id = &""
			return instance
	return null


func get_instance_by_file_id(file_id: StringName) -> QuestInstance:
	return _instance_by_file_id.get(file_id) as QuestInstance


func get_all_instances() -> Array[QuestInstance]:
	var result: Array[QuestInstance] = []
	for inst in _instance_by_file_id.values():
		if is_instance_valid(inst):
			result.append(inst)
	return result


func get_instance_count() -> int:
	return _instance_by_file_id.size()


## Returns quest IDs in a custom pool. Core states use get_pool_for_state instead.
func get_quests_in_pool(pool_id: StringName) -> Array[StringName]:
	var pool = get_pool_by_id(pool_id)
	if not pool:
		return []
	var result: Array[StringName] = []
	for inst in pool.get_all_instances():
		var sig_id = inst.quest_id if not inst.quest_id.is_empty() else inst.file_id
		result.append(sig_id)
	return result


func has_instance(file_id: StringName) -> bool:
	return _instance_by_file_id.has(file_id)


func pool_state_as_dict() -> Dictionary:
	var result = {
		"unavailable": _unavailable.get_all_file_ids(),
		"available": _available.get_all_file_ids(),
		"active": _active.get_all_file_ids(),
		"completed": _completed.get_all_file_ids(),
		"failed": _failed.get_all_file_ids()
	}
	for pool_id in _additional_pools:
		var pool: BaseQuestPool = _additional_pools[pool_id]
		result[str(pool_id)] = pool.get_all_file_ids()
	return result


func clear_all() -> void:
	_unavailable.clear()
	_available.clear()
	_active.clear()
	_completed.clear()
	_failed.clear()
	for pool in _additional_pools.values():
		pool.clear()
	_instance_by_file_id.clear()
