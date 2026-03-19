# res://addons/quest_weaver/nodes/logic/quest_context_node/quest_context_node_editor.gd
@tool

extends NodePropertyEditorBase

var _is_setting_up := false

# --- UI REFERENCES ---
@onready var quest_id_edit: LineEdit = %QuestIdEdit

@onready var quest_type_picker: OptionButton = %QuestTypePicker

@onready var title_edit: LineEdit = %TitleEdit

@onready var description_edit: TabFocusTextEdit = %DescriptionEdit

@onready var log_on_start_edit: TabFocusTextEdit = %LogOnStartEdit

# Rewards UI
@onready var rewards_container: VBoxContainer = %RewardsContainer

@onready var reward_label: Label = %RewardLabel

@onready var add_reward_button: Button = %AddRewardButton


func _ready() -> void:
	quest_id_edit.text_submitted.connect(func(_t): quest_id_edit.release_focus())
	quest_id_edit.focus_exited.connect(_on_quest_id_confirmed)

	quest_type_picker.item_selected.connect(_on_quest_type_changed)

	title_edit.text_submitted.connect(func(_t): title_edit.release_focus())
	title_edit.focus_exited.connect(_on_title_confirmed)

	description_edit.focus_exited.connect(_on_description_confirmed)
	log_on_start_edit.focus_exited.connect(_on_log_on_start_confirmed)

	add_reward_button.pressed.connect(_on_add_reward_pressed)


func set_node_data(node_data: GraphNodeResource) -> void:
	_is_setting_up = true
	super.set_node_data(node_data)

	if not node_data is QuestContextNodeResource:
		_is_setting_up = false
		return

	# Populate Core Fields
	quest_id_edit.text = node_data.quest_id
	title_edit.text = node_data.quest_title
	description_edit.text = node_data.quest_description
	log_on_start_edit.text = node_data.log_on_start

	quest_type_picker.clear()
	for type_name in node_data.QuestType.keys():
		quest_type_picker.add_item(type_name.capitalize())
	quest_type_picker.select(node_data.quest_type)

	call_deferred(&"_safe_rebuild")
	_is_setting_up = false


func _safe_rebuild() -> void:
	if not is_instance_valid(rewards_container) or not is_instance_valid(edited_node_data):
		return

	for child in rewards_container.get_children():
		child.queue_free()

	var context_node = edited_node_data as QuestContextNodeResource

	var display_index = 0

	for i in range(context_node.rewards.size()):
		var reward_dict = context_node.rewards[i]
		if reward_dict is Dictionary:
			var id_val = reward_dict.get("id", &"")
			var is_temp = id_val == &""

			var entry = QWConstants.RewardEntryScene.instantiate()
			rewards_container.add_child(entry)
			entry.setup(reward_dict, display_index, is_temp)
			entry.remove_requested.connect(_on_reward_delete_requested.bind(i))

			entry.data_changed.connect(_on_reward_entry_data_changed)

			if not is_temp:
				display_index += 1

	if is_instance_valid(reward_label):
		reward_label.visible = (context_node.rewards.size() > 0)


func _on_add_reward_pressed() -> void:
	if is_instance_valid(edited_node_data) and edited_node_data is QuestContextNodeResource:
		complex_action_requested.emit(edited_node_data.id, "add_reward", {})
		call_deferred(&"_safe_rebuild")


func _on_reward_delete_requested(index: int) -> void:
	if is_instance_valid(edited_node_data) and edited_node_data is QuestContextNodeResource:
		complex_action_requested.emit(edited_node_data.id, "remove_reward", {"index": index})
		call_deferred(&"_safe_rebuild")


func _on_reward_entry_data_changed() -> void:
	if is_instance_valid(edited_node_data) and edited_node_data is QuestContextNodeResource:
		property_update_requested.emit(
			edited_node_data.id, "rewards", edited_node_data.rewards.duplicate(true), null, {}
		)
	call_deferred(&"_safe_rebuild")


# --- CORE PROPERTY HANDLERS ---


func _on_quest_id_confirmed() -> void:
	if _is_setting_up:
		return
	if not is_instance_valid(edited_node_data):
		return
	if edited_node_data.quest_id != quest_id_edit.text:
		property_update_requested.emit(
			edited_node_data.id, "quest_id", StringName(quest_id_edit.text), null, {}
		)


func _on_quest_type_changed(index: int):
	if _is_setting_up:
		return
	if not is_instance_valid(edited_node_data):
		return
	if edited_node_data.quest_type != index:
		property_update_requested.emit(edited_node_data.id, "quest_type", index, null, {})


func _on_title_confirmed() -> void:
	if _is_setting_up:
		return
	if not is_instance_valid(edited_node_data):
		return
	if edited_node_data.quest_title != title_edit.text:
		property_update_requested.emit(
			edited_node_data.id, "quest_title", title_edit.text, null, {}
		)


func _on_description_confirmed() -> void:
	if _is_setting_up:
		return
	if not is_instance_valid(edited_node_data):
		return
	if edited_node_data.quest_description != description_edit.text:
		property_update_requested.emit(
			edited_node_data.id, "quest_description", description_edit.text, null, {}
		)


func _on_log_on_start_confirmed() -> void:
	if _is_setting_up:
		return
	if not is_instance_valid(edited_node_data):
		return
	if edited_node_data.log_on_start != log_on_start_edit.text:
		property_update_requested.emit(
			edited_node_data.id, "log_on_start", log_on_start_edit.text, null, {}
		)
