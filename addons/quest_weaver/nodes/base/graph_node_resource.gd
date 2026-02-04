# res://addons/quest_weaver/nodes/base/graph_node_resource.gd
@tool
class_name GraphNodeResource
extends Resource

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
	self.graph_position = data.get("graph_position", Vector2.ZERO)
	self.is_terminal = data.get("is_terminal", false)
	
	# Array Conversion
	self.input_ports.clear()
	for p in data.get("input_ports", []): self.input_ports.append(StringName(p))
		
	self.output_ports.clear()
	for p in data.get("output_ports", []): self.output_ports.append(StringName(p))

## Virtual method for validation.
## 'context' contains references to 'item_registry' and 'quest_registry'.
## Override this in specific node resources to add custom checks.
func _validate(context: Dictionary) -> Array[ValidationResult]:
	return [] # By default, a node is considered valid.

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
