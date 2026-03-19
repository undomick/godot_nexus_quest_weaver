# res://addons/quest_weaver/core/qw_condition_logic.gd
class_name QWConditionLogic
extends RefCounted

## Central logic for comparing values.
## Maps to ConditionResource.Operator and EventListenerNodeResource.SimpleOperator (Indices 0-5).
enum Op { EQUALS, NOT_EQUALS, GREATER_THAN, LESS_THAN, GREATER_OR_EQUAL, LESS_OR_EQUAL }


## Returns false if val_a is null or types are incompatible. Supports numeric coercion (int/float). Use QWConditionLogic.Op enum (indices 0-5).
static func compare(val_a: Variant, val_b: Variant, op: int) -> bool:
	if val_a == null:
		return false
	if (
		val_b == null
		and op in [Op.GREATER_THAN, Op.LESS_THAN, Op.GREATER_OR_EQUAL, Op.LESS_OR_EQUAL]
	):
		return false

	# Numeric safety: Allow comparison between int and float
	if typeof(val_a) != typeof(val_b):
		var is_num_a = val_a is float or val_a is int
		var is_num_b = val_b is float or val_b is int
		if not (is_num_a and is_num_b):
			return false

	match op:
		Op.EQUALS:
			return val_a == val_b
		Op.NOT_EQUALS:
			return val_a != val_b
		Op.GREATER_THAN:
			return val_a > val_b
		Op.LESS_THAN:
			return val_a < val_b
		Op.GREATER_OR_EQUAL:
			return val_a >= val_b
		Op.LESS_OR_EQUAL:
			return val_a <= val_b

	return false


## Parses a string to int, float, bool, or returns the string as-is. Empty string returns "".
static func parse_string_to_variant(text: String) -> Variant:
	if text.is_valid_int():
		return text.to_int()
	if text.is_valid_float():
		return text.to_float()
	var lower = text.to_lower()
	if lower == "true":
		return true
	if lower == "false":
		return false
	return text
