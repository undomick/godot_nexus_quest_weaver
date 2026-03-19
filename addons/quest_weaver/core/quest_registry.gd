## Populated by QuestRegistrar; used by Validator, Controller, and editor autocomplete.
@tool

class_name QuestRegistry

extends Resource

## Maps Logical Quest IDs to their resource file paths.
## Format: { "kill_rats_main": "res://quests/act_1/rats.quest" }
@export var quest_path_map: Dictionary = {}

# res://addons/quest_weaver/core/quest_registry.gd
## Resource that maps logical quest IDs to their .quest file paths.


## Returns all quest IDs from quest_path_map. Used for autocomplete and dropdowns.
func get_all_ids() -> Array:
	return quest_path_map.keys() if quest_path_map else []
