# res://addons/quest_weaver/editor/presentation/qw_char_animation_effect.gd
class_name QWCharAnimationEffect

extends RichTextEffect

@export var elapsed_time: float = 0.0

# This effect will be identified by the BBCode tag [qw_anim]
var bbcode = "qw_anim"

var owner_label: RichTextLabel

# Parameters passed from the BaseUIPanel
var preset: int = 0

var duration: float = 0.4

var stagger: float = 0.04

var ease_type: Tween.EaseType = Tween.EASE_IN_OUT


# This is the core function of the effect.
func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	var char_start_time = stagger * char_fx.relative_index
	var char_end_time = char_start_time + duration

	var char_progress = remap(elapsed_time, char_start_time, char_end_time, 0.0, 1.0)
	char_progress = clamp(char_progress, 0.0, 1.0)

	# We now call our own helper function instead of the incorrect global `ease()`.
	var eased_progress = _apply_ease(char_progress, ease_type)

	match preset:
		ShowUIMessageNodeResource.AnimationPreset.FADE:
			char_fx.color.a = eased_progress
		ShowUIMessageNodeResource.AnimationPreset.SLIDE_UP:
			char_fx.color.a = eased_progress
			char_fx.offset.y = lerp(20.0, 0.0, eased_progress)
		ShowUIMessageNodeResource.AnimationPreset.SLIDE_DOWN:
			char_fx.color.a = eased_progress
			char_fx.offset.y = lerp(-20.0, 0.0, eased_progress)
		ShowUIMessageNodeResource.AnimationPreset.SCALE_UP:
			var scale_val = lerp(0.0, 1.0, eased_progress)
			char_fx.transform = Transform2D().scaled(Vector2(scale_val, scale_val))
			char_fx.color.a = eased_progress
		ShowUIMessageNodeResource.AnimationPreset.SCALE_DOWN:
			var scale_val = lerp(2.0, 1.0, eased_progress)
			char_fx.transform = Transform2D().scaled(Vector2(scale_val, scale_val))
			char_fx.color.a = eased_progress
		ShowUIMessageNodeResource.AnimationPreset.SLIDE_ROTATED:
			char_fx.color.a = eased_progress
			char_fx.offset.x = lerp(-20.0, 0.0, eased_progress)
			char_fx.rotation = lerp(-0.5, 0.0, eased_progress)
		_:
			char_fx.color.a = eased_progress

	return true


# --- NEW HELPER FUNCTION ---

# This function correctly applies easing based on the Tween.EaseType enum.


func _apply_ease(progress: float, p_ease_type: Tween.EaseType) -> float:
	match p_ease_type:
		Tween.EASE_IN:
			# Quadratic easing in
			return progress * progress
		Tween.EASE_OUT:
			# Quadratic easing out
			return 1.0 - (1.0 - progress) * (1.0 - progress)
		Tween.EASE_IN_OUT:
			# Quadratic easing in/out
			if progress < 0.5:
				return 2.0 * progress * progress
			else:
				return 1.0 - pow(-2.0 * progress + 2.0, 2) / 2.0
		# Add other ease types here if needed (e.g., CUBIC, SINE...)
		_:  # Default case: EASE_OUT_IN or any other, falls back to linear
			return progress
