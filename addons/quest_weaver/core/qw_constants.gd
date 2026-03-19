# res://addons/quest_weaver/core/qw_constants.gd
class_name QWConstants
extends RefCounted

## Central constants and static resource loaders for Quest-Weaver.
## Call clear_static_references() before plugin shutdown.

# ==============================================================================
# UI Scenes (.tscn) - Preloaded for instantiation
# ==============================================================================
const MainViewScene = preload("../editor/quest_weaver_editor.tscn")
const ValidatorDockScene = preload("../editor/validation/validator_dock.tscn")
const AutoCompleteLineEditScene = preload("../editor/components/auto_complete_line_edit.tscn")
const QuestFileDialogScene = preload("../editor/dialogs/quest_file_dialog.tscn")
const QuestConfirmationDialogScene = preload("../editor/dialogs/quest_confirmation_dialog.tscn")
const ObjectiveEditorEntryScene = preload("../editor/conditions/objective_editor_entry.tscn")
const ItemStackEntryScene = preload("../editor/components/item_stack_entry.tscn")
const RewardEntryScene = preload("../editor/components/reward_entry.tscn")

# Editor Scenes for specific components
const OutputEntryScene = preload("../editor/components/parallel_output_editor_entry.tscn")
const RandomOutputEntryScene = preload("../editor/components/random_output_editor_entry.tscn")
const SyncInputEntryScene = preload("../editor/components/synchronize_input_editor_entry.tscn")
const SyncOutputEntryScene = preload("../editor/components/synchronize_output_editor_entry.tscn")
const SyncConditionEditorScene = preload("../editor/conditions/synchronize_condition_editor.tscn")
const SimpleConditionEntryScene = preload("../editor/components/simple_condition_entry.tscn")

# ==============================================================================
# Strings, Paths & Identifiers
# ==============================================================================
const VALIDATOR_DOCK_NAME = "QuestWeaverValidatorDock"
const MODIFIED_SUFFIX = " (*)"
const FILE_EXTENSION = "quest"
const ICON_PATH = "res://addons/quest_weaver/assets/icons/icon.svg"
const RESOURCE_TYPE_NAME = "QuestWeaver.QuestGraph"
const DEBUG_SETTINGS_PATH = "res://addons/quest_weaver/core/debug_settings.tres"
const QUEST_CONTEXT_NODE_SCRIPT_PATH = "res://addons/quest_weaver/nodes/logic/quest_context_node/quest_context_node_resource.gd"

# ==============================================================================
# Data Structures
# ==============================================================================
const TRANSLATABLE_FIELDS = {
	"quest_context_node_resource": ["quest_title", "quest_description", "log_on_start"],
	"text_node_resource": ["text_content"],
	"objective_resource": ["description"],
	"show_ui_message_node_resource": ["title_override", "message_override"]
}

# ==============================================================================
# Settings & Resources
# ==============================================================================
static var _settings: QuestWeaverSettings = null
static var _graph_node_category: GraphNodeCategory = null
static var _is_shutting_down: bool = false


## Returns QuestWeaverSettings resource. Returns null if settings file is missing or during shutdown. Callers must use is_instance_valid().
static func get_settings() -> QuestWeaverSettings:
	if _is_shutting_down:
		return null
	if not is_instance_valid(_settings):
		_settings = (
			ResourceLoader.load("res://addons/quest_weaver/quest_weaver_settings.tres")
			as QuestWeaverSettings
		)
		if not is_instance_valid(_settings):
			push_warning("QWConstants: Could not load quest_weaver_settings.tres.")
	return _settings


## Returns GraphNodeCategory resource. Returns null if file is missing or during shutdown. Callers must use is_instance_valid().
static func get_graph_node_category() -> GraphNodeCategory:
	if _is_shutting_down:
		return null
	if not is_instance_valid(_graph_node_category):
		_graph_node_category = (
			ResourceLoader.load("res://addons/quest_weaver/assets/graph_node_category.tres")
			as GraphNodeCategory
		)
		if not is_instance_valid(_graph_node_category):
			push_warning("QWConstants: Could not load graph_node_category.tres.")
	return _graph_node_category


static func clear_static_references():
	# Explicitly set to null to drop the static reference count
	_is_shutting_down = true
	_settings = null
	_graph_node_category = null
