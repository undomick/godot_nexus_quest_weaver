# res://addons/quest_weaver/nodes/common/backdrop/backdrop_node_editor.gd
@tool

extends NodePropertyEditorBase

# --- Signals (preview = live update during drag, no undo) ---
signal property_preview_requested(node_id: StringName, property_name: String, value: Variant)

# --- State for Undo/Redo ---
# Stores the font size value before a slider drag starts to create a clean undo action.
var _font_size_undo_value: int = 24

# --- UI References ---
@onready var color_picker: ColorPickerButton = %ColorPicker

@onready var title_edit: LineEdit = %TitleEdit

@onready var text_edit: TextEdit = %TextEdit

@onready var font_size_slider: HSlider = %FontSizeSlider

@onready var font_size_label: Label = %FontSizeLabel

# --- Godot Functions ---


func _ready() -> void:
	# Connect signals for all property controls.
	title_edit.text_submitted.connect(func(_text): _on_title_confirmed())
	title_edit.focus_exited.connect(_on_title_confirmed)
	text_edit.focus_exited.connect(_on_text_confirmed)
	color_picker.popup_closed.connect(_on_color_confirmed)

	# Connect slider signals for a robust undo/redo experience.
	font_size_slider.value_changed.connect(_on_font_size_slider_value_changed)
	font_size_slider.drag_started.connect(_on_font_size_drag_started)
	font_size_slider.drag_ended.connect(_on_font_size_drag_ended)


# --- Public API ---

# Populates the editor controls with data from the given node resource.


func set_node_data(node_data: GraphNodeResource) -> void:
	super.set_node_data(node_data)
	if not node_data is BackdropNodeResource:
		return

	title_edit.text = node_data.title
	text_edit.text = node_data.text
	color_picker.color = node_data.color

	# Update the slider and its label with the data from the resource,
	# without triggering their 'value_changed' signals during setup.
	font_size_slider.set_value_no_signal(node_data.title_font_size)
	font_size_label.text = str(node_data.title_font_size)


# --- Signal Handlers ---

# Called when the user confirms the title by pressing Enter or losing focus.


func _on_title_confirmed() -> void:
	var current_text = title_edit.text
	if is_instance_valid(edited_node_data) and edited_node_data.title != current_text:
		property_update_requested.emit(edited_node_data.id, "title", current_text, null, {})


# Called when the user confirms the description text by losing focus.
func _on_text_confirmed() -> void:
	var current_text = text_edit.text
	if is_instance_valid(edited_node_data) and edited_node_data.text != current_text:
		property_update_requested.emit(edited_node_data.id, "text", current_text, null, {})


# Called when the user closes the color picker popup.
func _on_color_confirmed() -> void:
	var new_color = color_picker.color
	if is_instance_valid(edited_node_data) and edited_node_data.color != new_color:
		property_update_requested.emit(edited_node_data.id, "color", new_color, null, {})


# Called continuously while the slider is being dragged.
# Update the label and emit preview so the graph backdrop title size updates live.
func _on_font_size_slider_value_changed(new_value: float) -> void:
	font_size_label.text = str(int(new_value))
	if is_instance_valid(edited_node_data):
		property_preview_requested.emit(edited_node_data.id, "title_font_size", int(new_value))


# Called once when the user starts dragging the slider.
# We store the initial value here for the final undo/redo action.
func _on_font_size_drag_started() -> void:
	if is_instance_valid(edited_node_data):
		_font_size_undo_value = edited_node_data.title_font_size


# Called once when the user releases the slider.
# This is where the actual property change is emitted and the undo action is created.
func _on_font_size_drag_ended(value_was_changed: bool) -> void:
	# Do nothing if the value didn't actually change.
	if not value_was_changed:
		return

	var final_size = int(font_size_slider.value)

	# Before emitting the change, we revert the visual label to its original state.
	# The history manager will then correctly set the new value upon command execution.
	font_size_label.text = str(_font_size_undo_value)

	if is_instance_valid(edited_node_data) and _font_size_undo_value != final_size:
		property_update_requested.emit(edited_node_data.id, "title_font_size", final_size, null, {})
