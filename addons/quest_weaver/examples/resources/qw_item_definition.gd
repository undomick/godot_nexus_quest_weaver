# res://addons/quest_weaver/examples/resources/qw_item_definition.gd
class_name QWItemDefinition

extends Resource

## The unique identifier for this item, e.g., "health_potion".
@export var id: String

## The name displayed to the player, e.g., "Health Potion".
@export var display_name: String

## The visual icon for the UI.
@export var icon: Texture2D

## A short description of the item.
@export_multiline var description: String

## The maximum number of this item that can be in a single stack.
@export_range(1, 999) var max_stack_size: int = 1
