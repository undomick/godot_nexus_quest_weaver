# res://addons/quest_weaver/core/quest_instance.gd
class_name QuestInstance

extends RefCounted

const EXPR_CACHE_MAX = 32

static var _resolver_regex: RegEx = null
static var _expr_cache: Dictionary = {}
static var _expr_cache_order: Array[String] = []

# The ID of the quest definition (e.g. "kill_rats_01")
var file_id: StringName = &""

# Logical ID from ContextNode (e.g. "main_heart_of_nestor")
var quest_id: StringName = &""

# Current status of the quest (ACTIVE, COMPLETED, FAILED, etc.)
# Uses QWEnums.QuestState
var current_status: int = 0

## True when the player explicitly rejected this quest (while it was AVAILABLE). Used for Quest Board filtering.
var rejected_by_player: bool = false

## When non-empty, the instance is in a custom pool (current_status = CUSTOM). Used for additional pools from settings.
var custom_pool_id: StringName = &""

# Local variables/parameters for this specific instance.
var variables: Dictionary = {}

# Tracks which nodes are currently "running" (e.g. Timers, EventListeners, TaskNodes).
# Key: NodeID (StringName) | Value: Meta Dictionary
var active_node_ids: Dictionary = {}

# Stores the internal state of specific nodes.
# Key: NodeID (StringName)
var node_states: Dictionary = {}

# Stores the progress of objectives (e.g. "already deposited" for GiveTakeItem partial deposit).
# Key: ObjectiveID (StringName). Value: { "status": int, "progress": int|Dictionary } (progress by item key).
# Persists only via game save (save_to_data/load_from_data). Editor "Save Quest" only saves the graph, not runtime state.
# Use get_objective_progress_by_key / set_objective_progress_by_key for progress; avoid direct key access for portability.
var objective_states: Dictionary = {}

## Represents a running instance of a Quest.
## Holds the runtime state (variables, node progress, objective status)
## separate from the static definition (QuestGraphResource).

# --- PERSISTENT STATE (Saved to disk) ---

# --- INITIALIZATION ---


func _init(p_file_id: StringName) -> void:
	self.file_id = p_file_id
	self.current_status = QWEnums.QuestState.UNAVAILABLE


# --- NODE STATE MANAGEMENT ---

## Marks a node as active (e.g. Timer, EventListener) with optional meta.


func set_node_active(node_id: StringName, is_active: bool, meta: Dictionary = {}) -> void:
	if is_active:
		active_node_ids[node_id] = meta
	else:
		active_node_ids.erase(node_id)


func is_node_active(node_id: StringName) -> bool:
	return active_node_ids.has(node_id)


func set_node_data(node_id: StringName, key: StringName, value: Variant) -> void:
	if not node_states.has(node_id):
		node_states[node_id] = {}
	node_states[node_id][key] = value


## Gets stored data for a node by key.
func get_node_data(node_id: StringName, key: StringName, default: Variant = null) -> Variant:
	if node_states.has(node_id):
		return node_states[node_id].get(key, default)
	return default


func clear_node_state(node_id: StringName) -> void:
	node_states.erase(node_id)
	active_node_ids.erase(node_id)


# --- OBJECTIVE STATE MANAGEMENT ---


func _get_objective_state_by_id(objective_id: StringName):
	if objective_states.has(objective_id):
		return objective_states[objective_id]
	var id_str = str(objective_id)
	for k in objective_states:
		if str(k) == id_str:
			return objective_states[k]
	return null


func _get_or_create_objective_state(objective_id: StringName):
	var existing = _get_objective_state_by_id(objective_id)
	if existing != null:
		return existing
	var key_n = StringName(objective_id)
	objective_states[key_n] = {"status": ObjectiveResource.Status.ACTIVE, "progress": {}}
	return objective_states[key_n]


## Returns the status of an objective (ObjectiveResource.Status).
func get_objective_status(objective_id: StringName) -> int:
	if objective_states.has(objective_id):
		return objective_states[objective_id].get("status", ObjectiveResource.Status.INACTIVE)
	return ObjectiveResource.Status.INACTIVE


## Sets the status of an objective.
func set_objective_status(objective_id: StringName, status: int) -> void:
	if not objective_states.has(objective_id):
		objective_states[objective_id] = {
			"status": ObjectiveResource.Status.INACTIVE, "progress": 0
		}
	objective_states[objective_id]["status"] = status


## Returns the TOTAL progress sum (simple int) or 0.
## For detailed checks, use get_objective_progress_by_key.
func get_objective_progress(objective_id: StringName) -> int:
	if objective_states.has(objective_id):
		var p = objective_states[objective_id].get("progress", 0)
		# If it's a dictionary (Multi-Target), return the sum of all values
		if p is Dictionary:
			var total = 0
			for val in p.values():
				total += int(val)
			return total
		return int(p)
	return 0


## Returns progress for a specific target (e.g. amount of "wood" collected).
## Matches keys by string value so stored progress is found regardless of String vs StringName.
func get_objective_progress_by_key(objective_id: StringName, target_key: StringName) -> int:
	var state = _get_objective_state_by_id(objective_id)
	if state == null:
		return 0
	var p = state.get("progress", 0)
	if not p is Dictionary:
		return int(p)
	var target_str = str(target_key)
	for k in p:
		if str(k) == target_str:
			return int(p[k])
	return 0


## Updates progress for a specific target.
## Uses a single key (StringName) and clears any duplicate key with same string value so get finds it.
func set_objective_progress_by_key(
	objective_id: StringName, target_key: StringName, value: int
) -> void:
	var state = _get_or_create_objective_state(objective_id)
	var prog = state.get("progress")
	if not prog is Dictionary:
		prog = {}
		state["progress"] = prog
	var target_str = str(target_key)
	var key_to_remove = null
	for k in prog:
		if str(k) == target_str:
			key_to_remove = k
			break
	if key_to_remove != null:
		prog.erase(key_to_remove)
	prog[StringName(target_key)] = value
	state["status"] = ObjectiveResource.Status.ACTIVE


## Sets the total progress for an objective (simple int).
func set_objective_progress(objective_id: StringName, value: int) -> void:
	if not objective_states.has(objective_id):
		objective_states[objective_id] = {"status": ObjectiveResource.Status.ACTIVE, "progress": 0}
	objective_states[objective_id]["progress"] = value


## Sets a runtime description override for an objective.
func set_objective_description_override(objective_id: StringName, text: String) -> void:
	if not objective_states.has(objective_id):
		objective_states[objective_id] = {
			"status": ObjectiveResource.Status.INACTIVE, "progress": 0
		}
	objective_states[objective_id]["description_override"] = text


## Returns the description override if set, otherwise the default blueprint text.
func get_objective_description(objective_id: StringName, default_blueprint_text: String) -> String:
	if objective_states.has(objective_id):
		var override = objective_states[objective_id].get("description_override", "")
		if not override.is_empty():
			return override
	return default_blueprint_text


# --- VARIABLE / PARAMETER MANAGEMENT ---

## Sets a variable for this instance.


func set_variable(key: StringName, value: Variant) -> void:
	variables[key] = value


## Gets a variable from this instance.
func get_variable(key: StringName, default: Variant = null) -> Variant:
	return variables.get(key, default)


## Replaces placeholders. Supports variables "{my_var}" and Expressions "{item(0).amount}".
## Provide 'context_obj' (ObjectiveResource) to allow accessing specific objective data.
func resolve_text(text: String, context_obj: Resource = null) -> String:
	if text.is_empty() or not "{" in text:
		return text

	if _resolver_regex == null:
		_resolver_regex = RegEx.new()
		_resolver_regex.compile("\\{(.*?)\\}")

	# 1. Prepare Context
	var main_loop = Engine.get_main_loop()
	if not main_loop or not main_loop.root:
		return text
	var global_qw = main_loop.root.get_node_or_null("QuestWeaverGlobal")
	var context_wrapper = QWTextContext.new(global_qw, self, context_obj)

	var result = text
	var matches = _resolver_regex.search_all(text)

	# Iterate matches in reverse to handle replacement without messing up indices,
	# OR just replace strings. Since we replace unique full strings, simple replace is fine
	# unless identical placeholders exist (which resolves same anyway).

	for regex_match in matches:
		var full_placeholder = regex_match.get_string(0)  # "{...}"
		var content = regex_match.get_string(1).strip_edges()  # "..."

		var replacement_value = full_placeholder  # Default: Keep original if fail

		# Fast path: Simple variable (no ., (, [, space) - avoid Expression entirely
		var is_simple_var = (
			not content.contains(".")
			and not content.contains("(")
			and not content.contains("[")
			and not content.contains(" ")
		)
		if is_simple_var:
			var simple_lookup = get_variable(content, null)
			if simple_lookup == null and global_qw:
				simple_lookup = global_qw.get_variable(content, null)
			if simple_lookup != null:
				replacement_value = str(simple_lookup)
		else:
			# Expression path: use cached Expression to avoid repeated parse()
			var expr: Expression = _expr_cache.get(content)
			if expr == null:
				expr = Expression.new()
				var parse_err = expr.parse(content)
				if parse_err == OK:
					_expr_cache[content] = expr
					_expr_cache_order.append(content)
					if _expr_cache_order.size() > EXPR_CACHE_MAX:
						var evict_key = _expr_cache_order.pop_front()
						_expr_cache.erase(evict_key)
				else:
					# Parse failed - try simple lookup as fallback
					var simple_lookup = get_variable(content, null)
					if simple_lookup == null and global_qw:
						simple_lookup = global_qw.get_variable(content, null)
					if simple_lookup != null:
						replacement_value = str(simple_lookup)
					expr = null

			if expr != null:
				var exec_result = expr.execute([], context_wrapper, true)
				if not expr.has_execute_failed():
					replacement_value = str(exec_result)
				else:
					# Execute failed (e.g. variable name) - fallback to simple lookup
					var simple_lookup = get_variable(content, null)
					if simple_lookup == null and global_qw:
						simple_lookup = global_qw.get_variable(content, null)
					if simple_lookup != null:
						replacement_value = str(simple_lookup)

		# Apply replacement
		if replacement_value != full_placeholder:
			result = result.replace(full_placeholder, replacement_value)

	return result


# --- REWARD FORMATTING HELPERS ---


func _get_local_rewards_string(index: int, global_qw: Node) -> String:
	# "Local" means defined in THIS quest's ContextNode.
	# We fetch it via Global because ContextNode is static data in Controller, not in Instance.
	if not global_qw:
		return ""
	# Try Logical ID first, then File ID
	var q_id = quest_id if quest_id != &"" else file_id
	var dict = global_qw.get_quest_rewards(q_id)
	return _format_rewards_dict(dict, index)


func _get_remote_rewards_string(target_quest_id: StringName, index: int, global_qw: Node) -> String:
	if not global_qw:
		return ""
	var dict = global_qw.get_quest_rewards(target_quest_id)
	return _format_rewards_dict(dict, index)


func _format_rewards_dict(dict: Dictionary, index: int) -> String:
	if dict.is_empty():
		return ""

	# 1. Sort Keys (Alphabetical) to match Editor view
	var keys = dict.keys()
	keys.sort_custom(func(a, b): return str(a) < str(b))

	# 2. Case: Index Access
	if index >= 0:
		if index < keys.size():
			var key = keys[index]
			var val = dict[key]
			return _format_single_reward(key, val)
		else:
			return ""  # Index out of bounds -> empty string

	# 3. Case: Full List
	var list_strings: PackedStringArray = []
	for key in keys:
		list_strings.append(_format_single_reward(key, dict[key]))

	# Join with commas (e.g. "100 Gold, 1 Sword")
	return ", ".join(list_strings)


func _format_single_reward(key: Variant, val: Variant) -> String:
	# Heuristic:
	# If Value is 1, maybe just show Key? -> "Sword" instead of "1 Sword"
	# Or always "Amount Key"? -> "1 Sword". Let's stick to "Amount Key" for consistency.
	# But if key is "Gold" and val is 100 -> "100 Gold".
	return "%s %s" % [str(val), str(key)]


## Resolves a parameter value.
## If input is a String looking like "{var_name}", it returns the variable value.
## Otherwise returns the input as-is.
func resolve_parameter(input: Variant) -> Variant:
	if input is String:
		if input.begins_with("{") and input.ends_with("}"):
			var key = input.substr(1, input.length() - 2)
			return get_variable(key, input)  # Fallback to input string if var missing
	return input


# --- SERIALIZATION ---

## Emits a save dict with string-only keys for objective_states so JSON/store_var round-trip is stable.


func get_save_data() -> Dictionary:
	var objective_states_serializable: Dictionary = {}
	for obj_key in objective_states:
		var state = objective_states[obj_key]
		var out_state = {"status": state.get("status", ObjectiveResource.Status.INACTIVE)}
		var prog = state.get("progress")
		if prog is Dictionary:
			var prog_str_keys = {}
			for pkey in prog:
				prog_str_keys[str(pkey)] = prog[pkey]
			out_state["progress"] = prog_str_keys
		else:
			out_state["progress"] = prog
		objective_states_serializable[str(obj_key)] = out_state
	return {
		"file_id": file_id,
		"quest_id": quest_id,
		"status": current_status,
		"custom_pool_id": custom_pool_id,
		"rejected_by_player": rejected_by_player,
		"variables": variables.duplicate(),
		"active_node_ids": active_node_ids.duplicate(),
		"node_states": node_states.duplicate(true),
		"objective_states": objective_states_serializable
	}


## Restores instance state from a previously saved dictionary.
func load_save_data(data: Dictionary) -> void:
	if data == null:
		push_warning("QuestInstance: load_save_data called with null.")
		return
	self.file_id = StringName(data.get("file_id", &""))
	self.quest_id = StringName(data.get("quest_id", &""))
	self.current_status = int(data.get("status", QWEnums.QuestState.UNAVAILABLE))
	self.custom_pool_id = StringName(data.get("custom_pool_id", &""))
	self.rejected_by_player = data.get("rejected_by_player", false)
	self.variables = data.get("variables", {}).duplicate()

	self.active_node_ids = {}
	var loaded_active = data.get("active_node_ids", {})
	for k in loaded_active:
		self.active_node_ids[StringName(k)] = loaded_active[k]

	self.node_states = {}
	var loaded_states = data.get("node_states", {})
	for k in loaded_states:
		self.node_states[StringName(k)] = loaded_states[k].duplicate(true)

	self.objective_states = {}
	var loaded_objs = data.get("objective_states", {})
	for k in loaded_objs:
		var state_copy = loaded_objs[k].duplicate(true)
		# Normalize progress dict keys to StringName so get_objective_progress_by_key finds them
		var prog = state_copy.get("progress")
		if prog is Dictionary:
			var normalized = {}
			for pkey in prog:
				normalized[StringName(pkey)] = prog[pkey]
			state_copy["progress"] = normalized
		self.objective_states[StringName(k)] = state_copy
