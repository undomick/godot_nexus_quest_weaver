# res://addons/quest_weaver/editor/presentation/base_ui_panel.gd
class_name BaseUIPanel

extends MarginContainer

signal presentation_completed

const QWCharAnimationEffect = preload(
	"res://addons/quest_weaver/editor/presentation/qw_char_animation_effect.gd"
)

var _active_tween: Tween = null

var _is_aborted: bool = false

@onready var title_label: RichTextLabel = %TitleLabel

@onready var message_label: RichTextLabel = %MessageLabel


## Stops any running animation and clears effects. Call before queue_free during shutdown.
func abort_presentation() -> void:
	_is_aborted = true
	if is_instance_valid(_active_tween):
		_active_tween.kill()
		_active_tween = null
	_clear_animation_effects()


func _exit_tree() -> void:
	if is_instance_valid(_active_tween):
		_active_tween.kill()
		_active_tween = null
	_clear_animation_effects()


func _clear_animation_effects() -> void:
	for label in [title_label, message_label]:
		if not is_instance_valid(label):
			continue
		if label.custom_effects.is_empty():
			continue
		for effect in label.custom_effects:
			if effect is QWCharAnimationEffect:
				effect.owner_label = null
		label.custom_effects.clear()


func present(data: Dictionary) -> void:
	self.modulate.a = 0.0
	_presentation_flow(data)


func _presentation_flow(data: Dictionary) -> void:
	title_label.text = tr(data.get("title", ""))
	message_label.text = tr(data.get("message", ""))

	await get_tree().process_frame
	if _is_aborted or not is_inside_tree():
		return

	var anim_in_preset = data.get("anim_in", 0)
	_set_initial_state(anim_in_preset)

	var in_tween = _play_animation(data, true)
	if is_instance_valid(in_tween):
		await in_tween.finished
	if _is_aborted or not is_inside_tree():
		return

	await get_tree().create_timer(data.get("hold_duration", 3.0)).timeout
	if _is_aborted or not is_inside_tree():
		return

	var out_tween = _play_animation(data, false)
	if is_instance_valid(out_tween):
		await out_tween.finished
	if _is_aborted or not is_inside_tree():
		return

	presentation_completed.emit()


func _set_initial_state(preset: int) -> void:
	modulate = Color.WHITE
	scale = Vector2.ONE
	position = Vector2.ZERO
	rotation_degrees = 0

	title_label.modulate.a = 0.0
	message_label.modulate.a = 0.0

	match preset:
		ShowUIMessageNodeResource.AnimationPreset.SLIDE_UP:
			position.y = 50
		ShowUIMessageNodeResource.AnimationPreset.SLIDE_DOWN:
			position.y = -50
		ShowUIMessageNodeResource.AnimationPreset.SCALE_UP:
			scale = Vector2(0.8, 0.8)
		ShowUIMessageNodeResource.AnimationPreset.SCALE_DOWN:
			scale = Vector2(1.2, 1.2)
		ShowUIMessageNodeResource.AnimationPreset.SLIDE_ROTATED:
			position.x = -50
			rotation_degrees = -5


func _play_animation(data: Dictionary, is_in: bool) -> Tween:
	var preset_key = "anim_in" if is_in else "anim_out"
	var duration_key = "duration_in" if is_in else "duration_out"
	var ease_key = "ease_in" if is_in else "ease_out"

	var preset = data.get(preset_key, 0)
	var duration = data.get(duration_key, 0.4)
	var ease_type = data.get(ease_key, Tween.EASE_IN_OUT)

	var has_container_animation = preset != ShowUIMessageNodeResource.AnimationPreset.NONE
	var has_text_animation = (
		is_in and (not title_label.text.is_empty() or not message_label.text.is_empty())
	)

	if not has_container_animation and not has_text_animation:
		return null

	_active_tween = create_tween()
	var tween = _active_tween
	var per_char_in = data.get("per_character_in", false)

	if is_in:
		# For "in" animations, all tracks (container, title, message) run in parallel.
		tween.set_parallel()

		if per_char_in:
			# For per-character, snap the container to its final position instantly.
			self.position = Vector2.ZERO
			self.scale = Vector2.ONE
			self.rotation_degrees = 0.0
		else:
			# For normal animations, tween the container's properties.
			tween.tween_property(self, "position", Vector2.ZERO, duration).set_ease(ease_type)
			tween.tween_property(self, "scale", Vector2.ONE, duration).set_ease(ease_type)
			tween.tween_property(self, "rotation_degrees", 0.0, duration).set_ease(ease_type)

		if has_text_animation:
			var delay = data.get("delay_title_message", 0.1)

			# Animate the title with no delay.
			_animate_text(tween, title_label, data, is_in, 0.0)

			# Animate the message with the specified delay.
			_animate_text(tween, message_label, data, is_in, delay)

	else:
		tween.set_parallel().set_ease(ease_type)
		tween.tween_property(self, "modulate:a", 0.0, duration)

		var target_pos = position
		var target_scale = scale
		var target_rot = rotation_degrees
		match preset:
			ShowUIMessageNodeResource.AnimationPreset.SLIDE_UP:
				target_pos.y = -50
			ShowUIMessageNodeResource.AnimationPreset.SLIDE_DOWN:
				target_pos.y = 50
			ShowUIMessageNodeResource.AnimationPreset.SCALE_UP:
				target_scale = Vector2(1.2, 1.2)
			ShowUIMessageNodeResource.AnimationPreset.SCALE_DOWN:
				target_scale = Vector2(0.8, 0.8)
			ShowUIMessageNodeResource.AnimationPreset.SLIDE_ROTATED:
				target_pos.x = 50
				target_rot = 5

		if target_pos != position:
			tween.tween_property(self, "position", target_pos, duration)
		if target_scale != scale:
			tween.tween_property(self, "scale", target_scale, duration)
		if target_rot != rotation_degrees:
			tween.tween_property(self, "rotation_degrees", target_rot, duration)

	return tween


func _animate_text(
	tween: Tween, label: RichTextLabel, data: Dictionary, is_in: bool, delay: float
) -> void:
	if label.text.is_empty():
		return

	var per_char_key = "per_character_in" if is_in else "per_character_out"
	var use_per_char = data.get(per_char_key, false)

	if use_per_char:
		var original_text = label.text
		label.modulate.a = 1.0

		var char_effect = QWCharAnimationEffect.new()

		char_effect.owner_label = label
		char_effect.preset = data.get("anim_in", 0)
		char_effect.duration = data.get("duration_in", 0.4)
		char_effect.stagger = data.get("character_stagger_ms", 40) / 1000.0
		char_effect.ease_type = data.get("ease_in", Tween.EASE_IN_OUT)

		label.custom_effects = [char_effect]
		label.text = "[qw_anim]" + original_text + "[/qw_anim]"

		var total_chars = label.get_total_character_count()
		var total_duration = char_effect.duration + (char_effect.stagger * max(0, total_chars - 1))

		var property_tweener = tween.tween_property(
			char_effect, "elapsed_time", total_duration, total_duration
		)
		if delay > 0.0:
			property_tweener.set_delay(delay)

	else:
		label.modulate.a = 0.0
		var duration = data.get("duration_in" if is_in else "duration_out", 0.4)
		var target_alpha = 1.0 if is_in else 0.0

		var property_tweener = tween.tween_property(label, "modulate:a", target_alpha, duration)
		if delay > 0.0:
			property_tweener.set_delay(delay)
