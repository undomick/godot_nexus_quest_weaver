class_name QuestBoardUI

extends CanvasLayer

## Runtime UI for the Quest Board. Shows quests in AVAILABLE state and lets the player accept them.
## Connect to quest_became_available; uses get_available_quests() from QuestController.

const QuestBoardEntryScene = preload("./quest_board_entry.tscn")

@export var toggle_board_action: StringName = &"toggle_quest_board"

# --- Internal State ---
var quest_controller: QuestController

var _list_needs_redraw := false

# --- UI References ---
@onready var quest_list_container: VBoxContainer = %BoardQuestListContainer

@onready var empty_label: Label = %BoardEmptyLabel

@onready var close_button: Button = %BoardCloseButton


func _ready() -> void:
	self.visible = false

	if not toggle_board_action.is_empty() and not InputMap.has_action(toggle_board_action):
		push_warning(
			(
				"QuestBoardUI: Input Action '%s' not found. Toggle via keyboard disabled."
				% toggle_board_action
			)
		)
		toggle_board_action = &""

	visibility_changed.connect(_on_visibility_changed)

	var services = _get_services_safe()
	if services:
		quest_controller = services.quest_controller
		if is_instance_valid(quest_controller):
			_initialize_connections()
		else:
			services.controller_ready.connect(_on_controller_ready, CONNECT_ONE_SHOT)


func _input(event: InputEvent) -> void:
	if not toggle_board_action.is_empty() and event.is_action_pressed(toggle_board_action):
		visible = !visible
		get_viewport().set_input_as_handled()


func _on_visibility_changed() -> void:
	if visible:
		_request_list_redraw()


func _initialize_connections() -> void:
	if not quest_controller.quest_became_available.is_connected(_on_board_list_changed):
		quest_controller.quest_became_available.connect(_on_board_list_changed)
	if not quest_controller.quest_started.is_connected(_on_board_list_changed):
		quest_controller.quest_started.connect(_on_board_list_changed)
	if not quest_controller.quest_data_changed.is_connected(_on_board_list_changed):
		quest_controller.quest_data_changed.connect(_on_board_list_changed)

	if self.visible:
		_request_list_redraw()


func _on_controller_ready() -> void:
	var services = _get_services_safe()
	if services:
		quest_controller = services.quest_controller
	if is_instance_valid(quest_controller):
		_initialize_connections()
	else:
		push_error("QuestBoardUI: Controller_ready received but controller invalid!")


func _on_board_list_changed(_arg: Variant = null) -> void:
	_request_list_redraw()


func _request_list_redraw() -> void:
	if not self.visible or _list_needs_redraw:
		return
	_list_needs_redraw = true
	call_deferred(&"_process_redraw")


func _process_redraw() -> void:
	if not _list_needs_redraw:
		return
	_list_needs_redraw = false
	if self.visible:
		_redraw_quest_list()


func _redraw_quest_list() -> void:
	if not is_instance_valid(quest_controller):
		return

	for child in quest_list_container.get_children():
		child.queue_free()

	var available_ids = quest_controller.get_quest_pool_manager().get_available_quests()

	if available_ids.is_empty():
		if is_instance_valid(empty_label):
			empty_label.visible = true
			empty_label.text = "No quests available."
		return

	if is_instance_valid(empty_label):
		empty_label.visible = false

	for quest_id in available_ids:
		var quest_data = quest_controller.get_quest_data_manager().get_quest_data(quest_id)
		if quest_data.is_empty():
			continue

		var entry = QuestBoardEntryScene.instantiate()
		entry.set_quest_data(quest_data)
		entry.accept_requested.connect(_on_quest_accepted)
		quest_list_container.add_child(entry)


func _on_quest_accepted(quest_id: StringName) -> void:
	if quest_id.is_empty():
		return
	if is_instance_valid(quest_controller):
		quest_controller.start_quest_id(quest_id)
		_request_list_redraw()


func _on_close_button_pressed() -> void:
	self.visible = false


func _get_services_safe() -> Node:
	var main_loop = Engine.get_main_loop()
	if main_loop and main_loop.root:
		return main_loop.root.get_node_or_null("QuestWeaverServices")
	return null
