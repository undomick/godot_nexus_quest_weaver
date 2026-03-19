# res://addons/quest_weaver/nodes/common/backdrop/backdrop_node_resource.gd
@tool

class_name BackdropNodeResource

extends GraphNodeResource

@export var title: String = ""

@export var color: Color = Color(0.2, 0.23, 0.3, 0.6)

@export var node_size: Vector2 = Vector2(400, 300)

@export_multiline var text: String = ""

@export_range(10, 48, 1) var title_font_size: int = 16


func _init() -> void:
	category = "Backdrop"
	input_ports = []
	output_ports = []


func get_description() -> String:
	return "A visual container to group nodes together. Has no effect on logic."


func get_icon() -> Texture2D:
	return preload("res://addons/quest_weaver/assets/icons/backdrop.svg")


func to_dictionary() -> Dictionary:
	var data = super.to_dictionary()
	data["title"] = self.title
	data["text"] = self.text
	data["color"] = self.color
	data["node_size"] = self.node_size
	data["title_font_size"] = self.title_font_size
	return data


func from_dictionary(data: Dictionary):
	super.from_dictionary(data)
	self.title = str(data.get("title", ""))
	self.text = str(data.get("text", ""))
	var color_val = data.get("color", Color(0.2, 0.23, 0.3, 0.6))
	self.color = color_val if color_val is Color else Color(0.2, 0.23, 0.3, 0.6)
	var size_val = data.get("node_size", Vector2(400, 300))
	self.node_size = size_val if size_val is Vector2 else Vector2(400, 300)
	self.title_font_size = int(data.get("title_font_size", 16))


func determine_default_size() -> QWNodeSizes.Size:
	return QWNodeSizes.Size.LARGE
