# res://addons/quest_weaver/nodes/flow/random_node/random_node_resource.gd
@tool
class_name RandomNodeResource
extends GraphNodeResource

@export var outputs: Array[RandomOutputPort] = []


func _init():
	category = "Flow"
	input_ports = ["In"]

	# Initialize with default outputs if none exist
	if id.is_empty() and outputs.is_empty():
		var out1 = RandomOutputPort.new()
		out1.port_name = "Choice A"
		out1.weight = 50
		var out2 = RandomOutputPort.new()
		out2.port_name = "Choice B"
		out2.weight = 50
		outputs.append(out1)
		outputs.append(out2)

	_update_ports_from_data()


func _update_ports_from_data():
	output_ports.clear()
	var total_weight = _get_total_weight()

	for output_port_info in outputs:
		if is_instance_valid(output_port_info):
			if total_weight > 0:
				var chance = int(float(output_port_info.weight) / total_weight * 100.0)
				output_ports.append("%s (%d%%)" % [output_port_info.port_name, chance])
			else:
				output_ports.append("%s (N/A)" % output_port_info.port_name)


func _get_total_weight() -> int:
	var total = 0
	for output_port_info in outputs:
		if is_instance_valid(output_port_info):
			total += output_port_info.weight
	return total


func get_editor_summary() -> String:
	var total_weight = _get_total_weight()
	if total_weight <= 0:
		return "[NO VALID CHOICES]"
	else:
		return ""


func get_description() -> String:
	return "Selects one output path randomly based on weighted probabilities."


func get_icon() -> Texture2D:
	return preload("res://addons/quest_weaver/assets/icons/random.svg")


# ==============================================================================
# EDITOR API - Called by RandomNodeEditor
# ==============================================================================


func add_random_output(_payload: Dictionary):
	var new_output = RandomOutputPort.new()
	# Generate default name like "Choice A", "Choice B", "Choice C"...
	new_output.port_name = "Choice %s" % (char(65 + outputs.size()))
	outputs.append(new_output)
	_update_ports_from_data()


func remove_random_output(payload: Dictionary):
	if payload.has("index") and payload.index >= 0 and payload.index < outputs.size():
		outputs.remove_at(payload.index)
		_update_ports_from_data()


func update_random_output_name(payload: Dictionary):
	if payload.has("index") and payload.has("new_name"):
		var index = payload.get("index")
		if index >= 0 and index < outputs.size():
			outputs[index].port_name = payload.get("new_name")
			_update_ports_from_data()


func update_random_output_weight(payload: Dictionary):
	if payload.has("index") and payload.has("new_weight"):
		var index = payload.get("index")
		if index >= 0 and index < outputs.size():
			outputs[index].weight = payload.get("new_weight")
			_update_ports_from_data()


# ==============================================================================
# SERIALIZATION
# ==============================================================================


func to_dictionary() -> Dictionary:
	var data = super.to_dictionary()
	var outputs_data = []
	for o in self.outputs:
		if is_instance_valid(o):
			outputs_data.append(o.to_dictionary())
	data["outputs"] = outputs_data
	return data


func from_dictionary(data: Dictionary):
	super.from_dictionary(data)
	self.outputs.clear()
	for o_data in data.get("outputs", []):
		var script = GraphNodeResource.get_script_cached(o_data.get("@script_path"))
		if script:
			var new_o = script.new()
			new_o.from_dictionary(o_data)
			self.outputs.append(new_o)


func determine_default_size() -> QWNodeSizes.Size:
	return QWNodeSizes.Size.TOWER
