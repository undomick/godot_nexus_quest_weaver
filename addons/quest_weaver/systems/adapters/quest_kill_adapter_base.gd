# res://addons/quest_weaver/systems/adapters/quest_kill_adapter_base.gd
@tool
class_name QuestKillAdapterBase
extends RefCounted

## ABSTRACT BASE CLASS (CONTRACT)
##
## Defines the interface that a kill-tracking system must implement
## so KILL objectives can use track_progress_since_activation (polling).
## Override count_kill in a concrete adapter class.

signal kills_updated


## Returns the TOTAL number of kills for a specific enemy (e.g. game-wide statistic).
func count_kill(_enemy_id: StringName) -> int:
	push_warning("The count_kill function has not been implemented in the concrete kill adapter.")
	return 0


## Is called by the QuestController when the adapter is initialized.
func initialize() -> void:
	pass
