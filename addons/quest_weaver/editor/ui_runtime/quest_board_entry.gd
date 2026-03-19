class_name QuestBoardEntry

extends PanelContainer

## Emitted when the player accepts this quest.
signal accept_requested(quest_id: StringName)

var _quest_id: StringName = &""

@onready var _title_label: Label = %BoardTitleLabel

@onready var _desc_label: Label = %BoardDescLabel


func get_quest_id() -> StringName:
	return _quest_id


func set_quest_data(quest_data: Dictionary) -> void:
	_quest_id = StringName(str(quest_data.get("id", "")))
	if is_instance_valid(_title_label):
		_title_label.text = tr(str(quest_data.get("title", "")))
	if is_instance_valid(_desc_label):
		var desc = str(quest_data.get("description", ""))
		if desc.length() > 120:
			desc = desc.left(117) + "..."
		_desc_label.text = tr(desc)


func _on_accept_pressed() -> void:
	if not _quest_id.is_empty():
		accept_requested.emit(_quest_id)
