# res://addons/quest_weaver/editor/components/tab_focus_text_edit.gd
@tool
class_name TabFocusTextEdit
extends TextEdit

## An extended TextEdit that overrides the default Tab key behavior.
## Instead of inserting a tab character, it moves focus to the next/previous
## control, making it suitable for forms. It handles both Tab and Shift+Tab.


func _gui_input(event: InputEvent) -> void:
	# Intercept keyboard events that are not echoes (e.g., from holding a key down).
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if event.keycode == KEY_TAB:
			get_viewport().set_input_as_handled()

			var neighbor_path: NodePath

			if event.is_shift_pressed():
				# If Shift is held, get the focus neighbor configured for "up".
				neighbor_path = get_focus_neighbor(Side.SIDE_TOP)
			else:
				# Otherwise, get the focus neighbor configured for "down".
				neighbor_path = get_focus_neighbor(Side.SIDE_BOTTOM)

			# Proceed only if a neighbor path is actually configured in the scene.
			if not neighbor_path.is_empty():
				var neighbor_node: Node = get_node_or_null(neighbor_path)

				# Ensure the neighbor exists and is a Control that can receive focus.
				if is_instance_valid(neighbor_node) and neighbor_node is Control:
					var neighbor_control := neighbor_node as Control
					neighbor_control.grab_focus()
