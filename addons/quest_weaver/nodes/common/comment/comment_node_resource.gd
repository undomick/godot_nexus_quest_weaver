# res://addons/quest_weaver/nodes/common/comment/comment_node_resource.gd
@tool

class_name CommentNodeResource

extends GraphNodeResource

# The size of the node in the graph editor.
@export var node_size: Vector2 = Vector2(200, 150)

# The text content of the comment.
@export_multiline var text: String = "My Comment"


func _init() -> void:
	category = "Utility"
	input_ports = []
	output_ports = []


func get_description() -> String:
	return "A sticky note for documentation. Has no effect on logic."


func get_icon() -> Texture2D:
	return preload("res://addons/quest_weaver/assets/icons/comment.svg")


func determine_default_size() -> QWNodeSizes.Size:
	return QWNodeSizes.Size.SMALL


func get_editor_summary() -> String:
	if text.is_empty():
		return "(Empty Comment)"
	return text


func to_dictionary() -> Dictionary:
	var data = super.to_dictionary()
	data["text"] = self.text
	data["node_size"] = self.node_size
	return data


func from_dictionary(data: Dictionary):
	super.from_dictionary(data)
	self.text = str(data.get("text", "My Comment"))
	var size_val = data.get("node_size", Vector2(200, 150))
	self.node_size = size_val if size_val is Vector2 else Vector2(200, 150)
