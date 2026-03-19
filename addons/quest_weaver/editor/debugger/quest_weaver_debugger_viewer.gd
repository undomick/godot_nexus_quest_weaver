@tool
class_name QuestWeaverDebuggerViewer
extends VBoxContainer

## Debugger tab that displays active quest instances and their state.
## Receives data via EditorDebuggerPlugin _capture.

var _instances_tree: Tree
var _details_text: TextEdit
var _file_id_to_item: Dictionary = {}


func _get_status_name(status: int) -> String:
	if status >= 0 and status < QWEnums.QuestState.size():
		return QWEnums.QuestState.keys()[status]
	return "UNKNOWN"


func _ready() -> void:
	var header = Label.new()
	header.text = "Quest Weaver - Active Instances"
	header.add_theme_font_size_override("font_size", 14)
	add_child(header)

	_instances_tree = Tree.new()
	_instances_tree.custom_minimum_size.y = 150
	_instances_tree.columns = 3
	_instances_tree.column_titles_visible = true
	_instances_tree.set_column_title(0, "Quest")
	_instances_tree.set_column_title(1, "Status")
	_instances_tree.set_column_title(2, "Active Node Count")
	_instances_tree.item_selected.connect(_on_tree_item_selected)
	add_child(_instances_tree)

	var details_label = Label.new()
	details_label.text = "Details (variables, objectives)"
	add_child(details_label)

	_details_text = TextEdit.new()
	_details_text.custom_minimum_size.y = 120
	_details_text.editable = false
	add_child(_details_text)


func on_capture(message: String, data: Array) -> bool:
	if not is_node_ready() or not _instances_tree:
		return true
	var cmd = message.trim_prefix("quest_weaver:")
	match cmd:
		"register":
			_clear_all()
			return true
		"instance_update":
			if data.size() >= 1 and data[0] is Dictionary:
				_apply_instance_data(data[0])
				return true
	return false


## Clears all displayed data. Call when session stops to avoid showing stale state on next run.
func clear_display() -> void:
	_clear_all()


func _clear_all() -> void:
	_file_id_to_item.clear()
	if _instances_tree:
		_instances_tree.clear()
		_instances_tree.create_item()
	if _details_text:
		_details_text.text = ""


func _apply_instance_data(payload: Dictionary) -> void:
	if not is_node_ready() or not _instances_tree:
		return
	var file_id = str(payload.get("file_id", ""))
	var quest_id = str(payload.get("quest_id", ""))
	var status = int(payload.get("status", 0))
	var variables = payload.get("variables", {})
	var active_nodes = payload.get("active_node_ids", [])
	var objective_states = payload.get("objective_states", {})

	var display_name = quest_id if not quest_id.is_empty() else file_id
	var status_name = _get_status_name(status)

	var item: TreeItem
	if _file_id_to_item.has(file_id):
		item = _file_id_to_item[file_id]
	else:
		item = _instances_tree.create_item()
		_file_id_to_item[file_id] = item

	item.set_text(0, display_name)
	item.set_text(1, status_name)
	item.set_text(2, str(active_nodes.size()))
	item.set_metadata(
		0,
		{
			"file_id": file_id,
			"quest_id": quest_id,
			"status": status,
			"variables": variables,
			"active_node_ids": active_nodes,
			"objective_states": objective_states
		}
	)


func _on_tree_item_selected() -> void:
	var item = _instances_tree.get_selected()
	if not item:
		return
	var meta = item.get_metadata(0)
	if not meta is Dictionary:
		return

	var lines: PackedStringArray = []
	lines.append("=== %s ===" % meta.get("quest_id", meta.get("file_id", "")))
	lines.append("Status: %s" % _get_status_name(meta.get("status", 0)))
	lines.append("")

	var vars_dict = meta.get("variables", {})
	if not vars_dict.is_empty():
		lines.append("--- Variables ---")
		for k in vars_dict:
			lines.append("  %s = %s" % [k, vars_dict[k]])
		lines.append("")

	var active = meta.get("active_node_ids", [])
	if not active.is_empty():
		lines.append("--- Active Nodes ---")
		for n in active:
			lines.append("  %s" % n)
		lines.append("")

	var objs = meta.get("objective_states", {})
	if not objs.is_empty():
		lines.append("--- Objectives ---")
		for k in objs:
			var s = objs[k]
			var st = s.get("status", 0) if s is Dictionary else 0
			lines.append("  %s: %s" % [k, _get_status_name(st)])

	_details_text.text = "\n".join(lines)
