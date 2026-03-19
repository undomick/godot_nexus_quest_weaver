# res://addons/quest_weaver/nodes/action/show_ui_message_node/show_ui_message_node_resource.gd
@tool

class_name ShowUIMessageNodeResource

extends GraphNodeResource

enum AnimationPreset { NONE, FADE, SLIDE_UP, SLIDE_DOWN, SCALE_UP, SCALE_DOWN, SLIDE_ROTATED }

@export var message_type: StringName = &"Default"

@export var title_override: String = ""

@export var wait_for_completion: bool = true

@export var animation_in: AnimationPreset = AnimationPreset.SLIDE_UP

@export var ease_in: Tween.EaseType = Tween.EASE_OUT

@export var per_character_in: bool = false

@export var animation_out: AnimationPreset = AnimationPreset.FADE

@export var ease_out: Tween.EaseType = Tween.EASE_IN

@export var per_character_out: bool = false

@export_multiline var message_override: String = ""

@export_group("Animation In")

@export_group("Animation Out")

@export_group("Timing & Behavior")

@export_range(0.1, 5.0, 0.05, "suffix:s") var duration_in: float = 0.4

@export_range(0.1, 5.0, 0.05, "suffix:s") var duration_out: float = 0.4

@export_range(0.0, 2.0, 0.05, "suffix:s") var delay_title_message: float = 0.1

@export_range(0.1, 10.0, 0.1, "suffix:s") var hold_duration: float = 3.0

@export_range(10, 200, 1, "suffix:ms") var character_stagger_ms: int = 40


func _init():
	category = "Action"
	input_ports = ["In"]
	_update_ports_from_data()


func _update_ports_from_data() -> void:
	if is_terminal:
		output_ports = []
	else:
		output_ports = ["Out"]


func get_editor_summary() -> String:
	var type_text = str(message_type)
	var anim_in_text = AnimationPreset.keys()[animation_in]
	if per_character_in:
		anim_in_text += " (Per Char)"
	return "[%s]\nAnim In: %s" % [type_text, anim_in_text]


func get_description() -> String:
	return "Displays a temporary UI popup or notification to the player."


func get_icon() -> Texture2D:
	return preload("res://addons/quest_weaver/assets/icons/ui_message.svg")


func to_dictionary() -> Dictionary:
	var data = super.to_dictionary()
	data["message_type"] = self.message_type
	data["title_override"] = self.title_override
	data["message_override"] = self.message_override
	data["wait_for_completion"] = self.wait_for_completion
	data["animation_in"] = self.animation_in
	data["ease_in"] = self.ease_in
	data["per_character_in"] = self.per_character_in
	data["animation_out"] = self.animation_out
	data["ease_out"] = self.ease_out
	data["per_character_out"] = self.per_character_out
	data["duration_in"] = self.duration_in
	data["duration_out"] = self.duration_out
	data["delay_title_message"] = self.delay_title_message
	data["hold_duration"] = self.hold_duration
	data["character_stagger_ms"] = self.character_stagger_ms
	return data


func from_dictionary(data: Dictionary):
	super.from_dictionary(data)
	self.message_type = StringName(data.get("message_type", &"Default"))
	self.title_override = str(data.get("title_override", ""))
	self.message_override = str(data.get("message_override", ""))
	self.wait_for_completion = data.get("wait_for_completion", true)
	self.animation_in = _defensive_load(
		data, "animation_in", AnimationPreset.keys(), AnimationPreset.SLIDE_UP
	)
	self.ease_in = _defensive_load(data, "ease_in", [0, 1, 2, 3], Tween.EASE_OUT)
	self.per_character_in = data.get("per_character_in", false)
	self.animation_out = _defensive_load(
		data, "animation_out", AnimationPreset.keys(), AnimationPreset.FADE
	)
	self.ease_out = _defensive_load(data, "ease_out", [0, 1, 2, 3], Tween.EASE_IN)
	self.per_character_out = data.get("per_character_out", false)
	self.duration_in = float(data.get("duration_in", 0.4))
	self.duration_out = float(data.get("duration_out", 0.4))
	self.delay_title_message = float(data.get("delay_title_message", 0.1))
	self.hold_duration = float(data.get("hold_duration", 3.0))
	self.character_stagger_ms = int(data.get("character_stagger_ms", 40))
	_update_ports_from_data()


func _defensive_load(data: Dictionary, prop: String, keys: Array, default_val: int) -> int:
	var val = data.get(prop, default_val)
	if val is int and val >= 0 and val < keys.size():
		return val
	return default_val
