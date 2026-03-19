# res://addons/quest_weaver/nodes/flow/parallel_node/parallel_node_resource.gd
@tool
class_name ParallelNodeResource
extends GraphNodeResource

@export var keep_listening: bool = true
@export var outputs: Array[ParallelOutputPort] = []


func _init():
	category = "Flow"
	input_ports = ["In"]

	if id.is_empty() and outputs.is_empty():
		var out1 = ParallelOutputPort.new()
		out1.port_name = "Out 1"
		var out2 = ParallelOutputPort.new()
		out2.port_name = "Out 2"
		outputs.append(out1)
		outputs.append(out2)

	_update_ports_from_data()


func get_description() -> String:
	return "Splits the execution flow into multiple branches. All connected outputs are triggered simultaneously."


func get_icon() -> Texture2D:
	return preload("res://addons/quest_weaver/assets/icons/parallel.svg")


func add_parallel_output(_payload: Dictionary):
	var new_output = ParallelOutputPort.new()
	new_output.port_name = "Out %d" % (outputs.size() + 1)
	outputs.append(new_output)
	_update_ports_from_data()


func remove_parallel_output(payload: Dictionary):
	if payload.has("index") and payload.index >= 0 and payload.index < outputs.size():
		outputs.remove_at(payload.index)
		_update_ports_from_data()


func update_parallel_port_name(payload: Dictionary):
	if payload.has("index") and payload.has("new_name"):
		var index = payload.get("index")
		if index >= 0 and index < outputs.size():
			outputs[index].port_name = payload.get("new_name")
			_update_ports_from_data()


func update_parallel_condition_property(payload: Dictionary):
	if payload.has_all(["index", "property_name", "new_value"]):
		var index = payload.get("index")
		if index >= 0 and index < outputs.size() and is_instance_valid(outputs[index].condition):
			outputs[index].condition.set(payload.get("property_name"), payload.get("new_value"))
			_update_ports_from_data()  # Update hints


func change_parallel_condition_type(payload: Dictionary):
	if payload.has_all(["index", "new_script"]):
		var index = payload.get("index")
		var new_script = payload.get("new_script")
		if index >= 0 and index < outputs.size() and is_instance_valid(new_script):
			outputs[index].condition = new_script.new()
			_update_ports_from_data()  # Update hints


func _update_ports_from_data():
	output_ports.clear()
	for output_info in outputs:
		if is_instance_valid(output_info):
			var port_text = output_info.port_name
			var condition: ConditionResource = output_info.condition

			if (
				is_instance_valid(condition)
				and not (
					condition.type == ConditionResource.ConditionType.BOOL and condition.is_true
				)
			):
				var hint_text = ""
				match condition.type:
					ConditionResource.ConditionType.BOOL:
						hint_text = "BOOL"
					ConditionResource.ConditionType.CHANCE:
						hint_text = "RNG"
					ConditionResource.ConditionType.CHECK_ITEM:
						hint_text = "ITEM"
					ConditionResource.ConditionType.CHECK_QUEST_STATUS:
						hint_text = "QUEST"
					ConditionResource.ConditionType.CHECK_VARIABLE:
						hint_text = "VAR"
					ConditionResource.ConditionType.CHECK_OBJECTIVE_STATUS:
						hint_text = "OBJ"
					ConditionResource.ConditionType.CHECK_OBJECTIVE_REQUIREMENT:
						hint_text = "REQ"
					ConditionResource.ConditionType.COMPOUND:
						hint_text = "AND/OR"

				if not hint_text.is_empty():
					port_text += " (%s)" % hint_text

			output_ports.append(port_text)


func to_dictionary() -> Dictionary:
	var data = super.to_dictionary()
	data["keep_listening"] = keep_listening
	var outputs_data = []
	for o in self.outputs:
		if is_instance_valid(o):
			outputs_data.append(o.to_dictionary())
	data["outputs"] = outputs_data
	return data


func from_dictionary(data: Dictionary):
	super.from_dictionary(data)
	keep_listening = data.get("keep_listening", true)
	self.outputs.clear()
	for o_data in data.get("outputs", []):
		var script = GraphNodeResource.get_script_cached(o_data.get("@script_path"))
		if script:
			var new_o = script.new()
			new_o.from_dictionary(o_data)
			self.outputs.append(new_o)


func determine_default_size() -> QWNodeSizes.Size:
	return QWNodeSizes.Size.TOWER
