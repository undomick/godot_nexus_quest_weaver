# res://addons/quest_weaver/core/node_type_info.gd
@tool

class_name NodeTypeInfo

extends Resource

## Metadata for a graph node type. Used by NodeTypeRegistry for editor UI and executor lookup.
## Role: START (one per graph), NORMAL, END.

enum Role { START, NORMAL, END }

@export var node_name: String

@export var node_script: Script

@export var role: Role = Role.NORMAL

@export var category: String = "Default"

@export var description: String = ""

@export var icon: Texture2D

@export var default_size: QWNodeSizes.Size = QWNodeSizes.Size.MEDIUM

@export_file("*.tscn") var editor_scene_path: String

@export_file("*.gd") var executor_script_path: String
