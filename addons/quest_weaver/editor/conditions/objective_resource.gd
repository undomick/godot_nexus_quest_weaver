@tool

class_name ObjectiveResource

extends Resource

enum Status { INACTIVE, ACTIVE, COMPLETED, FAILED }

enum TriggerType { MANUAL, ITEM_COLLECT, LOCATION_ENTER, INTERACT, KILL }

@export var id: StringName

@export var trigger_type: TriggerType = TriggerType.MANUAL

# NEW: Stores targets and amounts. Format: { StringName(ID): int(Amount) }
# Used for ITEM_COLLECT and KILL.
@export var requirements: Dictionary = {}

# Legacy params for singular triggers (Location, Interact)
@export var trigger_params: Dictionary = {}

## For ITEM_COLLECT: only counts items collected since objective became active.
## For KILL: counts kills since objective became active.
@export var track_progress_since_activation: bool = true

# UI Hints
@export var show_counter: bool = true

@export var is_optional: bool = false

@export var is_hidden: bool = false

## If true: Objective is not completed when enough items are collected. Waits until GiveTakeItem reports enough items deposited.
@export var complete_on_delivery: bool = false

@export_multiline var description: String

# Runtime Properties
var status: int = 0

var owner_task_node_id: StringName = &""

var current_progress: Variant = 0


func _init():
	requirements = {}
	trigger_params = {}


func to_dictionary() -> Dictionary:
	return {
		"@script_path": get_script().resource_path,
		"id": self.id,
		"description": self.description,
		"trigger_type": self.trigger_type,
		"requirements": self.requirements.duplicate(),
		"trigger_params": self.trigger_params,
		"track_progress_since_activation": self.track_progress_since_activation,
		"show_counter": self.show_counter,
		"is_optional": self.is_optional,
		"is_hidden": self.is_hidden,
		"complete_on_delivery": self.complete_on_delivery
	}


func from_dictionary(data: Dictionary) -> void:
	self.id = StringName(data.get("id", &""))
	self.description = data.get("description", "")
	self.trigger_type = _defensive_load(
		data, "trigger_type", TriggerType.keys(), TriggerType.MANUAL
	)

	# Load Requirements with StringName Keys
	self.requirements = {}
	var raw_reqs = data.get("requirements", {})
	for key in raw_reqs:
		self.requirements[StringName(key)] = int(raw_reqs[key])

	# Fallback for migration (if old data exists):
	var old_params = data.get("trigger_params", {})
	var old_req_progress = data.get("required_progress", 1)

	if self.requirements.is_empty() and not old_params.is_empty():
		if self.trigger_type == TriggerType.ITEM_COLLECT and old_params.has("item_id"):
			self.requirements[StringName(old_params["item_id"])] = old_req_progress
		elif self.trigger_type == TriggerType.KILL and old_params.has("enemy_id"):
			self.requirements[StringName(old_params["enemy_id"])] = old_req_progress
		else:
			self.trigger_params = old_params
	else:
		self.trigger_params = old_params

	self.track_progress_since_activation = data.get("track_progress_since_activation", true)
	self.show_counter = data.get("show_counter", true)
	self.is_optional = data.get("is_optional", false)
	self.is_hidden = data.get("is_hidden", false)
	self.complete_on_delivery = data.get("complete_on_delivery", false)

	# Reset runtime vars
	self.status = 0
	self.current_progress = 0
	self.owner_task_node_id = &""


func _defensive_load(data: Dictionary, prop: String, keys: Array, default_val: int) -> int:
	var val = data.get(prop, default_val)
	if val is int and val >= 0 and val < keys.size():
		return val
	return default_val
