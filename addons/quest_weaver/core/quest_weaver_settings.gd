# res://addons/quest_weaver/core/quest_weaver_settings.gd
@tool

class_name QuestWeaverSettings

extends Resource

## Optional: Script paths for additional quest pools (e.g. "Daily", "Seasonal").
## Each script must extend BaseQuestPool. Pool ID is derived from filename (e.g. "daily_pool.gd" -> "daily_pool").
@export var additional_pool_scripts: Array[String] = []

## Optional: Path to a CSV file for localization keys.
## If set, the 'Update Localization Keys' button will scan your quests and append new text keys to this file.
## IMPORTANT: Enter the path manually if the file does not exist yet (e.g. 'res://localization.csv').
@export var localization_csv_path: String = "res://localization.csv"

## Define the language codes (columns) for your CSV file (e.g. "en", "de", "es").
## The first column will always be "keys".
@export var supported_locales: Array[String] = ["en"]

# ==============================================================================
# INTERNAL DATA (Hidden from Inspector)
# ==============================================================================

@export var quest_registry_path: String = "res://addons/quest_weaver/core/quest_registry.tres"

@export var editor_data_path: String = "res://addons/quest_weaver/core/quest_editor_data.tres"

## The folder where you store your '.quest' files.
## Quest Weaver scans this folder to auto-detect Quest IDs for the 'Quest Registry'.
@export_dir var quest_scan_folder: String

## This resource holds all external paths and settings for the Quest Weaver editor.

@export_group("Integration")

## Quest Objectives might need Inventory Logic. The Inventory Adapter provides a way to let
## your Inventory talk with Quest Weaver, without rewriting Quest Weaver itself.
## Your Adapter has to extend 'QuestInventoryAdapterBase'!
@export_file("*.gd") var inventory_adapter_script: String

## KILL objectives can optionally use a Kill Adapter for track_progress_since_activation.
## Your Adapter has to extend 'QuestKillAdapterBase'!
@export_file("*.gd") var kill_adapter_script: String

## Path to the PresentationRegistry resource.
## This defines which UI templates (popup styles) are available for the 'Show UI Message' node.
@export_file("*.tres", "res://") var presentation_registry_path: String

## Path to your Item Registry resource.
## This allows the editor to offer auto-completion for Item IDs in various nodes.
@export_file("*.tres", "res://") var item_registry_path: String

@export_group("Automation")

@export_subgroup("Startup")

## A Quest Graph file (.quest) that should be automatically started when the game begins.
## Useful for "Master Quest" that listen for global events.
@export_file("*.quest", "res://") var auto_start_quests: Array[String] = []

@export_subgroup("Pools")

@export_subgroup("Localization")


func _validate_property(property: Dictionary) -> void:
	# Hide internal paths from the Inspector, but keep them strictly serializable (STORAGE).
	if property.name in [&"quest_registry_path", &"editor_data_path"]:
		property.usage = PROPERTY_USAGE_STORAGE
	# Enable drag & drop / file picker for additional_pool_scripts (Array[String])
	if property.name == &"additional_pool_scripts":
		property.hint = PROPERTY_HINT_TYPE_STRING
		property.hint_string = "%d/%d:*.gd" % [TYPE_STRING, PROPERTY_HINT_FILE]
