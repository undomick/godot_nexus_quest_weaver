# res://addons/quest_weaver/core/qw_enums.gd
class_name QWEnums
extends RefCounted

## Central repository for enums used throughout the Quest Weaver plugin
## to avoid dependencies on external game state scripts.

enum QuestState {
	UNAVAILABLE, # 0 Hidden / Not discovered
	AVAILABLE,   # 1 Visible on Quest Board / Minimap, but logic not running
	ACTIVE,      # 2 Running
	COMPLETED,   # 3 Done
	FAILED       # 4 Failed
}
