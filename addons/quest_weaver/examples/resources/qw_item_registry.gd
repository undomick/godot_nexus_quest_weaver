# res://addons/quest_weaver/examples/resources/qw_item_registry.gd
@tool
class_name QWItemRegistry
extends Resource

@export var item_definitions: Array[QWItemDefinition]

## A dictionary containing all item definitions, keyed by their unique ID.
var _definitions_dict: Dictionary = {}
var _is_initialized := false


## Finds an item definition by its ID.
func find(item_id: String) -> QWItemDefinition:
	if not _is_initialized:
		_build_lookup_dict()

	return _definitions_dict.get(item_id)


# This function builds the fast lookup dictionary from the array.
func _build_lookup_dict():
	if _is_initialized:
		return
	_definitions_dict.clear()
	for definition in item_definitions:
		# Safety check in case a slot in the array is empty
		if is_instance_valid(definition) and not definition.id.is_empty():
			_definitions_dict[definition.id] = definition
	_is_initialized = true
