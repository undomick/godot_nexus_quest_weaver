# res://addons/quest_weaver/nodes/logic/sub_graph_node/sub_graph_node_resource.gd
@tool

class_name SubGraphNodeResource

extends GraphNodeResource

@export var wait_for_completion: bool = true

## Executes another Quest Graph file as a sub-process.
## Can optionally wait for its completion before continuing the main flow.

@export_file("*.tres", "*.quest") var quest_graph_path: String


func _init():
	category = "Logic"
	input_ports = ["In"]
	_update_ports_from_data()


func _update_ports_from_data() -> void:
	if is_terminal:
		output_ports = []
	else:
		output_ports = ["Out"]


func get_editor_summary() -> String:
	var path_text = quest_graph_path.get_file() if not quest_graph_path.is_empty() else "(Not Set)"
	return "Run:\n%s" % path_text


func get_description() -> String:
	return "Executes another Quest Graph file as a subroutine. Useful for reusable logic."


func get_icon() -> Texture2D:
	return preload("res://addons/quest_weaver/assets/icons/subgraph.svg")


func to_dictionary() -> Dictionary:
	var data = super.to_dictionary()
	data["quest_graph_path"] = self.quest_graph_path
	data["wait_for_completion"] = self.wait_for_completion
	return data


func from_dictionary(data: Dictionary):
	if not data is Dictionary:
		return
	super.from_dictionary(data)
	self.quest_graph_path = data.get("quest_graph_path", "")
	self.wait_for_completion = data.get("wait_for_completion", true)
	_update_ports_from_data()


func _validate(_context: Dictionary) -> Array[ValidationResult]:
	var results: Array[ValidationResult] = []
	if quest_graph_path.is_empty():
		results.append(
			ValidationResult.new(
				ValidationResult.Severity.ERROR, "Sub Graph: Quest graph path is not set.", id
			)
		)
	elif not ResourceLoader.exists(quest_graph_path):
		results.append(
			ValidationResult.new(
				ValidationResult.Severity.ERROR,
				"Sub Graph: File not found at '%s'." % quest_graph_path,
				id
			)
		)
	return results


func determine_default_size() -> QWNodeSizes.Size:
	return QWNodeSizes.Size.SMALL
