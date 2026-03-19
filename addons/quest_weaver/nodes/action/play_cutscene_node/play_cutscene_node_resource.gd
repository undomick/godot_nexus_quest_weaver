# res://addons/quest_weaver/nodes/action/play_cutscene_node/play_cutscene_node_resource.gd
@tool
class_name PlayCutsceneNodeResource
extends GraphNodeResource

## Plays an animation on an AnimationPlayer within the scene.

@export var animation_player_path: NodePath
@export var animation_name: StringName
@export var wait_for_completion: bool = true


func _init():
	category = "Action"
	input_ports = ["In"]
	# We provide two outputs for maximum flexibility:
	# "On Start": Fires immediately when the animation begins.
	# "On Finish": Fires when the animation is finished (especially useful if wait_for_completion is false).
	output_ports = ["On Start", "On Finish"]


func get_editor_summary() -> String:
	var anim_name_text = str(animation_name) if not str(animation_name).is_empty() else "[WARN]???"
	return "Play:\n%s" % anim_name_text


func get_description() -> String:
	return "Plays a specific animation on an AnimationPlayer in the scene."


func get_icon() -> Texture2D:
	return preload("res://addons/quest_weaver/assets/icons/play.svg")


func to_dictionary() -> Dictionary:
	var data = super.to_dictionary()
	data["animation_player_path"] = self.animation_player_path
	data["animation_name"] = self.animation_name
	data["wait_for_completion"] = self.wait_for_completion
	return data


func from_dictionary(data: Dictionary):
	super.from_dictionary(data)
	self.animation_player_path = data.get("animation_player_path", NodePath())
	self.animation_name = data.get("animation_name", &"")
	self.wait_for_completion = data.get("wait_for_completion", true)


func _validate(_context: Dictionary) -> Array[ValidationResult]:
	var results: Array[ValidationResult] = []
	if animation_name.is_empty():
		results.append(
			ValidationResult.new(
				ValidationResult.Severity.ERROR, "Play Cutscene: Animation name is not set.", id
			)
		)
	return results


func determine_default_size() -> QWNodeSizes.Size:
	return QWNodeSizes.Size.SMALL
