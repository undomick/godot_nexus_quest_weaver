# res://addons/quest_weaver/core/qw_node_sizes.gd
@tool
class_name QWNodeSizes
extends RefCounted

enum Size { TINY, SMALL, MEDIUM, LARGE, TOWER }


static func get_vector_for_size(size_enum: Size) -> Vector2:
	match size_enum:
		Size.TINY:
			return Vector2(60, 60)
		Size.SMALL:
			return Vector2(240, 120)
		Size.MEDIUM:
			return Vector2(300, 160)
		Size.LARGE:
			return Vector2(360, 240)
		Size.TOWER:
			return Vector2(240, 240)
	return Vector2(280, 120)  # Fallback
