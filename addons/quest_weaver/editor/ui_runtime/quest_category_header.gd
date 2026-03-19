# res://addons/quest_weaver/editor/ui_runtime/quest_category_header.gd
class_name QuestCategoryHeader

extends VBoxContainer

var category_name: String

var is_expanded: bool = true

@onready var header_button: Button = %HeaderButton

@onready var main_quest_list: VBoxContainer = %MainQuestListContainer

@onready var side_quest_list: VBoxContainer = %SideQuestListContainer

@onready var separator: HSeparator = %QuestTypeSeparator


func _ready() -> void:
	header_button.toggle_mode = true
	header_button.button_pressed = is_expanded
	header_button.toggled.connect(_on_header_toggled)

	_on_header_toggled(is_expanded)


func _on_header_toggled(is_button_pressed: bool) -> void:
	is_expanded = is_button_pressed
	main_quest_list.visible = is_expanded
	side_quest_list.visible = is_expanded
	separator.visible = is_expanded and _should_separator_be_visible()

	update_display()


func set_category_name(new_name: String) -> void:
	category_name = new_name


func add_quest_entry(
	entry_node: QuestLogEntry, quest_type: QuestContextNodeResource.QuestType
) -> void:
	if quest_type == QuestContextNodeResource.QuestType.MAIN:
		main_quest_list.add_child(entry_node)
	else:  # SIDE
		side_quest_list.add_child(entry_node)


## Clears entries. If recycle_to is an Array, entries are returned to it instead of freed.
func clear_entries(recycle_to: Variant = null) -> void:
	for child in main_quest_list.get_children().duplicate():
		main_quest_list.remove_child(child)
		if recycle_to is Array:
			recycle_to.append(child)
		else:
			child.free()

	for child in side_quest_list.get_children().duplicate():
		side_quest_list.remove_child(child)
		if recycle_to is Array:
			recycle_to.append(child)
		else:
			child.free()


func _should_separator_be_visible() -> bool:
	return main_quest_list.get_child_count() > 0 and side_quest_list.get_child_count() > 0


func update_display() -> void:
	var main_count = main_quest_list.get_child_count()
	var side_count = side_quest_list.get_child_count()
	var total_count = main_count + side_count

	var arrow = "▼" if is_expanded else "►"
	header_button.text = "%s %s (%d)" % [arrow, category_name, total_count]

	if is_expanded:
		separator.visible = _should_separator_be_visible()
