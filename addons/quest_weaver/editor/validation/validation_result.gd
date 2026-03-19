# res://addons/quest_weaver/editor/validation/validation_result.gd
@tool
class_name ValidationResult
extends Resource

enum Severity { ERROR, WARNING, INFO }

var severity: Severity
var message: String
var node_id: StringName
## Human-readable node type (e.g. "Start Scope Node").
var node_type: String = ""
## For batch validation (validate_all_quests_in_registry): path to the quest file containing this result.
var source_quest_path: String = ""


func _init(
	p_severity: Severity,
	p_message: String,
	p_node_id: StringName = &"",
	p_source_quest_path: String = "",
	p_node_type: String = ""
):
	self.severity = p_severity
	self.message = p_message
	self.node_id = p_node_id
	self.source_quest_path = p_source_quest_path
	self.node_type = p_node_type
