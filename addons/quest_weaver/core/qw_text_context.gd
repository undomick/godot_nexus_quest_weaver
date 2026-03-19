# res://addons/quest_weaver/core/qw_text_context.gd
class_name QWTextContext
extends RefCounted

## Acts as the execution base for text expressions.
## Allows writing things like "{item(0).name}" or "{val('gold')}" in quest texts.

var _global: Node
var _instance: QuestInstance
var _objective: ObjectiveResource
var _item_registry: Resource


func _init(p_global: Node, p_instance: QuestInstance, p_objective: ObjectiveResource = null):
	self._global = p_global
	self._instance = p_instance
	self._objective = p_objective

	# Load registry for name/icon lookup
	var settings = QWConstants.get_settings()
	if is_instance_valid(settings) and ResourceLoader.exists(settings.item_registry_path):
		_item_registry = ResourceLoader.load(settings.item_registry_path)


# ==============================================================================
# VIRTUAL PROPERTIES FOR EXPRESSIONS
# ==============================================================================


func _get(property: StringName) -> Variant:
	if property == &"rewards":
		return get_rewards()
	return null


# ==============================================================================
# API FOR USE IN TEXT PLACEHOLDERS
# ==============================================================================


## Returns the value of a variable (Local Instance > Global GameState).
## Usage: "{variable('my_var')}" or just "{my_var}" (handled by fallback)
func variable(key: StringName) -> Variant:
	if not is_instance_valid(_instance):
		return null
	if _instance.variables.has(key):
		return _instance.variables[key]
	if not is_instance_valid(_global):
		return null
	return _global.get_variable(key)


## Returns info about a requirement in the current objective by index (0, 1, 2...).
## Usage: "Collect {item(0).amount} {item(0).name}"
func item(index: int) -> Dictionary:
	return _get_entry_by_index(index)


## Alias for item() to be more generic.
func entry(index: int) -> Dictionary:
	return _get_entry_by_index(index)


## Access another quest to read its variables or state.
## Usage: "{quest('other_quest_id').is_completed()}"
func quest(quest_id: StringName) -> QuestProxy:
	if not is_instance_valid(_global):
		return QuestProxy.new(quest_id, null, false)
	return _global.quest_id(quest_id)


## Reference items of a specific objective (e.g. from another TaskNode).
## Usage: "{objective('collect_wood').item(0).name}" or "{objective('obj_1').item(0).amount}"
## Returns a proxy; use .item(index) to get id, amount, name, icon.
func objective(objective_id: StringName) -> ObjectiveTextProxy:
	var obj = _global.get_objective_resource(objective_id) if is_instance_valid(_global) else null
	return ObjectiveTextProxy.new(obj, _item_registry)


## Rewards of another quest (item_id -> amount). Same as quest(quest_id).get_rewards().
## Usage: "{rewards('other_quest_id').gold}" or use reward_at for name/amount by index.
func rewards(quest_id: StringName) -> Dictionary:
	if is_instance_valid(_global):
		return _global.get_quest_rewards(quest_id)
	return {}


## Amount of a specific reward item in another quest.
## Usage: "You get {reward_amount('main_quest', 'gold')} gold."
func reward_amount(quest_id: StringName, item_id: StringName) -> int:
	if is_instance_valid(_global):
		var rwd = _global.get_quest_rewards(quest_id)
		return rwd.get(item_id, 0)
	return 0


## One reward of another quest by index (0, 1, 2...). Returns id, amount, name, icon.
## Usage: "Reward: {reward_at('main_quest', 0).amount} x {reward_at('main_quest', 0).name}"
func reward_at(quest_id: StringName, index: int) -> Dictionary:
	if not is_instance_valid(_global):
		return _get_empty_entry_dict()
	var rwd_dict = _global.get_quest_rewards(quest_id)
	if rwd_dict.is_empty():
		return _get_empty_entry_dict()
	var keys = rwd_dict.keys()
	keys.sort()
	if index < 0 or index >= keys.size():
		return _get_empty_entry_dict()
	var entry_id = keys[index]
	var amount = rwd_dict[entry_id]
	var data = {"id": entry_id, "amount": amount, "name": str(entry_id).capitalize(), "icon": ""}
	if _item_registry and _item_registry.has_method("find"):
		var def = _item_registry.find(str(entry_id))
		if def:
			if "display_name" in def:
				data["name"] = def.display_name
			if "icon" in def and def.icon:
				data["icon"] = "[img=16x16]%s[/img]" % def.icon.resource_path
	return data


## Allow accessing rewards of the current quest instance in text
## Usage: "You get {rewards.gold} gold."
func get_rewards() -> Dictionary:
	if not is_instance_valid(_instance) or not is_instance_valid(_global):
		return {}
	# Resolve via Global/Controller using the instance's Quest ID
	var q_id = _instance.quest_id if _instance.quest_id != &"" else _instance.file_id
	return _global.get_quest_rewards(q_id)


# ==============================================================================
# HELPERS
# ==============================================================================


func _get_empty_entry_dict() -> Dictionary:
	return {"id": "???", "amount": 0, "name": "Unknown", "icon": ""}


func _get_entry_by_index(index: int) -> Dictionary:
	var fallback = _get_empty_entry_dict()

	if not _objective:
		return fallback
	if _objective.requirements.is_empty():
		return fallback

	# Sort keys to ensure stable indexing
	var keys = _objective.requirements.keys()
	keys.sort()  # Alphabetical sort by ID

	if index < 0 or index >= keys.size():
		return fallback

	var entry_id = keys[index]
	var amount = _objective.requirements[entry_id]

	var data = {"id": entry_id, "amount": amount, "name": str(entry_id).capitalize(), "icon": ""}  # Default name  # Default icon (empty string means none)

	# Enrich with Registry Data if available
	if _item_registry and _item_registry.has_method("find"):
		var def = _item_registry.find(str(entry_id))
		if def:
			if "display_name" in def:
				data["name"] = def.display_name
			if "icon" in def and def.icon:
				# Embed image for RichTextLabel
				data["icon"] = "[img=16x16]%s[/img]" % def.icon.resource_path

	return data
