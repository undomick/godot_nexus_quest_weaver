# res://addons/quest_weaver/editor/ui_runtime/quest_log_ui.gd
class_name QuestLogUI

extends CanvasLayer

## Main runtime UI for the Quest Journal.
## It connects to the QuestController signals to automatically update
## when quests start, progress, or finish.

const QuestLogEntryScene = preload("./quest_log_entry.tscn")

const QuestCategoryHeader = preload("./quest_category_header.gd")

# Object pool to reduce allocations on redraw
const ENTRY_POOL_MAX := 20

@export var toggle_log_action: StringName = &"toggle_quest_log"

var quest_controller: QuestController

# --- Internal State ---
var _all_quest_entries: Array[QuestLogEntry] = []

var _current_selected_quest_id: StringName = &""

var _item_registry: Resource = null

var _item_registry_load_attempted := false

# Redraw flag to prevent multiple rebuilds in the same frame
var _list_needs_redraw := false

var _entry_pool: Array[QuestLogEntry] = []

# --- UI References (Right Side / Detail View) ---
@onready var quest_list: VBoxContainer = %QuestListContainer

@onready var active_quests_header: QuestCategoryHeader = %ActiveQuestsHeader

@onready var completed_quests_header: QuestCategoryHeader = %CompletedQuestsHeader

@onready var failed_quests_header: QuestCategoryHeader = %FailedQuestsHeader

# --- UI References (Left Side / List View) ---
@onready var detail_title_label: Label = %DetailTitleLabel

@onready var detail_description_label: RichTextLabel = %DetailDescriptionLabel

@onready var detail_objectives_list: VBoxContainer = %DetailObjectivesList

@onready var detail_log_list: VBoxContainer = %DetailLogList

@onready var close_button: Button = %CloseButton


func _ready() -> void:
	self.visible = false

	# Validate Input Action exists to prevent runtime errors
	if not toggle_log_action.is_empty() and not InputMap.has_action(toggle_log_action):
		push_warning(
			(
				"QuestLogUI: Input Action '%s' not found in Project Settings. Log toggle via keyboard disabled."
				% toggle_log_action
			)
		)
		toggle_log_action = &""  # Disable action to prevent crashes in _input

	# Initialize headers with default titles
	active_quests_header.set_category_name("Active Quests")
	completed_quests_header.set_category_name("Completed Quests")
	failed_quests_header.set_category_name("Failed Quests")

	# React to visibility changes (e.g. opened via button or key)
	visibility_changed.connect(_on_visibility_changed)

	# Try to connect to the controller immediately, or wait for it
	var services = _get_services_safe()
	if services:
		quest_controller = services.quest_controller
		if is_instance_valid(quest_controller):
			_initialize_connections()
		else:
			# Wait until controller is ready
			services.controller_ready.connect(_on_controller_ready, CONNECT_ONE_SHOT)


func _input(event: InputEvent) -> void:
	if not toggle_log_action.is_empty() and event.is_action_pressed(toggle_log_action):
		visible = !visible
		get_viewport().set_input_as_handled()


func _on_visibility_changed() -> void:
	# Refresh data only when the UI becomes visible to save performance
	if visible:
		_request_list_redraw()


# Connect to all relevant signals from the QuestController logic
func _initialize_connections() -> void:
	if not quest_controller.quest_started.is_connected(_on_quest_list_changed):
		quest_controller.quest_started.connect(_on_quest_list_changed)
	if not quest_controller.quest_completed.is_connected(_on_quest_list_changed):
		quest_controller.quest_completed.connect(_on_quest_list_changed)
	if not quest_controller.quest_failed.is_connected(_on_quest_list_changed):
		quest_controller.quest_failed.connect(_on_quest_list_changed)
	if not quest_controller.quest_data_changed.is_connected(_on_quest_data_changed):
		quest_controller.quest_data_changed.connect(_on_quest_data_changed)

	if self.visible:
		_request_list_redraw()


func _on_controller_ready() -> void:
	var services = _get_services_safe()
	if services:
		quest_controller = services.quest_controller
	if is_instance_valid(quest_controller):
		_initialize_connections()
	else:
		push_error("QuestLogUI: Controller_ready signal received, but controller is still invalid!")


# --- Signal Handlers ---


func _on_quest_list_changed(_quest_id: StringName) -> void:
	_request_list_redraw()


func _on_quest_data_changed(quest_id: StringName) -> void:
	_request_list_redraw()

	# If the currently viewed quest changed, update the details immediately
	if self.visible and quest_id == _current_selected_quest_id:
		_update_detail_view()


# --- Redraw Logic (Debounced) ---


func _request_list_redraw() -> void:
	# Only schedule one redraw per frame, and only if visible
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

		# Update the category headers (expand/collapse/count)
		active_quests_header.update_display()
		completed_quests_header.update_display()
		failed_quests_header.update_display()

		_update_detail_view()


func _redraw_quest_list() -> void:
	if not is_instance_valid(quest_controller):
		return

	# 1. Recycle existing entries to pool instead of freeing
	active_quests_header.clear_entries(_entry_pool)
	completed_quests_header.clear_entries(_entry_pool)
	failed_quests_header.clear_entries(_entry_pool)
	_all_quest_entries.clear()
	_trim_entry_pool()

	# 2. Fetch fresh data from the controller
	var all_quests = quest_controller.get_quest_data_manager().get_all_managed_quests_data()

	# 3. Iterate and sort into categories
	for quest_data in all_quests:
		var status = quest_data.get("status", QWEnums.QuestState.UNAVAILABLE)

		# Filter: Don't show UNAVAILABLE or AVAILABLE quests in the active log.
		# AVAILABLE quests usually belong on a "Quest Board", not the personal Journal.
		if status == QWEnums.QuestState.UNAVAILABLE or status == QWEnums.QuestState.AVAILABLE:
			continue

		var entry_instance: QuestLogEntry = _get_entry_from_pool()
		entry_instance.selected.connect(_on_quest_entry_selected)
		_all_quest_entries.append(entry_instance)

		var quest_type = quest_data.get("quest_type", QuestContextNodeResource.QuestType.SIDE)
		match status:
			QWEnums.QuestState.ACTIVE:
				active_quests_header.add_quest_entry(entry_instance, quest_type)
			QWEnums.QuestState.COMPLETED:
				completed_quests_header.add_quest_entry(entry_instance, quest_type)
			QWEnums.QuestState.FAILED:
				failed_quests_header.add_quest_entry(entry_instance, quest_type)

		entry_instance.set_quest_data(quest_data)

	# 4. Ensure the selection highlight is correct
	_update_selection_and_highlights(all_quests)


func _update_selection_and_highlights(all_quests: Array) -> void:
	var all_quest_ids = all_quests.map(func(q): return q.id)

	# If selection is invalid (empty or quest removed), try to select the first active quest
	if not _current_selected_quest_id in all_quest_ids:
		var active_quests = all_quests.filter(
			func(q): return q.get("status") == QWEnums.QuestState.ACTIVE
		)
		if not active_quests.is_empty():
			_on_quest_entry_selected(active_quests[0].id)
		else:
			_clear_detail_view()
			_update_entry_highlights()
	else:
		_update_entry_highlights()


func _on_quest_entry_selected(quest_id: StringName) -> void:
	if _current_selected_quest_id == quest_id:
		return

	_current_selected_quest_id = quest_id

	_update_entry_highlights()
	_update_detail_view()


func _update_entry_highlights() -> void:
	# Visually highlight the selected entry in the list
	for entry in _all_quest_entries:
		entry.set_active_state(entry.get_quest_id() == _current_selected_quest_id)


func _get_entry_from_pool() -> QuestLogEntry:
	if _entry_pool.size() > 0:
		var entry = _entry_pool.pop_back()
		if entry.selected.is_connected(_on_quest_entry_selected):
			entry.selected.disconnect(_on_quest_entry_selected)
		return entry
	return QuestLogEntryScene.instantiate()


func _trim_entry_pool() -> void:
	while _entry_pool.size() > ENTRY_POOL_MAX:
		_entry_pool.pop_back().queue_free()


# --- Detail View Logic ---


func _clear_detail_view() -> void:
	_current_selected_quest_id = &""
	detail_title_label.text = "No Quest selected"
	detail_description_label.text = ""
	for child in detail_objectives_list.get_children():
		child.queue_free()
	for child in detail_log_list.get_children():
		child.queue_free()


func _update_detail_view() -> void:
	if _current_selected_quest_id.is_empty():
		_clear_detail_view()
		return
	if not is_instance_valid(quest_controller):
		return

	var quest_data = quest_controller.get_quest_data_manager().get_quest_data(
		_current_selected_quest_id
	)
	if quest_data.is_empty():
		_clear_detail_view()
		return

	# 1. Set Title and Description
	var title_string = quest_data.get("title", "ERROR_TITLE")
	var description_string = quest_data.get("description", "")

	detail_title_label.text = tr(title_string)
	detail_description_label.text = tr(description_string)

	# 2. Build Log Entries (History)
	for child in detail_log_list.get_children():
		child.queue_free()

	for log_entry_string in quest_data.get("log_entries", []):
		var log_label = Label.new()
		log_label.text = "- " + tr(log_entry_string)
		log_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		log_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		detail_log_list.add_child(log_label)

	# 3. Build Active Objectives
	for child in detail_objectives_list.get_children():
		child.queue_free()

	var active_objectives = (
		quest_controller
		. get_objective_manager()
		. get_active_objectives_for_quest(_current_selected_quest_id)
	)
	var quest_status = quest_data.get("status")

	if active_objectives.is_empty() and quest_status == QWEnums.QuestState.ACTIVE:
		var no_obj_label = Label.new()
		no_obj_label.text = "No active objectives."
		no_obj_label.modulate = Color(1, 1, 1, 0.5)
		detail_objectives_list.add_child(no_obj_label)
	elif quest_status == QWEnums.QuestState.COMPLETED:
		var comp_label = Label.new()
		comp_label.text = "Quest Completed."
		comp_label.modulate = Color(0.5, 1.0, 0.5)
		detail_objectives_list.add_child(comp_label)
	elif quest_status == QWEnums.QuestState.FAILED:
		var fail_label = Label.new()
		fail_label.text = "Quest Failed."
		fail_label.modulate = Color(1.0, 0.5, 0.5)
		detail_objectives_list.add_child(fail_label)
	else:
		for objective in active_objectives:
			if objective.is_hidden:
				continue  #hides hidden objectives
			var obj_label = Label.new()

			var prefix = "[ ] "
			# Check against ObjectiveResource Status Enum (or raw int 2)
			if objective.status == ObjectiveResource.Status.COMPLETED:
				prefix = "[X] "

			var display_text = prefix + tr(objective.description)

			# Add progress counter for items or kills (only when show_counter is enabled)
			var progress_text = ""
			if objective.show_counter:
				match objective.trigger_type:
					ObjectiveResource.TriggerType.ITEM_COLLECT, ObjectiveResource.TriggerType.KILL:
						if not objective.requirements.is_empty():
							var parts: Array[String] = []
							var keys = objective.requirements.keys()
							keys.sort_custom(func(a, b): return str(a) < str(b))
							for key in keys:
								var key_str = str(key)
								if key_str.begins_with("new_target_"):
									continue
								var max_val = objective.requirements[key]
								var current = (
									quest_controller
									. get_objective_manager()
									. get_objective_progress_by_key(objective.id, key)
								)
								var display_name = _get_item_display_name(key_str)
								parts.append("%s (%d/%d)" % [display_name, current, max_val])
							if parts.size() > 0:
								progress_text = " " + " + ".join(parts)

			display_text += progress_text
			obj_label.text = display_text

			if objective.is_optional:
				obj_label.modulate = Color(0.8, 0.8, 0.8)

			detail_objectives_list.add_child(obj_label)


func _get_item_registry() -> Resource:
	if _item_registry != null:
		return _item_registry
	if _item_registry_load_attempted:
		return null
	_item_registry_load_attempted = true
	var settings = QWConstants.get_settings()
	if (
		settings
		and settings.item_registry_path
		and ResourceLoader.exists(settings.item_registry_path)
	):
		_item_registry = ResourceLoader.load(settings.item_registry_path)
	return _item_registry


func _get_item_display_name(item_id: String) -> String:
	var registry = _get_item_registry()
	if registry and registry.has_method(&"find"):
		var def = registry.find(item_id)
		if def and "display_name" in def and def.display_name:
			return str(def.display_name)
	return item_id.capitalize()


func _get_services_safe() -> Node:
	var main_loop = Engine.get_main_loop()
	if main_loop and main_loop.root:
		return main_loop.root.get_node_or_null("QuestWeaverServices")
	return null


func _on_close_button_pressed() -> void:
	self.visible = false
