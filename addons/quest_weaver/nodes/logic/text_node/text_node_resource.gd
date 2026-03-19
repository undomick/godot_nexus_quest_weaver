# res://addons/quest_weaver/nodes/logic/text_node/text_node_resource.gd
@tool
class_name TextNodeResource
extends GraphNodeResource

enum TextTarget { ADD_TO_QUEST_LOG, SET_QUEST_DESCRIPTION }  # Adds a new entry to the quest log (multiline support)  # Overwrites the current quest description (multiline support)

@export var target_property: TextTarget = TextTarget.ADD_TO_QUEST_LOG
@export_multiline var text_content: String = ""


func _init() -> void:
	category = "Logic"
	input_ports = ["In"]
	output_ports = ["Out"]


func get_editor_summary() -> String:
	var category_text: String
	if target_property == TextTarget.ADD_TO_QUEST_LOG:
		category_text = "[LOG]\n"
	else:
		category_text = "[DESCRIPTION]\n"

	if text_content.is_empty():
		return "%s (Empty Text)" % category_text

	# Replace manual line breaks with spaces to allow our custom drawing logic
	# in QWGraphNode to handle word wrapping cleanly based on node width.
	var single_line_text = text_content.replace("\n", " ").strip_edges()

	# The [TRUNCATE] prefix signals QWGraphNode to use the
	# intelligent wrapping and truncation logic.
	return "[TRUNCATE]" + category_text + single_line_text


func get_description() -> String:
	return "Updates the quest log or changes the current visible quest description."


func get_icon() -> Texture2D:
	return preload("res://addons/quest_weaver/assets/icons/text.svg")


func to_dictionary() -> Dictionary:
	var data = super.to_dictionary()
	data["target_property"] = self.target_property
	data["text_content"] = self.text_content
	return data


func from_dictionary(data: Dictionary):
	super.from_dictionary(data)
	self.target_property = _defensive_load(
		data, "target_property", TextTarget.keys(), TextTarget.ADD_TO_QUEST_LOG
	)
	self.text_content = data.get("text_content", "")


func _defensive_load(data: Dictionary, prop: String, keys: Array, default_val: int) -> int:
	var val = data.get(prop, default_val)
	if val is int and val >= 0 and val < keys.size():
		return val
	return default_val


func _validate(_context: Dictionary) -> Array[ValidationResult]:
	var results: Array[ValidationResult] = []

	if text_content.is_empty():
		results.append(
			ValidationResult.new(
				ValidationResult.Severity.INFO, "Quest Text: Text content is empty.", id
			)
		)

	return results
