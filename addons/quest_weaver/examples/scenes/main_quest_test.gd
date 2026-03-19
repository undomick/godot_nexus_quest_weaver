# res://addons/quest_weaver/examples/scenes/main_quest_test.gd
extends Node

var inventory_controller: Node

var qw_global = null

@onready var quest_log_ui: QuestLogUI = %QuestLogUI

@onready var journal_button: Button = %JournalButton

@onready var lang_opt_button: OptionButton = %LangOptButton

@onready var inventory_amount: Label = %InventoryAmount

# Old Man Nestor
@onready var mq_vbox_container: VBoxContainer = %MQ_VBoxContainer

@onready var old_man_talk_button: Button = %OldManTalkButton

@onready var old_man_kill_button: Button = %OldManKillButton

@onready var collect_v_box_container: VBoxContainer = %CollectVBoxContainer

# Young Lady Lydia
@onready var mq_vbox_container_2: VBoxContainer = %MQ_VBoxContainer2

@onready var lady_talk_button: Button = %LadyTalkButton

@onready var lady_kill_button: Button = %LadyKillButton

@onready var lady_spare_button: Button = %LadySpareButton

# This scene demonstrates how to interact with the QuestWeaver system from your game.
# It uses a safe access pattern to avoid errors if the plugin is not yet enabled.
#
# SIGNAL EXAMPLES (emit these from your game code):
#   quest_event_fired:     QuestWeaverGlobal.quest_event_fired.emit("my_event", {"key": "value"})
#   enemy_was_killed:      QuestWeaverGlobal.enemy_was_killed.emit("rat")
#   interacted_with_object: QuestWeaverGlobal.interacted_with_object.emit(my_npc_node)  # For INTERACT objectives
#   entered_location:      QuestWeaverGlobal.entered_location.emit("tavern")            # For ENTER_LOCATION objectives

# Adventure related stuff


func _ready() -> void:
	# We find the inventory controller when the scene starts.
	# The adapter looks for it via the group, so we do the same here.
	inventory_controller = get_tree().get_first_node_in_group("inventory_controller")
	if not is_instance_valid(inventory_controller):
		push_error("Test Scene: Could not find the 'inventory_controller' in the scene!")
	else:
		if inventory_controller.has_signal("inventory_changed"):
			inventory_controller.inventory_changed.connect(_update_rewards_display)
		_update_rewards_display()

	# Hide on startup
	collect_v_box_container.visible = false
	old_man_kill_button.visible = false
	lady_spare_button.visible = false
	mq_vbox_container_2.visible = false

	# button logic
	old_man_talk_button.pressed.connect(_on_old_man_talked)
	old_man_kill_button.pressed.connect(_on_kill_nestor)
	lady_talk_button.pressed.connect(_on_lady_talked)
	lady_kill_button.pressed.connect(_on_kill_lydia)

	# Listen to the global quest weaver events.
	# We use a safe lookup here to prevent errors during plugin installation.
	# In your own game, you can simply write: QuestWeaverGlobal.quest_event_fired.connect(...)
	qw_global = _get_global_bus()
	if qw_global:
		qw_global.quest_event_fired.connect(_on_quest_event)


func _on_quest_event(event_name: String, _payload: Dictionary) -> void:
	if event_name == "enable_collect_ui":
		collect_v_box_container.visible = true
	if event_name == "disable_collect_ui":
		collect_v_box_container.visible = false
	if event_name == "enable_lydia_ui":
		mq_vbox_container_2.visible = true
	if event_name == "enable_kill_nestor_button":
		old_man_kill_button.visible = true
	if event_name == "end_the_game":
		get_tree().quit()


func _on_old_man_talked() -> void:
	if qw_global && !qw_global.is_locked:
		print("Demo: Interact with Old Man...")
		qw_global.quest_event_fired.emit("interact_old_man", {})


func _on_lady_talked() -> void:
	if qw_global && !qw_global.is_locked:
		print("Demo: Interact with Lady...")
		qw_global.quest_event_fired.emit("interact_lady", {})


func _on_kill_nestor() -> void:
	if qw_global && !qw_global.is_locked:
		print("Demo: Nestor was killed!")
		qw_global.enemy_was_killed.emit("nestor")

	old_man_talk_button.disabled = true
	old_man_kill_button.disabled = true
	lady_kill_button.disabled = true
	lady_spare_button.disabled = true

	if mq_vbox_container:
		mq_vbox_container.modulate = Color(0.0, 0.0, 0.0, 0.25)


func _on_kill_lydia() -> void:
	if qw_global && !qw_global.is_locked:
		print("Demo: Lydia was killed")
		qw_global.enemy_was_killed.emit("lydia")

	old_man_kill_button.disabled = true
	lady_kill_button.disabled = true
	lady_spare_button.disabled = true
	lady_talk_button.disabled = true

	if mq_vbox_container_2:
		mq_vbox_container_2.modulate = Color(0.0, 0.0, 0.0, 0.25)


func _update_rewards_display() -> void:
	if not is_instance_valid(inventory_controller) or not is_instance_valid(inventory_amount):
		return
	if not inventory_controller.has_method("get_all_items"):
		return
	var items: Dictionary = inventory_controller.get_all_items()
	if items.is_empty():
		inventory_amount.text = "—"
		return
	var parts: PackedStringArray = []
	for item_id in items.keys():
		parts.append("%s × %d" % [item_id, items[item_id]])
	inventory_amount.text = ", ".join(parts)


func _on_collect_item(item_id: String, amount: int) -> void:
	if is_instance_valid(inventory_controller):
		inventory_controller.give_item(item_id, amount)
		print("Demo: Player collect %d x %s" % [amount, item_id])


func _on_journal_button_pressed() -> void:
	quest_log_ui.visible = true


func _on_collect_button_1_pressed() -> void:
	_on_collect_item("wood", 1)


func _on_collect_button_2_pressed() -> void:
	_on_collect_item("iron", 1)


func _on_collect_button_3_pressed() -> void:
	_on_collect_item("silk", 1)


func _on_collect_button_4_pressed() -> void:
	_on_collect_item("meat", 1)


# Helper to get the singleton safely without breaking compilation on first import
func _get_global_bus() -> Node:
	return get_tree().root.get_node_or_null("QuestWeaverGlobal")
