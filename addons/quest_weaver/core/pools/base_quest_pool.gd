# res://addons/quest_weaver/core/pools/base_quest_pool.gd
class_name BaseQuestPool
extends RefCounted

## Base class for quest instance pools.
## Holds QuestInstance references keyed by file_id for O(1) lookup within the pool.

var _instances: Dictionary = {}  # file_id (StringName) -> QuestInstance


func add_instance(instance: QuestInstance) -> void:
	if not is_instance_valid(instance) or instance.file_id == &"":
		push_error("BaseQuestPool: Cannot add invalid instance or instance with empty file_id.")
		return
	if _instances.has(instance.file_id):
		push_warning(
			"BaseQuestPool: Overwriting existing instance for file_id '%s'." % instance.file_id
		)
	_instances[instance.file_id] = instance


func remove_instance(file_id: StringName) -> QuestInstance:
	if _instances.has(file_id):
		var instance = _instances[file_id]
		_instances.erase(file_id)
		return instance
	return null


func get_instance(file_id: StringName) -> QuestInstance:
	return _instances.get(file_id) as QuestInstance


func get_all_instances() -> Array[QuestInstance]:
	var result: Array[QuestInstance] = []
	for inst in _instances.values():
		if is_instance_valid(inst):
			result.append(inst)
	return result


func get_instance_count() -> int:
	return _instances.size()


func get_all_file_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for fid in _instances.keys():
		result.append(fid)
	return result


func is_instance_inside(file_id: StringName) -> bool:
	return _instances.has(file_id)


func clear() -> void:
	_instances.clear()
