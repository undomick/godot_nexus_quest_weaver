# res://addons/quest_weaver/core/qw_logger.gd
class_name QWLogger

extends RefCounted

var _active_categories: Dictionary = {}

## Runtime logger with category-based filtering.
## Call initialize() once at startup. Categories (Flow, Inventory, System, etc.) are configured in debug_settings.tres.

# category (StringName) -> bool


# This is called once by the QuestController when the game starts.
func initialize() -> void:
	var settings: QuestWeaverDebugSettings
	if ResourceLoader.exists(QWConstants.DEBUG_SETTINGS_PATH):
		# Load the resource fresh from disk to get the latest editor settings.
		settings = ResourceLoader.load(
			QWConstants.DEBUG_SETTINGS_PATH, "", ResourceLoader.CACHE_MODE_REPLACE
		)
		if is_instance_valid(settings):
			_active_categories = settings.active_categories.duplicate()
		else:
			push_warning("QWLogger: Could not load debug_settings.tres. All logs will be printed.")
	else:
		push_warning("QWLogger: Debug settings file not found. All logs will be printed.")


# The main logging function (Info/Debug).
func log(category: StringName, message: String) -> void:
	if _active_categories.get(str(category), true):
		print(_format(category, message))


# Warnings (Always visible + pushed to Debugger)
func warn(category: StringName, message: String) -> void:
	push_warning(_format(category, message))


# Errors (Always visible + pushed to Debugger + Pause on Error potential)
func error(category: StringName, message: String) -> void:
	push_error(_format(category, message))


func _format(category: StringName, message: String) -> String:
	return "[%s] %s" % [str(category).to_upper(), message]
