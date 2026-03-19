# res://addons/quest_weaver/nodes/logic/quest_context_node/quest_context_node_resource.gd
@tool

class_name QuestContextNodeResource

extends GraphNodeResource

## Defines whether this is a Main or Side quest.
enum QuestType { MAIN, SIDE }

@export var quest_type: QuestType = QuestType.SIDE

## Unique identifier for this quest.
@export var quest_id: StringName = &""

## The title displayed to the player.
@export var quest_title: String = ""

# CHANGED: Now an Array of Dictionaries.
# Format: { "id": StringName, "amount": int, "linked_objective_id": StringName, "description": String }
@export var rewards: Array[Dictionary] = []

## The initial description of the quest.
@export_multiline var quest_description: String = ""

## (Optional) An initial log entry added when the quest starts.
@export_multiline var log_on_start: String = ""


func _init() -> void:
	category = "Logic"
	input_ports = ["In"]
	output_ports = ["Out"]


func get_editor_summary() -> String:
	if quest_id.is_empty():
		return "!! NO QUEST ID SET !!"

	var type_text = "Main" if quest_type == QuestType.MAIN else "Side"

	var reward_text = ""
	if not rewards.is_empty():
		reward_text = "\n(%d Rewards)" % rewards.size()

	return "\nID: %s\n%s Quest:\n%s%s" % [quest_id, type_text, quest_title, reward_text]


func get_description() -> String:
	return "Defines the core properties of this quest (ID, Title, Description, Rewards)."


func get_icon() -> Texture2D:
	return preload("res://addons/quest_weaver/assets/icons/context.svg")


## Reward editing is done via AddRewardCommand / RemoveRewardCommand in the editor.
## The qw_action_handler uses these commands; do not add direct mutators here.

# --- SERIALIZATION ---


func to_dictionary() -> Dictionary:
	var data = super.to_dictionary()
	data["quest_type"] = self.quest_type
	data["quest_id"] = self.quest_id
	data["quest_title"] = self.quest_title
	data["quest_description"] = self.quest_description
	data["log_on_start"] = self.log_on_start
	data["rewards"] = self.rewards.duplicate(true)

	return data


func from_dictionary(data: Dictionary):
	if not data is Dictionary:
		push_error("QuestContextNodeResource: from_dictionary requires a valid Dictionary.")
		return
	super.from_dictionary(data)
	self.quest_type = _defensive_load(data, "quest_type", QuestType.keys(), QuestType.SIDE)
	self.quest_id = StringName(data.get("quest_id", &""))
	self.quest_title = data.get("quest_title", "")
	self.quest_description = data.get("quest_description", "")
	self.log_on_start = data.get("log_on_start", "")

	self.rewards.clear()

	# Load dictionaries and ensure types (String -> StringName conversion for IDs)
	var raw_rewards = data.get("rewards", [])
	if raw_rewards is Array:
		for r in raw_rewards:
			if r is Dictionary:
				# Sanitize / Cast types upon loading
				var clean_reward = {
					"id": StringName(r.get("id", &"gold")),
					"amount": int(r.get("amount", 100)),
					"linked_objective_id": StringName(r.get("linked_objective_id", &"")),
					"description": str(r.get("description", ""))
				}
				self.rewards.append(clean_reward)

	# Migration Fallback (Old logic)
	elif data.has("rewards_summary"):
		var old_dict = data.get("rewards_summary", {})
		if old_dict is Dictionary:
			for k in old_dict:
				self.rewards.append(
					{
						"id": StringName(k),
						"amount": int(old_dict[k]),
						"linked_objective_id": &"",
						"description": ""
					}
				)


## PRIVATE METHOD: Checks if an integer value is valid for the enum type.
func _defensive_load(data: Dictionary, prop: String, keys: Array, default_val: int) -> int:
	var val = data.get(prop, default_val)
	if val is int and val >= 0 and val < keys.size():
		return val
	return default_val


func _validate(context: Dictionary) -> Array[ValidationResult]:
	var results: Array[ValidationResult] = []
	var item_registry = context.get("item_registry")

	# 1. Check ID
	if quest_id.is_empty():
		results.append(
			ValidationResult.new(
				ValidationResult.Severity.ERROR, "Quest Context: Quest ID is not set.", id
			)
		)

	# 2. Check Rewards
	if not rewards.is_empty() and is_instance_valid(item_registry):
		# Helper to check existence based on Registry type
		var check_item_exists = func(item_id: String) -> bool:
			if item_registry.has_method("find"):
				return item_registry.find(item_id) != null
			if "item_definitions" in item_registry:
				# Fallback for simple array based registries
				for def in item_registry.item_definitions:
					if def.id == item_id:
						return true
			return false

		for i in range(rewards.size()):
			var reward = rewards[i]
			if reward is Dictionary:
				var r_id = str(reward.get("id", ""))
				if r_id.is_empty():
					results.append(
						ValidationResult.new(
							ValidationResult.Severity.ERROR,
							"Reward #%d: Item ID is missing." % (i + 1),
							id
						)
					)
				elif not check_item_exists.call(r_id):
					results.append(
						ValidationResult.new(
							ValidationResult.Severity.WARNING,
							"Reward #%d: Item '%s' not found in Registry." % [i + 1, r_id],
							id
						)
					)

	return results


func determine_default_size() -> QWNodeSizes.Size:
	return QWNodeSizes.Size.LARGE
