# Changelog

All notable changes to Quest Weaver are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [1.5.0] – 2025-03-19

### Added

- **Pool Pattern**: Quest states (UNAVAILABLE, AVAILABLE, ACTIVE, COMPLETED, FAILED) are now managed via explicit pools. New `BaseQuestPool` and `QuestPoolRegistry` in `core/pools/` provide extensible state management and O(1) instance lookup.
- **Extensible Custom Pools**: Settings support `additional_pool_scripts` to register custom pools. API: `move_quest_to_custom_pool()`, `get_quests_in_pool()`, `get_all_custom_pool_ids()` in `QuestController` and `QuestWeaverGlobal`. Custom pools persist in save data.
- **Settings Drag & Drop**: `additional_pool_scripts` supports file picker and drag & drop in the Inspector (like other settings).
- **Set Quest Node**: New action "Move to Custom Pool" with pool dropdown populated from `additional_pool_scripts`. Enables moving quests to custom pools directly from quest graphs.
- **Save Format v1.5**: Save data now includes `pool_state` for clean separation of pool placement and instance data. Old saves (version < 1.5) are migrated automatically using stored status.
- **All Complete Flow Node**: Waits for all of multiple parallel inputs before continuing. Complements Any Complete; configurable 1–16 input ports.
- **Switch Flow Node**: Variable-based multi-way branch. Reads a GameState/QuestInstance variable and routes to the matching case or Default output. Configurable cases (value string + port name).
- **Cancel Scope Logic Node**: Aborts a scope from outside by cleaning up all nodes in the target scope without restarting. Flow continues via output; useful for quest abandonment, timeouts, or interrupt events.

### Changed

- **QuestController**: Replaced `_runtime_instances` with `_pool_registry`. All status transitions use `move_instance_to_pool`. Public API unchanged.
- **QuestStatePersistenceManager**: SAVE_VERSION bumped to 1.5; `pool_state_as_dict()` / `restore_from_data()` with migration for legacy format.
- **Performance Monitors**: Now read from pool counts instead of iterating instances.
- **Side Panel**: Folder scan limited to 500 files.
- **Quest Registrar**: Scan limited to 2000 quests when updating registry; iterative BFS with proper `list_dir_end` cleanup.

### Fixed

- **Node Creation**: Newly created nodes are now correctly selected and inspected (ID consistency between CreateNodeCommand and NodeFactory).
- **Translation Parser**: Corrupt or invalid `.quest` files no longer cause errors during Project → Localization scan.
- **Quest Registrar**: Invalid node data in quest files no longer causes scan failures.

### Known Issues

- **Editor exit warning "1 resources still in use"**: When closing the Godot Editor, you may see `ERROR: 1 resources still in use at exit` referring to `condition_resource.gd`. This is caused by Godot’s GDScriptCache keeping an extra reference to scripts (see [Godot #77513](https://github.com/godotengine/godot/issues/77513)). It affects editor shutdown only and does not impact gameplay. Quest Weaver already avoids `load()` for ConditionResource where possible to reduce cache pressure.

---

## [1.4.0] – 2025-03-13

### Added

- **Waypoint-API / Marker-Hooks**: `get_active_objective_markers()` returns active LOCATION_ENTER and INTERACT objectives for map/minimap integration. Each marker includes `type` ("location"|"interact"), `target` (location_id or node path), `quest_id`, `objective_id`, `description`. Connect to `quest_markers_changed` to refresh when markers change.
- **Performance Benchmark**: Script and scene (`benchmark_runner.tscn`) for profiling QuestWeaver core hot paths. Run via Editor "Run Current Scene" or `godot --path game addons/quest_weaver/core/benchmarks/benchmark_runner.tscn`. Output: `operation,iterations,median_us,p99_us`.
- **Custom Performance Monitors**: In debug builds, the Debugger → Monitors panel shows QuestWeaver metrics: `RuntimeTotal` (all tracked instances), `StateActive`, `StateCompleted`, `StateFailed`, `StateAvailable`, `StateUnavailable`.

### Changed

- **Performance**: Faster objective lookups (`get_objective_progress`, `get_objective_progress_by_key`, `get_objective_status`) – now O(1) instead of O(n) over instances.
- **Performance**: Quest path and node lookups optimized to O(1) via internal caches.
- **Performance**: Reduced debug overhead – instance update payload is only built when the debugger is active (no overhead in release builds).

### Fixed

- **Quest graphs**: Robust connection filtering when loading connections from JSON (String/StringName compatibility).
- **Editor**: Avoids redundant file writes when saving quest graphs that have no unsaved changes.
- **Subquest flows**: Safer dictionary access when completing nodes in nested subquest flows.

---

## [1.3.0] – 2025-03-07

### Added

- **Collapse All Other Categories**: New sidebar context menu option (right-click on category or file) collapses all categories except the focused one, so you can concentrate on one category without closing others from the panel.
- **Quest Board UI**: `QuestBoardUI` widget with `QuestBoardEntry`; displays available quests and starts them via Accept button (`accept_requested` → `start_quest_id`).
- **QuestAction.MARK_AVAILABLE**: Quest Node now supports `MARK_AVAILABLE`; sets quest to available via `set_quest_available()`.
- **Any-Complete Flow Node**: New flow node that continues as soon as the first of multiple parallel inputs completes. Configurable 1–16 input ports; registered in NodeTypeRegistry. (This is a simplified version of Synchronize Node)
- **Accept/Reject API**: Signals `quest_accepted`, `quest_rejected`; API `can_accept_quest()`, `reject_quest_id()`, `add_acceptance_condition()`, `clear_acceptance_conditions()`, `was_quest_rejected()`; `QuestInstance.rejected_by_player` with Save/Load support.

### Fixed

- **Sidebar Category Collapse State**: Collapsed categories stay collapsed when filtering in the search field; clearing the search no longer expands all categories.
- **REWARD_FROM_QUEST**: Re-enabled; quest rewards are now handed out correctly when objectives are completed.

---

## [1.2.0] – 2025-03-01

### Added

- **EditorTranslationParserPlugin**: Integration in Godot’s standard localization pipeline. `.quest` files are now recognized by Project → Localization.
- **Debugger Viewer Tab**: New “Quest Weaver” tab in the editor debugger shows active instances, status, variables, and objective states while the game runs.
- **Pool API**: `get_active_quests()`, `get_completed_quests()`, and `get_failed_quests()` in `QuestWeaverGlobal` and `QuestController`.
- **Review Commands**:
  - **ValidatorDock**: "Validate All Quests" button validates all quests in the Quest Registry at once. "Validate Opened Quests" button validates all quests opened in the side panel.
  - **QuestValidator**: `validate_all_quests_in_registry()` for batch validation; `export_validation_report(format, output_path)` exports reports as JSON or Markdown.
  - **QuestDebugProxy**: `list_quests()` and `list_active_instances()` for runtime debug review.

### Fixed

- **Fire-and-forget cutscenes**: Cutscenes that use the fire-and-forget path no longer fail to complete.
- **Save data**: Corrupt or invalid save data is now handled correctly instead of causing load failures.
- **Quest loading**: Quests with custom ease settings (`ease_in`/`ease_out`) on ShowUIMessage nodes now load correctly.
- **Scene changes**: Fixed crashes when changing scenes or resetting quests.
- **Condition editor**: Fixed incorrect condition evaluation in some cases; fixed potential crash in synchronize condition editor.
- **Quest graphs**: Quest graphs from older or alternate formats load more reliably.

