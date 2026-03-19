# res://addons/quest_weaver/core/qw_enums.gd
class_name QWEnums
extends RefCounted

## Central repository for enums used throughout the Quest Weaver plugin
## to avoid dependencies on external game state scripts.

# 0 Hidden / Not discovered  # 1 Visible on Quest Board / Minimap, but logic not running  # 2 Running  # 3 Done  # 4 Failed  # 5 In a custom pool (see custom_pool_id on QuestInstance)
enum QuestState { UNAVAILABLE, AVAILABLE, ACTIVE, COMPLETED, FAILED, CUSTOM }
