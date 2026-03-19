# res://addons/quest_weaver/systems/adapters/simple_inventory_adapter.gd
@tool
class_name SimpleInventoryAdapter
extends QuestInventoryAdapterBase

var _inventory_controller: Node = null
var _is_initialized_successfully := false


# This function is called by the QuestController at runtime.
func initialize() -> void:
	# We need a reference to the scene tree to find our node.
	# We use Engine.get_main_loop() instead of the Singleton to avoid static dependency issues
	# during the initial plugin loading phase.
	var tree := Engine.get_main_loop() as SceneTree

	if not is_instance_valid(tree):
		push_error(
			"QuestWeaver (SimpleInventoryAdapter): Could not get SceneTree access. Adapter will not function."
		)
		return

	# This adapter expects a node in the scene that belongs to the "inventory_controller" group.
	_inventory_controller = tree.get_first_node_in_group("inventory_controller")

	if not is_instance_valid(_inventory_controller):
		push_warning(
			"QuestWeaver (SimpleInventoryAdapter): No node in group 'inventory_controller' found. Add a node to this group for Give/Take/Check Item nodes to work."
		)
		return

	# Connect to the controller's signal to propagate the update.
	if not _inventory_controller.is_connected(
		&"inventory_changed", Callable(self, "_on_inventory_changed")
	):
		_inventory_controller.inventory_changed.connect(_on_inventory_changed)

	_is_initialized_successfully = true

	# Attempt to log via QuestWeaverServices only if available (dynamic lookup)
	var services = tree.root.get_node_or_null("QuestWeaverServices")
	if is_instance_valid(services) and services.logger:
		services.logger.log("Inventory", "SimpleInventoryAdapter initialized successfully.")


# Called when the controller signals a change.
func _on_inventory_changed() -> void:
	inventory_updated.emit()


# --- ADAPTER METHOD IMPLEMENTATIONS ---
# These functions just pass the call directly to the controller.


func count_item(item_id: StringName) -> int:
	if not _is_initialized_successfully or not is_instance_valid(_inventory_controller):
		return 0
	return _inventory_controller.count_item(str(item_id))


func check_item(item_id: StringName, amount: int) -> bool:
	if not _is_initialized_successfully or not is_instance_valid(_inventory_controller):
		return false
	return _inventory_controller.check_item(str(item_id), amount)


func give_item(item_id: StringName, amount: int) -> void:
	if not _is_initialized_successfully or not is_instance_valid(_inventory_controller):
		return
	_inventory_controller.give_item(str(item_id), amount)


func take_item(item_id: StringName, amount: int) -> bool:
	if not _is_initialized_successfully or not is_instance_valid(_inventory_controller):
		return false
	return _inventory_controller.take_item(str(item_id), amount)
