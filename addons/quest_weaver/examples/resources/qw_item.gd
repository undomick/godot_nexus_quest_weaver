# res://addons/quest_weaver/examples/resources/qw_item.gd
class_name QWItem
extends RefCounted

var definition: QWItemDefinition
var stack_size: int


func _init(p_definition: QWItemDefinition, p_stack_size: int = 1):
	self.definition = p_definition
	self.stack_size = p_stack_size
