# res://addons/quest_weaver/editor/qw_editor_utils.gd
@tool
class_name QWEditorUtils
extends RefCounted

static var _cached_item_ids: Array[String] = []
static var _cached_quest_ids: Array[String] = []
static var _item_registry_loaded := false
static var _quest_registry_loaded := false
## Callable that returns the current active graph (set by editor). Used for refresh on first focus.
static var _get_active_graph_callback: Callable = Callable()

## Clears the internal cache, forcing a reload from disk on the next call.
static func clear_cache() -> void:
	_cached_item_ids.clear()
	_cached_quest_ids.clear()
	_item_registry_loaded = false
	_quest_registry_loaded = false

## Populates an AutoCompleteLineEdit with all item IDs from the registry.
static func populate_item_completer(completer: AutoCompleteLineEdit):
	if not _item_registry_loaded:
		_load_item_registry_data()
	completer.set_items(_cached_item_ids)

## Populates an AutoCompleteLineEdit with all quest IDs from the registry.
## Call refresh_quest_id_cache_for_graph when opening a graph so unsaved quest IDs appear.
static func populate_quest_id_completer(completer: AutoCompleteLineEdit):
	if not _quest_registry_loaded:
		_load_quest_registry_data()
	completer.set_items(_cached_quest_ids)

## Sets the callback used to resolve the active graph (e.g. from QuestWeaverEditor).
static func set_active_graph_callback(cb: Callable) -> void:
	_get_active_graph_callback = cb

## Refreshes quest ID cache from the active graph then repopulates the completer.
## Call on first focus in quest-ID fields so autocomplete works for clean/unsaved quests.
static func refresh_quest_id_completer_from_active_graph(completer: AutoCompleteLineEdit) -> void:
	if _get_active_graph_callback.is_valid():
		var graph = _get_active_graph_callback.call()
		refresh_quest_id_cache_for_graph(graph)
	populate_quest_id_completer(completer)

## Merges quest IDs from the graph's QuestContextNodes into the cache.
## Enables autocomplete for current/unsaved quests. Call on active_graph_changed.
static func refresh_quest_id_cache_for_graph(graph: QuestGraphResource) -> void:
	if not is_instance_valid(graph): return
	if not _quest_registry_loaded:
		_load_quest_registry_data()
	for node_data in graph.nodes.values():
		var qid_val = node_data.get("quest_id")
		if qid_val != null and str(qid_val) != "":
			var qid = str(qid_val)
			if not _cached_quest_ids.has(qid):
				_cached_quest_ids.append(qid)
				_cached_quest_ids.sort()

# Internal function to load item data and fill the cache.
static func _load_item_registry_data() -> void:
	_cached_item_ids.clear()
	_item_registry_loaded = true 

	if not is_instance_valid(QWConstants.get_settings()) or QWConstants.get_settings().item_registry_path.is_empty():
		_cached_item_ids.append("!Error: Item Registry path not set!")
		return
		
	var item_registry = ResourceLoader.load(QWConstants.get_settings().item_registry_path)
	if not is_instance_valid(item_registry):
		_cached_item_ids.append("!Error: Could not load Item Registry!")
		return
		
	var all_ids: Array[String] = []
	if "item_definitions" in item_registry and item_registry.item_definitions is Array:
		for definition in item_registry.item_definitions:
			if is_instance_valid(definition) and not definition.id.is_empty():
				all_ids.append(definition.id)
	
	if all_ids.is_empty():
		_cached_item_ids.append("(Registry is empty)")
	else:
		_cached_item_ids = all_ids

# Internal function to load quest data and fill the cache.
static func _load_quest_registry_data() -> void:
	_cached_quest_ids.clear()
	_quest_registry_loaded = true

	if QWConstants.get_settings().quest_registry_path.is_empty() or not ResourceLoader.exists(QWConstants.get_settings().quest_registry_path):
		_cached_quest_ids.append("!Error: Quest Registry path not set!")
		return
	
	var registry: QuestRegistry = ResourceLoader.load(QWConstants.get_settings().quest_registry_path, "QuestRegistry", ResourceLoader.CACHE_MODE_REPLACE)
	
	if is_instance_valid(registry):
		if registry.quest_path_map.is_empty():
			_cached_quest_ids.append("(No Quests found. Save a graph with an ID)")
		else:
			var raw_ids = registry.get_all_ids()
			for id in raw_ids:
				_cached_quest_ids.append(str(id))
	else:
		_cached_quest_ids.append("!Error: Could not load Quest Registry!")
