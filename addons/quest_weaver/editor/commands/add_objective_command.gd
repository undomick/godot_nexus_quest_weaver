# res://addons/quest_weaver/editor/commands/add_objective_command.gd
@tool
class_name AddObjectiveCommand
extends EditorCommand

var _task_node: TaskNodeResource
var _objective_to_add: ObjectiveResource


# If no objective is passed, a new one will be created.
func _init(p_task_node: TaskNodeResource, p_objective: ObjectiveResource = null):
	self._task_node = p_task_node
	self._objective_to_add = p_objective


func execute() -> void:
	# If this is the first execution (not a redo), create a new objective.
	if not is_instance_valid(_objective_to_add):
		_objective_to_add = ObjectiveResource.new()
		_objective_to_add.id = "objective_%d" % Time.get_unix_time_from_system()
		_objective_to_add.description = "New Objective"

	_task_node.objectives.append(_objective_to_add)


func undo() -> void:
	_task_node.objectives.erase(_objective_to_add)
