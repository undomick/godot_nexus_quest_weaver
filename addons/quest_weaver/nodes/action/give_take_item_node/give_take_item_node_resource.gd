# res://addons/quest_weaver/nodes/action/give_take_item_node/give_take_item_node_resource.gd
@tool
class_name GiveTakeItemNodeResource
extends GraphNodeResource

enum Action { GIVE, TAKE, REWARD_FROM_QUEST, ITEMS_FROM_OBJECTIVE }

@export var action: Action = Action.GIVE

## For GIVE/TAKE: A dictionary of items { ItemID (StringName): Amount (int) }
@export var items: Dictionary = {}

## For REWARD_FROM_QUEST: The ID of the quest to fetch rewards from.
@export var target_quest_id: StringName = &""

# For ITEMS_FROM_OBJECTIVE
@export var target_objective_id: StringName = &""
# Allows taking less than required if player has only some items
@export var allow_partial_deposit: bool = false
# When Success output triggers, automatically mark the target objective as COMPLETED
@export var complete_objective_on_success: bool = false


func _init() -> void:
	category = &"Action"
	input_ports = [&"In"]
	_update_ports_from_data()


func _update_ports_from_data() -> void:
	if is_terminal:
		output_ports = []
	elif allow_partial_deposit and (action == Action.TAKE or action == Action.ITEMS_FROM_OBJECTIVE):
		output_ports = [&"Success", &"Partial", &"Failure"]
	else:
		output_ports = [&"Success", &"Failure"]


func get_editor_summary() -> String:
	var action_text = Action.keys()[action].capitalize()
	var info_text = ""

	if action == Action.REWARD_FROM_QUEST:
		if target_quest_id == &"":
			info_text = "[WARN](No Quest Target)"
		else:
			info_text = "from '%s'" % target_quest_id
	elif action == Action.ITEMS_FROM_OBJECTIVE:
		return "Deposit for:\n'%s'" % target_objective_id
	else:
		if items.is_empty():
			info_text = "(Empty List)"
		elif items.size() == 1:
			var key = items.keys()[0]
			info_text = "%d x %s" % [items[key], key]
		else:
			info_text = "%d Items..." % items.size()

	return "%s:\n%s" % [action_text, info_text]


func get_description() -> String:
	return "Adds/removes multiple items or distributes rewards defined in another quest's Context Node."


func get_icon() -> Texture2D:
	return preload("res://addons/quest_weaver/assets/icons/give_take.svg")


func to_dictionary() -> Dictionary:
	var data = super.to_dictionary()
	data["action"] = self.action
	# Dictionary needs duplication to be safe
	data["items"] = self.items.duplicate()
	data["target_quest_id"] = self.target_quest_id
	data["target_objective_id"] = self.target_objective_id
	data["allow_partial_deposit"] = self.allow_partial_deposit
	data["complete_objective_on_success"] = self.complete_objective_on_success
	return data


func from_dictionary(data: Dictionary):
	super.from_dictionary(data)
	self.action = _defensive_load(data, "action", Action.keys(), Action.GIVE)
	self.target_quest_id = StringName(data.get("target_quest_id", &""))
	self.target_objective_id = StringName(data.get("target_objective_id", &""))
	self.allow_partial_deposit = data.get("allow_partial_deposit", false)
	self.complete_objective_on_success = data.get("complete_objective_on_success", false)
	# Load Dictionary ensuring StringName keys and int values (defensive conversion for corrupt data)
	self.items.clear()
	var raw_items = data.get("items", {})
	if raw_items is Dictionary:
		for key in raw_items:
			var v = raw_items.get(key, 0)
			var amount = 0
			if v is int:
				amount = v
			elif v is float:
				amount = int(v)
			elif str(v).is_valid_int():
				amount = int(str(v))
			self.items[StringName(key)] = amount

	_update_ports_from_data()


func _validate(_context: Dictionary) -> Array[ValidationResult]:
	var results: Array[ValidationResult] = []

	match action:
		Action.REWARD_FROM_QUEST:
			if target_quest_id.is_empty():
				results.append(
					ValidationResult.new(
						ValidationResult.Severity.ERROR, "Reward: No Target Quest ID specified.", id
					)
				)

		Action.ITEMS_FROM_OBJECTIVE:
			if target_objective_id.is_empty():
				results.append(
					ValidationResult.new(
						ValidationResult.Severity.ERROR,
						"Items From Objective: No Target Objective ID specified.",
						id
					)
				)

		Action.GIVE, Action.TAKE:
			if items.is_empty():
				results.append(
					ValidationResult.new(
						ValidationResult.Severity.WARNING, "Give/Take: Item list is empty.", id
					)
				)

	return results


func _defensive_load(data: Dictionary, prop: String, keys: Array, default_val: int) -> int:
	var val = data.get(prop, default_val)
	if val is int and val >= 0 and val < keys.size():
		return val
	return default_val
