# Quest Weaver – Architecture Overview

## Blueprint & Instance Pattern

Quest Weaver separates **logic (Blueprint)** from **runtime state (Instance)**:

- **QuestGraphResource** – Stateless blueprint: nodes, connections, structure. Stored in `.quest` files.
- **QuestInstance** – Per-quest runtime state: variables, active nodes, objective progress. Not persisted in the quest file.

Save games store only instance data (JSON-compatible). Editing quest logic does not invalidate existing saves.

## Core Components

### Entry Points

- **plugin.gd** – EditorPlugin: Autoloads, Import/Export, Validator, Debugger, Translation Parser
- **QuestWeaverGlobal** – Autoload: Event bus, facade API (start_quest_id, complete_quest_id, get_quest_state, etc.)
- **QuestWeaverServices** – Autoload: Registers Controller, PresentationManager, Logger, GameState
- **QuestWeaverGameState** – Autoload: Variables, quest states, kill counts

### Execution Pipeline

```
QuestController._activate_node() 
  → NodeTypeRegistry.get_executor_for_node() 
  → NodeExecutor.execute(context, node, instance)
  → context.quest_controller.complete_node() (when done)
  → _trigger_next_nodes_from_port()
```

- **QuestController** – Central runtime logic: loads graphs, activates nodes, manages instances
- **ExecutionContext** – Passed to executors: quest_controller, game_state, services, adapters
- **NodeExecutor** – Base class for each node type; sync or async execution

### Managers

- **QuestPoolManager** – Quest pool queries: `get_available_quests()`, `move_quest_to_custom_pool()`, etc. Extracted from QuestController.
- **QuestObjectiveManager** – Objective queries and status: `get_objective_status()`, `get_objective_progress_by_key()`, `set_manual_objective_status()`, etc. Extracted from QuestController.
- **QuestDataManager** – Quest data, instance lookup, presentation: `get_quest_data()`, `get_instance_for_node()`, `add_quest_log_entry()`, etc. Extracted from QuestController.
- **QuestScopeManager** – StartScope/EndScope iteration limits
- **QuestSyncManager** – Synchronize node pattern matching (deferred batching)
- **QuestTimerManager** – Physical timers for TimerNode
- **QuestEventManager** – Global event listening
- **PresentationManager** – UI queue (messages, cutscenes)
- **QuestStatePersistenceManager** – Save/load instance state

### Adapters

- **QuestInventoryAdapterBase** – count_item, check_item, give_item, take_item
- **QuestKillAdapterBase** – count_kill
- Implementations: SimpleInventoryAdapter (group `inventory_controller`), SimpleKillAdapter (group `kill_controller` or QWGameState)

## Data Flow

```
.quest (FileAccess.store_var) → QuestGraphResource
     ↓
QuestController._load_graph_data() → _node_definitions, _node_connections, _id_to_context_node_map
     ↓
QuestInstance (runtime) ← variables, active_node_ids, objective_states
     ↓
Save: QuestInstance.get_save_data() → PersistenceManager → JSON
```

## Node Registration

- **NodeTypeRegistry** – Maps Resource script → Executor instance
- Each node type: Resource (data), Executor (runtime logic), Editor (UI)
- Definitions in `NodeTypeRegistry.DEFINITIONS`

## Debugger Integration

- **EditorDebuggerPlugin** – Captures `quest_weaver:*` messages from the game
- **quest_weaver:register** – Controller registration
- **quest_weaver:instance_update** – Instance state (file_id, quest_id, status, variables, active_node_ids)
- Viewer tab shows active instances in the Debugger panel when running the game

## Conventions

- **instance** can be `null` for QuestContextNodeResource (entry point); executors must handle null
- Use `StringName` for IDs and keys where appropriate
- State guards at API entry points (empty quest_id, invalid state)
- `call_deferred(&"method_name")` for deferred calls (Godot 4.6 Callable style)
