# res://addons/quest_weaver/editor/commands/composite_command.gd
@tool
class_name CompositeCommand
extends EditorCommand

var _commands: Array[EditorCommand] = []


func add_command(command: EditorCommand) -> void:
	if is_instance_valid(command):
		_commands.append(command)


func execute() -> void:
	for cmd in _commands:
		cmd.execute()


func undo() -> void:
	for i in range(_commands.size() - 1, -1, -1):
		_commands[i].undo()
