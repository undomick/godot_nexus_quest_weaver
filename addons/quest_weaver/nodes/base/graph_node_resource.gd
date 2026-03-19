@tool

class_name GraphNodeResource

extends Resource

## Static cache for scripts loaded in from_dictionary(). Key: script_path -> Script.
static var _script_cache: Dictionary = {}

@export var id: StringName

@export var category: StringName = &"Default"

@export var graph_position: Vector2

@export var input_ports: Array[StringName] = [&"In"]

@export var output_ports: Array[StringName] = [&"Out"]

@export var is_terminal: bool = false  # disables output


## Provides a brief, human-readable summary for display in the graph editor.
func get_editor_summary() -> String:
	return ""


## Returns a short description of what this node does.
## Used for tooltips in the Add Node menu.
func get_description() -> String:
	return "No description available."


## Returns an icon for the menu and graph header.
## By default, it tries to load an SVG with the same name as the script
## from an 'icons' subfolder (Convention over Configuration).
func get_icon() -> Texture2D:
	return null


func to_dictionary() -> Dictionary:
	return {
		"@script_path": get_script().resource_path,
		"id": id,
		"category": category,
		"graph_position": graph_position,
		"input_ports": input_ports,
		"output_ports": output_ports,
		"is_terminal": is_terminal
	}


func from_dictionary(data: Dictionary):
	self.id = StringName(data.get("id", &""))
	self.category = StringName(data.get("category", &"Default"))
	self.graph_position = _safe_vector2(data, "graph_position", Vector2.ZERO)
	self.is_terminal = _safe_bool(data, "is_terminal", false)

	# Array Conversion
	self.input_ports.clear()
	var inp = data.get("input_ports", [])
	if inp is Array:
		for p in inp:
			self.input_ports.append(StringName(p))
	self.output_ports.clear()
	var outp = data.get("output_ports", [])
	if outp is Array:
		for p in outp:
			self.output_ports.append(StringName(p))


## Virtual method for validation.
## 'context' contains references to 'item_registry' and 'quest_registry'.
## Override this in specific node resources to add custom checks.
func _validate(_context: Dictionary) -> Array[ValidationResult]:
	return []  # By default, a node is considered valid.


## Returns the name displayed in the "Add Node" menu.
## By default, it tries to format the class name (e.g. "TimerNodeResource" -> "Timer Node").
func get_display_name() -> String:
	# Get the script filename (e.g. "timer_node_resource.gd")
	var script_filename = get_script().resource_path.get_file().get_basename()
	# Remove "_resource" suffix
	var clean_name = script_filename.replace("_resource", "").replace("_node", "")
	# Capitalize snake_case to Title Case (e.g. "timer" -> "Timer")
	return clean_name.capitalize() + " Node"


## Determines the default visual size of the node in the graph.
## Override this in child classes to change the appearance (e.g., SMALL, LARGE).
func determine_default_size() -> QWNodeSizes.Size:
	return QWNodeSizes.Size.MEDIUM


## Loads a script by path with caching. Use in from_dictionary() to avoid repeated load() calls.
static func get_script_cached(path: String) -> Script:
	if path.is_empty():
		return null
	var s: Script = _script_cache.get(path)
	if s == null:
		s = load(path) as Script
		if is_instance_valid(s):
			_script_cache[path] = s
	return s


## Creates a ConditionResource from script_path without loading the script when it's condition_resource.gd.
## Avoids load() for ConditionResource to reduce GDScriptCache refs (Godot #77513).
static func new_condition_from_path(script_path: String) -> Resource:
	if script_path.is_empty():
		return null
	if "condition_resource.gd" in script_path:
		return ConditionResource.new()
	var script := get_script_cached(script_path)
	return script.new() if script else null


## Clears the script cache. Call when editor cache is invalidated.
static func clear_script_cache() -> void:
	_script_cache.clear()


## Safely loads a Vector2 from a dictionary. Handles Vector2, Dictionary with x/y keys, or defaults.
func _safe_vector2(data: Dictionary, prop: String, default_val: Vector2) -> Vector2:
	var val = data.get(prop, default_val)
	if val is Vector2:
		return val
	if val is Dictionary and val.has("x") and val.has("y"):
		return Vector2(float(val.get("x", 0)), float(val.get("y", 0)))
	return default_val


## Safely loads a bool from a dictionary. Handles bool, string "true"/"false", or defaults.
func _safe_bool(data: Dictionary, prop: String, default_val: bool) -> bool:
	var val = data.get(prop, default_val)
	if val is bool:
		return val
	if val is String:
		return val.to_lower() == "true"
	return default_val


## Static helper for defensive enum deserialization. Use when loading enum values from dict.
## Returns the enum index if valid (int in range), otherwise default_val.
## Subclasses can call GraphNodeResource.defensive_load_enum(data, "prop", EnumType.keys(), default).
static func defensive_load_enum(
	data: Dictionary, prop: String, keys: Array, default_val: int
) -> int:
	var val = data.get(prop, default_val)
	if val is int and val >= 0 and val < keys.size():
		return val
	return default_val
