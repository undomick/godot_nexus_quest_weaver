# res://addons/quest_weaver/nodes/flow/synchronize_node/synchronize_node_resource.gd
@tool
class_name SynchronizeNodeResource
extends GraphNodeResource

enum InputState { IGNORE = 0, REQUIRED = 1, FORBIDDEN = 2 }
enum LogicMode { EXCLUSIVE, PARALLEL }

@export var keep_listening: bool = true
@export var inputs: Array[SynchronizeInputPort] = []
@export var outputs: Array[SynchronizeOutputPort] = []
@export var logic_mode: LogicMode = LogicMode.EXCLUSIVE


func _init():
	category = "Flow"

	if id.is_empty():
		if inputs.is_empty():
			var in1 = SynchronizeInputPort.new()
			in1.port_name = "In 1"
			var in2 = SynchronizeInputPort.new()
			in2.port_name = "In 2"
			inputs.append(in1)
			inputs.append(in2)

		if outputs.is_empty():
			var out1 = SynchronizeOutputPort.new()
			out1.port_name = "Out"
			outputs.append(out1)

	_ensure_pattern_integrity()
	_update_ports_from_data()


func get_editor_summary() -> String:
	var mode_text = "Priority" if logic_mode == LogicMode.EXCLUSIVE else "Gateway"
	var loop_text = " [Loop]" if keep_listening else ""
	return "Sync (%s)%s\n%d In -> %d Out" % [mode_text, loop_text, inputs.size(), outputs.size()]


func get_description() -> String:
	return "Pattern Matching Gate. \nExclusive: First matching output fires.\nParallel: All matching outputs fire."


func get_icon() -> Texture2D:
	return preload("res://addons/quest_weaver/assets/icons/join.svg")


# ==============================================================================
# EDITOR API - Called by SynchronizeNodeEditor
# ==============================================================================

# --- Inputs ---


func add_sync_input(_payload: Dictionary):
	var new_input = SynchronizeInputPort.new()
	new_input.port_name = "In %d" % (inputs.size() + 1)
	inputs.append(new_input)

	# Add a default IGNORE state for this new input to all existing outputs
	for out in outputs:
		out.patterns.append(InputState.IGNORE)

	_update_ports_from_data()


func remove_sync_input(payload: Dictionary):
	if payload.has("index") and payload.index >= 0 and payload.index < inputs.size():
		inputs.remove_at(payload.index)

		# Remove the corresponding pattern column from all outputs
		for out in outputs:
			if payload.index < out.patterns.size():
				out.patterns.remove_at(payload.index)

		_update_ports_from_data()


func update_sync_input_name(payload: Dictionary):
	if payload.has("index") and payload.has("new_name"):
		var index = payload.get("index")
		if index >= 0 and index < inputs.size():
			inputs[index].port_name = payload.get("new_name")
			_update_ports_from_data()


# --- Outputs ---


func add_sync_output(_payload: Dictionary):
	var new_output = SynchronizeOutputPort.new()
	new_output.port_name = "Out %d" % (outputs.size() + 1)

	# Initialize pattern with IGNORE for current input count
	new_output.patterns.resize(inputs.size())
	new_output.patterns.fill(InputState.IGNORE)

	outputs.append(new_output)
	_update_ports_from_data()


func remove_sync_output(payload: Dictionary):
	if payload.has("index") and payload.index >= 0 and payload.index < outputs.size():
		outputs.remove_at(payload.index)
		_update_ports_from_data()


func update_sync_output_name(payload: Dictionary):
	if payload.has("index") and payload.has("new_name"):
		var index = payload.get("index")
		if index >= 0 and index < outputs.size():
			outputs[index].port_name = payload.get("new_name")
			_update_ports_from_data()


# --- Matrix Logic ---


func update_sync_pattern(payload: Dictionary):
	if payload.has_all(["output_index", "input_index", "state"]):
		var out_idx = payload.output_index
		var in_idx = payload.input_index
		var state = payload.state

		if out_idx >= 0 and out_idx < outputs.size():
			var out = outputs[out_idx]
			# Ensure array size safety
			if in_idx >= 0 and in_idx < out.patterns.size():
				out.patterns[in_idx] = state


# ==============================================================================
# SERIALIZATION
# ==============================================================================


func to_dictionary() -> Dictionary:
	var data = super.to_dictionary()
	data["keep_listening"] = keep_listening
	data["logic_mode"] = self.logic_mode

	var inputs_data = []
	for i in self.inputs:
		if is_instance_valid(i):
			inputs_data.append(i.to_dictionary())
	data["inputs"] = inputs_data

	var outputs_data = []
	for o in self.outputs:
		if is_instance_valid(o):
			outputs_data.append(o.to_dictionary())
	data["outputs"] = outputs_data

	return data


func from_dictionary(data: Dictionary):
	super.from_dictionary(data)
	keep_listening = data.get("keep_listening", true)
	self.logic_mode = _defensive_load(data, "logic_mode", LogicMode.keys(), LogicMode.EXCLUSIVE)

	self.inputs.clear()
	for i_data in data.get("inputs", []):
		var script = GraphNodeResource.get_script_cached(i_data.get("@script_path"))
		if script:
			var new_i = script.new()
			new_i.from_dictionary(i_data)
			self.inputs.append(new_i)

	self.outputs.clear()
	for o_data in data.get("outputs", []):
		var script = GraphNodeResource.get_script_cached(o_data.get("@script_path"))
		if script:
			var new_o = script.new()
			new_o.from_dictionary(o_data)
			self.outputs.append(new_o)

	_ensure_pattern_integrity()


# --- PRIVATE HELPER FUNCTIONS ---


func _ensure_pattern_integrity():
	var needed_size = inputs.size()
	for out in outputs:
		if out.patterns.size() != needed_size:
			var old = out.patterns.duplicate()
			out.patterns.resize(needed_size)
			out.patterns.fill(InputState.IGNORE)

			# Restore what fits
			for i in range(min(old.size(), needed_size)):
				out.patterns[i] = old[i]


func _update_ports_from_data():
	_ensure_pattern_integrity()
	input_ports.clear()
	for port in inputs:
		if is_instance_valid(port):
			input_ports.append(port.port_name)

	output_ports.clear()
	for port in outputs:
		if is_instance_valid(port):
			output_ports.append(port.port_name)


func _defensive_load(data: Dictionary, prop: String, keys: Array, default_val: int) -> int:
	var val = data.get(prop, default_val)
	if val is int and val >= 0 and val < keys.size():
		return val
	return default_val


func determine_default_size() -> QWNodeSizes.Size:
	return QWNodeSizes.Size.TOWER
