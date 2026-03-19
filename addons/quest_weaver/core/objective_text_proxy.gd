# res://addons/quest_weaver/core/objective_text_proxy.gd
class_name ObjectiveTextProxy
extends RefCounted

## Proxy for referencing items of a specific objective in text expressions.
## Use via QWTextContext.objective('objective_id').item(0) to get item data from another task.

var _objective: ObjectiveResource
var _item_registry: Resource


## Creates proxy for the given objective. item_registry used for display_name and icon lookup.
func _init(p_objective: ObjectiveResource, p_item_registry: Resource) -> void:
	_objective = p_objective
	_item_registry = p_item_registry


## Returns item data for the requirement at the given index (0, 1, 2...).
## Same structure as item() in QWTextContext: id, amount, name, icon.
func item(index: int) -> Dictionary:
	return _get_entry_by_index(index)


func _get_entry_by_index(index: int) -> Dictionary:
	var fallback = {"id": "???", "amount": 0, "name": "Unknown", "icon": ""}

	if not _objective:
		return fallback
	if _objective.requirements.is_empty():
		return fallback

	var keys = _objective.requirements.keys()
	keys.sort()

	if index < 0 or index >= keys.size():
		return fallback

	var id = keys[index]
	var amount = _objective.requirements[id]

	var data = {"id": id, "amount": amount, "name": str(id).capitalize(), "icon": ""}

	if _item_registry and _item_registry.has_method("find"):
		var def = _item_registry.find(str(id))
		if def:
			if "display_name" in def:
				data["name"] = def.display_name
			if "icon" in def and def.icon:
				data["icon"] = "[img=16x16]%s[/img]" % def.icon.resource_path

	return data
