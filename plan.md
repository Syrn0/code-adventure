# Implementation Ledger — Coding Wizard (Phase 2: Connected World Stage Complete)

## System & Tech Stack

- Engine: Godot 4.7 (`config_version=5` in `project.godot`)
- Language: GDScript
- Renderer: GL Compatibility (`renderer/rendering_method="gl_compatibility"`)
- Physics: Jolt Physics (`3d/physics_engine="Jolt Physics"`)
- Platform: Windows (win32); desktop exports target Windows/Linux/macOS
- IDE: VS Code with Godot Tools extension (recommended)
- Project root: `C:\Users\lawre\localRepo\Personal Projects\code-adventure`
- Main scene: `res://Scenes/Levels/level_01.tscn`
- Autoloads (singletons): `CodeSandbox="*res://Scripts/Core/code_sandbox.gd"`, `ProgressionManager="*res://Scripts/Core/progression_manager.gd"`
- Git state: on `main`, uncommitted changes from Phase 1.5 + Phase 2 executions present

## Session History

### Phase 1.5 — Tier Completion & Crash Guards (EXECUTED & REVIEWED)

All 20 implementation steps completed and verified. Review confirmed strict contract compliance.

**Files created:**
- `Resources/api_tiers/journeyman_api.tres` — tier_name="Journeyman", tier_order=1, loops/match/functions enabled, 2000ms timeout, 500 statements, 20 recursion depth. Explicit full function list: all 16 Apprentice functions verbatim + `tween_property` + `get_node`.
- `Resources/api_tiers/master_api.tres` — tier_name="Master", tier_order=2, all language features on, 5000ms timeout, 1000 statements, 50 recursion depth. Explicit full function list: all Journeyman functions verbatim + `instantiate_scene` + `connect_signal` + `physics_raycast`.
- `Scripts/Core/journeyman_api.gd` — `extends ApprenticeAPI`, `class_name JourneymanAPI`. Adds `tween_property(target, property, to, duration)` with `is_instance_valid(target)` guard + duration clamped `[0,30]`; `get_node(path)` with `/root/` and `..` path-traversal rejection returning `get_node_or_null`.
- `Scripts/Core/master_api.gd` — `extends JourneymanAPI`, `class_name MasterAPI`. Adds `instantiate_scene(path, x, y)` with `ResourceLoader.exists` + `PackedScene` type check + clamped coords; `connect_signal(node, signal_name, method)` with `is_instance_valid(node)` + `node.has_signal(signal_name)` + `node.has_method(method)` guards; `physics_raycast(x1, y1, x2, y2)` with `Node2D`/`direct_space_state` validation returning collision point/normal/collider as Dictionary.

**Files modified:**
- `Scripts/Core/apprentice_api.gd` — Added `WORLD_MIN: float = -5000.0`, `WORLD_MAX: float = 5000.0` constants. Every method opens with `is_instance_valid(_world)`/`_player` checks, returns signature default on failure. `spawn_platform`: dims clamped `[8,512]`, coords clamped to world box, finite-arg checks. `teleport_player`: NaN/inf rejection, clamp, zero velocity after teleport. `change_gravity`: clamped `[-5000,5000]`. `spawn_particles`: count `[1,200]`, lifetime `[0.1,10]`. Child-loops (`remove_platform`/`color_platform`/`platform_exists_at`/`count_spawned_platforms`/`clear_all_platforms`): `is_instance_valid(child)` checks + `break` immediately after `queue_free`.
- `Scripts/Core/code_sandbox.gd` — `execute()` validates `world_context` and `context` dictionary nodes (`level`/`player`/`goal`) via `typeof == TYPE_OBJECT && is_instance_valid` before compiling; returns friendly `SandboxResult` error if invalid.
- `Scripts/Levels/level_base.gd` — `_on_run_requested()` guards `sandbox`/`progression` before calling `execute()`. `_process()` win-condition guards `player`/`goal_area` before `distance_to()`. `_spawn_win_effects()` guards `player` before spawning particles.

**Intentional contract deviation:**
- `connect_signal` parameter is named `signal_name` instead of `signal` because `signal` is a reserved GDScript keyword. Functionally identical; required for compilation.

**Test artifacts created (untracked):**
- `_freeze_test.gd`, `_freeze_test.gd.uid`, `_freeze_test.tscn`, `_sec_test.gd`, `_sec_test.gd.uid`, `_sec_test.tscn`

### Phase 2 Planning — Connected World Stage (PLANNED)

User decisions:
1. **Single connected world** (Hollow Knight / Metroidvania style) instead of discrete levels.
2. **No auto-advance / level select hub** — player stays in one world session.
3. **No `.tres` level data files** — geometry lives in `.tscn` scenes only.

Plan file updated at `C:\Users\lawre\.opencode\plan\CodingWizard_Plan.md` with:
- Phase 2 rewritten: single persistent `Node2D` world scene, puzzles as gated areas within the same world, progression tracked by `ProgressionManager` (unlocked tiers, completed puzzle zones) within single world save.
- Learning focus: conditionals (`if`/`elif`), boolean logic, position-based triggers (`get_player_position`, `is_player_near`) across connected puzzle zones.
- Technical Decisions updated: World Structure = Single connected stage; Level Data = `.tscn` scenes only.
- Risks updated: scope creep = "single connected world stage, Apprentice tier".

### Phase 2 — Connected World Stage (EXECUTED)

All 15 steps completed. An automated smoke test (26 checks, run headless with Godot 4.7.2, then deleted) verified: zone detection via Area2D triggers, per-zone API tier switching, locked-zone gating (interaction-only), tier unlocks, save persistence, and all 4 zone completions. Interactive playtest for camera feel/geometry tuning still pending.

**Files created:**
- `Scripts/World/puzzle_zone.gd` — `extends Node2D`, `class_name PuzzleZone`. Declarative zone data: `zone_id`, `zone_title`, `zone_description`, `required_tier`, `zone_bounds` (Rect2, local coords; zones sit at origin so local == world), `goal_path`, `min_spawned_platforms`, `required_function`, `hints` (Array). Runtime state: `is_completed`, `is_locked`. Builds its own `Area2D` trigger at runtime from `zone_bounds` (no per-zone shape boilerplate in the scene). Helpers: `get_trigger()`, `get_global_bounds()`, `contains_point()`.
- `Scripts/World/world_stage.gd` — `extends Node2D`, `class_name WorldStage` (does NOT extend LevelBase). Zone detection via trigger signals with `_zones_inside` tracking; per-zone API + editor wiring on every entry (never stale); run-based win (`min_spawned_platforms` inside zone bounds after successful spell) + goal-based win (player within 40px of zone goal, only while unlocked & incomplete); tier gating of puzzle interaction only, never traversal; zone completion → `ProgressionManager.complete_zone` → tier unlock check → HUD messages + particles; fall recovery (y > 1100 → teleport to zone entrance); HUD zone label + timed message label; `get_gravity`/`set_gravity` for player & `change_gravity()`.
- `Scenes/World/world_stage.tscn` — ~8.2k px-wide connected world, 4 zones left-to-right:
  - Zone 1 "The Awakening" (Apprentice, goal): level_01 gap-bridge puzzle ported verbatim (solution hint unchanged).
  - Zone 2 "Floating Isles" (Apprentice, goal): 900px void with one mid isle; teaches `var pos = get_player_position()` + `if`.
  - Zone 3 "The Pattern Forge" (Journeyman, `min_spawned_platforms = 5`): forge ledge over a 1000px pit; teaches `for i in range()`; completes in place.
  - Zone 4 "The Arcanum" (Master, `required_function = "physics_raycast"`, goal): chasm with two rune pillars to raycast, then bridge.
  - Plus: HUD (zone label, locked/completion message label, controls hint), ambient strata/glow rects, forge ember particles, invisible world-boundary walls.

**Files modified:**
- `Scripts/Core/progression_manager.gd` — Added `zone_completed` signal; `completed_zones` / `unlocked_zones` / `zone_states` vars; `register_zone`, `complete_zone(zone_id, tier)`, `is_zone_completed`, `get_completed_zones`, `unlock_zone`, `is_zone_unlocked`, `count_completed_zones_for_tier`, `count_zones_for_tier`. Tier rules replaced (step 7): Journeyman ← 2 Apprentice zones; Master ← ALL Journeyman-tier zones (user decision, see deviations). Save/load/reset extended; save `version` stays 1 and new keys default when missing, so Phase 1.5 saves load unchanged. `load_progress` now uses `.assign()` for all typed arrays — `get_var()`/fallback literals return untyped Arrays which cannot assign to `Array[String]` (caught by headless boot).
- `Scripts/Core/code_sandbox.gd` — `_build_wrapped_script` now normalizes each player line's leading whitespace to tabs via new `_indent_levels()` helper. Pre-existing bug exposed by Phase 2 content: wrapper prepends a tab, so space-indented `if`/`for` bodies (what beginners type and what hint strings contain) compiled as "Mixed use of tabs and spaces". Same signature; additive helper.
- `project.godot` — `run/main_scene` → `res://Scenes/World/world_stage.tscn` (step 12).

**Deleted (step 11):** `_freeze_test.gd`, `_freeze_test.gd.uid`, `_freeze_test.tscn`, `_sec_test.gd`, `_sec_test.gd.uid`, `_sec_test.tscn`.

**Kept (step 13):** `Scenes/Levels/level_01.tscn` retained as reference (non-destructive choice; safe to delete in a later phase).

**Intentional deviations (approved / documented):**
1. **Master gating** — plan contradicted itself (steps 3/7: "3 Journeyman zones" vs step 14: Zone 4 unlocks right after Zone 3). User chose: Master unlocks when ALL Journeyman-tier zones are complete; with the single Phase 2 zone that means completing The Pattern Forge, and the rule generalizes to a literal "3 Journeyman zones" once two more exist.
2. **Added `puzzle_zone.gd`** — "exported metadata" per zone requires a script; the blueprint listed only `world_stage.gd`. Zone nodes stay plain `Node2D` groups in the scene.
3. **Sandbox indentation normalization** — required for any `if`/`for` solution to compile; see files modified.
4. **Fall recovery** — not in the plan; falling into a pit teleports the player back to the current zone's entrance. Deliberately NOT a checkpoint system (still a single spawn at world start, per plan).
5. **Zone 3 win condition** — "forge 5 platforms" implemented as `min_spawned_platforms` counted inside zone bounds after a successful run, so the Journeyman trial completes in place (matches step 10's example win conditions).

## The Blueprint

File directory layout tree (current state + Phase 2 planned):

```
code-adventure/
├── .git/
├── .godot/
├── .vscode/
├── Assets/
│   ├── Audio/
│   ├── Fonts/
│   ├── Sprites/
│   ├── UI/
│   ├── icon.svg
│   └── icon.svg.import
├── Resources/
│   ├── api_tiers/
│   │   ├── apprentice_api.tres   [EXISTS]
│   │   ├── journeyman_api.tres   [CREATED — Phase 1.5]
│   │   └── master_api.tres       [CREATED — Phase 1.5]
│   └── levels/                   [EMPTY — no .tres level files by design]
├── Scenes/
│   ├── Entities/                 [EMPTY]
│   ├── Levels/
│   │   └── level_01.tscn         [EXISTS — current main scene]
│   ├── Objects/                  [EMPTY]
│   ├── Player/                   [EMPTY — wizard_player.tscn planned]
│   ├── UI/
│   │   ├── code_editor.tscn      [EXISTS]
│   │   ├── block_palette.tscn    [PLANNED]
│   │   └── hud.tscn              [PLANNED]
│   └── World/
│       └── world_stage.tscn     [CREATED — Phase 2 single connected stage]
├── Scripts/
│   ├── Camera/
│   │   └── game_camera.gd        [EXISTS]
│   ├── Core/
│   │   ├── code_sandbox.gd       [MODIFIED — Phase 1.5: context/world guards]
│   │   ├── wizard_api.gd         [EXISTS]
│   │   ├── progression_manager.gd[EXISTS]
│   │   ├── apprentice_api.gd     [MODIFIED — Phase 1.5: full crash guards]
│   │   ├── journeyman_api.gd     [CREATED — Phase 1.5]
│   │   └── master_api.gd         [CREATED — Phase 1.5]
│   ├── Levels/
│   │   └── level_base.gd         [MODIFIED — Phase 1.5: null/validity guards]
│   ├── Player/
│   │   └── wizard_controller.gd  [EXISTS]
│   ├── UI/
│   │   └── code_editor.gd        [EXISTS]
│   └── World/
│       ├── puzzle_zone.gd       [CREATED — Phase 2 zone data + runtime trigger]
│       └── world_stage.gd       [CREATED — Phase 2 connected world logic]
├── project.godot                 [MODIFIED — Phase 2: main scene = world_stage.tscn]
├── README.md                     [EXISTS]
├── SETUPINSTRUCTIONS.md          [EXISTS]
└── plan.md                       [THIS FILE]
```

## Strict Code Contracts

### Existing contracts (reference, must not break)

`code_sandbox.gd` — `extends Node` (no `class_name`, autoload singleton):
- `signal execution_started`
- `signal execution_completed(result: SandboxResult)`
- `signal execution_error(error: String)`
- `class SandboxResult:` with `var success: bool`, `var return_value: Variant`, `var error_message: String`, `var execution_time_ms: int`, `var print_output: Array`
- `func _init(p_success: bool, p_return_value: Variant = null, p_error: String = "", p_time: int = 0)`
- `const FORBIDDEN_PATTERNS := ["OS.", "FileAccess", "DirAccess", "ResourceLoader", "ResourceSaver", "Engine.", "ProjectSettings", "Input.", "DisplayServer", "load(", "preload(", "call(", "callv(", "call_deferred(", "set_script(", "instance_from_id(", "get_tree().quit", "get_tree().reload_current_scene", "yield", "signal ", "class_name"]`
- `const BUILTIN_FUNCTIONS := ["if", "elif", "else", "for", "while", "return", "and", "or", "not", "print", "str", "int", "float", "bool", "len", "range", "abs", "min", "max", "clamp", "lerp", "randf", "randi", "push_error", "push_warning", "vec2", "Color", "Vector2", "Vector2i", "Rect2", "Array", "Dictionary", "sin", "cos", "tan", "sqrt", "pow", "floor", "ceil", "round", "floori", "ceili", "roundi", "sign", "snapped"]`
- `var current_api: WizardAPI = null`
- `const DEBUG_SHOW_WRAPPED: bool = false`
- `var world_context: Node = null`
- `var _execution_count: int = 0`
- `var _total_execution_time: int = 0`
- `func _ready() -> void`
- `func set_api(api: WizardAPI) -> void`
- `func set_world_context(node: Node) -> void`
- `func execute(code: String, context: Dictionary = {}) -> SandboxResult`
- `func _describe_compile_error(code: int) -> String`
- `func _validate_code(code: String) -> String`
- `func _contains_keyword(code: String, keyword: String) -> bool`
- `func _validate_function_calls(code: String) -> String`
- `func _validate_arg_count(func_name: String, code: String, open_paren_index: int) -> String`
- `func _count_call_args(code: String, open_paren_index: int) -> int`
- `func _validate_identifiers(code: String) -> String`
- `func _enclosing_call_name(prefix: String) -> String`
- `func _collect_declared_identifiers(code: String) -> Dictionary`
- `func _mask_strings(code: String) -> String`
- `func _strip_comments(code: String) -> String`
- `func _build_wrapped_script(player_code: String) -> String`
- `func get_stats() -> Dictionary`
- `func reset_stats() -> void`

`wizard_api.gd` — `extends Resource`, `class_name WizardAPI`:
- `@export var tier_name: String = "Apprentice"`
- `@export var tier_order: int = 0`
- `@export var allowed_functions: Dictionary = {}` — keys: function name; value: Dictionary with `"args"` (Array[String] type names), `"param_names"` (Array[String]), `"returns"` (String), optional `"defaults"` (Dictionary index->value)
- `@export var allowed_node_methods: Dictionary = {}`
- `@export var allowed_node_properties: Dictionary = {}`
- `@export var allowed_classes: Array[String] = []`
- `@export var allowed_constants: Array[String] = []`
- `@export var allow_loops: bool = false`
- `@export var allow_conditionals: bool = true`
- `@export var allow_functions: bool = false`
- `@export var allow_lambdas: bool = false`
- `@export var allow_match: bool = false`
- `@export var max_execution_time_ms: int = 500`
- `@export var max_memory_bytes: int = 1048576`
- `@export var max_statements: int = 100`
- `@export var max_recursion_depth: int = 10`
- `@export_file("*.gd") var api_implementation_path: String = ""`
- `const TIER_APPRENTICE: String = "res://Resources/api_tiers/apprentice_api.tres"`
- `const TIER_JOURNEYMAN: String = "res://Resources/api_tiers/journeyman_api.tres"`
- `const TIER_MASTER: String = "res://Resources/api_tiers/master_api.tres"`
- `func _init() -> void`
- `func get_api_implementation() -> Script`
- `func is_function_allowed(func_name: String) -> bool`
- `func get_function_signature(func_name: String) -> Dictionary`
- `func is_node_method_allowed(node_class: String, method_name: String) -> bool`
- `func is_node_property_allowed(node_class: String, property_name: String) -> bool`
- `func is_class_allowed(p_class_name: String) -> bool`
- `func is_constant_allowed(const_name: String) -> bool`
- `func get_allowed_function_names() -> Array[String]`
- `func get_arg_default(signature: Dictionary, index: int) -> Variant`
- `func build_arg_declarations(func_name: String) -> Array[String]`
- `func get_default_return(type_name: String) -> String`
- `func format_signature(func_name: String) -> String`
- `func get_allowed_methods_for_class(node_class: String) -> Array[String]`
- `func validate() -> Array[String]`

`apprentice_api.gd` — `extends RefCounted`, `class_name ApprenticeAPI`:
- `const WORLD_MIN: float = -5000.0`
- `const WORLD_MAX: float = 5000.0`
- `var _world: Node = null`
- `var _player: Node = null`
- `func setup(world: Node, player: Node = null) -> void`
- `func set_world(world: Node) -> void`
- `func set_player(player: Node) -> void`
- `func spawn_platform(x: float, y: float, width: float = 64, height: float = 16) -> Node2D`
- `func remove_platform(x: float, y: float, tolerance: float = 32.0) -> bool`
- `func change_gravity(value: float) -> void`
- `func teleport_player(x: float, y: float) -> void`
- `func get_player_position() -> Vector2`
- `func color_platform(x: float, y: float, color: Color, tolerance: float = 32.0) -> bool`
- `func spawn_particles(x: float, y: float, count: int = 10, color: Color = Color.WHITE) -> void`
- `func wait(seconds: float) -> void` — print-only stub (async not supported)
- `func log_message(message: String) -> void`
- `func vec2(x: float, y: float) -> Vector2`
- `func random_range(min_val: float, max_val: float) -> float`
- `func random_int(min_val: int, max_val: int) -> int`
- `func is_player_near(x: float, y: float, radius: float = 64.0) -> bool`
- `func platform_exists_at(x: float, y: float, tolerance: float = 32.0) -> bool`
- `func count_spawned_platforms() -> int`
- `func clear_all_platforms() -> void`

`progression_manager.gd` — `extends Node` (no `class_name`, autoload singleton):
- `const SAVE_PATH := "user://progress.dat"`
- `const TIERS: Array[String] = ["Apprentice", "Journeyman", "Master"]`
- `var current_tier: String = "Apprentice"`
- `var completed_levels: Array[String] = []`
- `var unlocked_tiers: Array[String] = ["Apprentice"]`
- `var player_solutions: Dictionary = {}`
- `var current_level: String = ""`
- `signal tier_unlocked(tier_name: String)`
- `signal level_completed(level_id: String)`
- `signal progress_saved`
- `func is_tier_unlocked(tier_name: String) -> bool`
- `func get_tier_index(tier_name: String) -> int`
- `func unlock_tier(tier_name: String) -> bool`
- `func set_current_tier(tier_name: String) -> bool`
- `func complete_level(level_id: String) -> void`
- `func is_level_completed(level_id: String) -> bool`
- `func get_completed_levels() -> Array[String]`
- `func save_solution(level_id: String, code: String) -> void`
- `func get_solution(level_id: String) -> String`
- `func set_current_level(level_id: String) -> void`
- `func save_progress() -> void`
- `func load_progress() -> void`
- `func reset_progress() -> void`
- `func get_api_path_for_tier(tier_name: String) -> String`
- `func load_current_api() -> WizardAPI`
- `func get_tier_display_info(tier_name: String) -> Dictionary`

`level_base.gd` — `extends Node2D`, `class_name LevelBase`:
- `@export var level_id: String = "level_01"`
- `@export var level_title: String = "The Awakening"`
- `@export var level_description: String = "Learn to spawn platforms with code!"`
- `@export var required_api_tier: String = "Apprentice"`
- `@export_node_path("Camera2D") var camera_path: NodePath`
- `@export var camera_limits: Rect2 = Rect2(0, 0, 0, 0)`
- `@export var gravity: float = 980.0`
- `@export_node_path("Node2D") var goal_path: NodePath`
- `@export var required_function: String = ""`
- `@export var min_code_length: int = 0`
- `@export var first_hint: String`
- `@export var second_hint: String`
- `@export var solution_hint: String`
- `var player: CharacterBody2D = null`
- `var goal_area: Node2D = null`
- `var code_editor: CodeEditorUI = null`
- `var camera: GameCamera = null`
- `var progression: Node = null` — resolved via `/root/ProgressionManager`
- `var sandbox: Node = null` — resolved via `/root/CodeSandbox`
- `var level_completed: bool = false`
- `var spawned_platform_count: int = 0`
- `signal level_started`
- `signal code_executed(result: Dictionary)`
- `signal level_won`
- `func _ready() -> void`
- `func _find_camera() -> GameCamera`
- `func _find_code_editor() -> CodeEditorUI`
- `func get_gravity() -> float`
- `func set_gravity(value: float) -> void`
- `func _process(_delta: float) -> void`
- `func _unhandled_input(event: InputEvent) -> void`
- `func open_code_editor() -> void`
- `func _on_run_requested(code: String) -> void`
- `func execute_player_code() -> void`
- `func _win_level() -> void`
- `func _spawn_win_effects() -> void`
- `func _on_execution_completed(result) -> void`
- `func _count_spawned_platforms() -> int`
- `func _on_execution_error(error: String) -> void`
- `func get_progress_info() -> Dictionary`
- `func reload_level() -> void`

`wizard_controller.gd` — `extends CharacterBody2D`, `class_name WizardController`:
- `@export var speed: float = 300.0`
- `@export var jump_velocity: float = -420.0`
- `@export var acceleration: float = 2000.0`
- `@export var friction: float = 1800.0`
- `@export var gravity_multiplier: float = 1.0`
- `@export var visual_path: NodePath = "Visual"`
- `var is_controllable: bool = true`
- `var current_gravity: float = 980.0`
- `var visual: Node2D = null`
- `var _facing: float = 1.0`
- `func _ready() -> void`
- `func _physics_process(delta: float) -> void`
- `func _update_visual() -> void`
- `func teleport(new_position: Vector2) -> void`
- `func set_controllable(enabled: bool) -> void`
- `func set_gravity_multiplier(multiplier: float) -> void`
- `func get_state_string() -> String`
- `func _ensure_input_actions() -> void`
- `func _add_action(action: StringName, keys: Array) -> void`

`code_editor.gd` — `extends CanvasLayer`, `class_name CodeEditorUI`:
- `signal run_requested(code: String)`
- `signal opened`
- `signal closed`
- `@export var auto_close_on_success: bool = true`
- `var _is_open: bool = false`
- `var _hints: Array = []`
- `var _hint_index: int = 0`
- `var _api: WizardAPI = null`
- `var _initial_code: String = ""`
- `func _ready() -> void`
- `func open_editor() -> void`
- `func close_editor() -> void`
- `func toggle_editor() -> void`
- `func is_open() -> bool`
- `func set_code(code: String) -> void`
- `func get_code() -> String`
- `func set_level_info(title: String, description: String, hints: Array) -> void`
- `func set_api_reference(api: WizardAPI) -> void`
- `func show_result(success: bool, message: String, output: Array) -> void`
- `func _on_run_pressed() -> void`
- `func _on_reset_pressed() -> void`
- `func _on_hint_pressed() -> void`
- `func _set_output(bbcode: String) -> void`
- `func _input(event: InputEvent) -> void`
- `func _unhandled_input(event: InputEvent) -> void`
- `func _build_highlighter() -> void`

`game_camera.gd` — `extends Camera2D`, `class_name GameCamera`:
- `@export var follow_speed: float = 8.0`
- `@export var deadzone_radius: float = 0.0`
- `@export var lookahead_distance: float = 80.0`
- `@export var lookahead_speed: float = 5.0`
- `@export var default_zoom: Vector2 = Vector2(1.5, 1.5)`
- `@export var min_zoom: Vector2 = Vector2(0.5, 0.5)`
- `@export var max_zoom: Vector2 = Vector2(4.0, 4.0)`
- `@export var min_limit_size: Vector2 = Vector2(2400, 1300)`
- `@export var shake_decay: float = 5.0`
- `@export var shake_frequency: float = 30.0`
- `var target: Node2D = null`
- `func _ready() -> void`
- `func _process(delta: float) -> void`
- `func set_target(node: Node2D) -> void`
- `func set_limits(rect: Rect2) -> void`
- `func set_limits_from_node(node: Node2D) -> void`
- `func shake(intensity: float = 5.0) -> void`
- `func tween_zoom(target_zoom: Vector2, duration: float = 0.5) -> void`
- `func snap_to_target() -> void`
- `func reset() -> void`

### Tier resource contracts (as implemented)

`Resources/api_tiers/journeyman_api.tres` [CREATED]:
- `tier_name = "Journeyman"`, `tier_order = 1`
- `allow_loops = true`, `allow_match = true`, `allow_functions = true`
- `max_execution_time_ms = 2000`, `max_statements = 500`, `max_recursion_depth = 20`
- `api_implementation_path = "res://Scripts/Core/journeyman_api.gd"`
- `allowed_functions`: explicit full list — all 16 Apprentice functions verbatim + `tween_property` + `get_node`
- `allowed_node_methods = {}`, `allowed_node_properties = {}`
- `allowed_classes = ["Vector2", "Vector2i", "Color", "Array", "Dictionary", "Rect2", "String"]`
- `allowed_constants = ["PI", "TAU", "INF", "NAN"]`
- `allow_conditionals = true`, `allow_lambdas = false`

`Resources/api_tiers/master_api.tres` [CREATED]:
- `tier_name = "Master"`, `tier_order = 2`
- `allow_loops = true`, `allow_conditionals = true`, `allow_functions = true`, `allow_lambdas = true`, `allow_match = true`
- `max_execution_time_ms = 5000`, `max_statements = 1000`, `max_recursion_depth = 50`
- `api_implementation_path = "res://Scripts/Core/master_api.gd"`
- `allowed_functions`: explicit full list — all Journeyman functions verbatim + `instantiate_scene` + `connect_signal` + `physics_raycast`

### API implementation contracts (as implemented)

`Scripts/Core/journeyman_api.gd` [CREATED] — `extends ApprenticeAPI`, `class_name JourneymanAPI`:
- `func tween_property(target: Node2D, property: String, to: Variant, duration: float) -> void` — guards: `_world` valid, `target` valid, `property` non-empty, `duration` finite, duration clamped `[0, 30]`. Supports indexed paths like `"position:x"` by validating base property.
- `func get_node(path: String) -> Node` — rejects `/root/` prefix and `..` traversal; returns `get_node_or_null(path)`.

`Scripts/Core/master_api.gd` [CREATED] — `extends JourneymanAPI`, `class_name MasterAPI`:
- `func instantiate_scene(path: String, x: float, y: float) -> Node2D` — guards: `_world` valid, `path` non-empty, coords finite, `ResourceLoader.exists(path)`, resource is `PackedScene`; clamps coords to `[WORLD_MIN, WORLD_MAX]`.
- `func connect_signal(node: Node, signal_name: String, method: String) -> void` — guards: `_world` valid, `node` valid, `signal_name` non-empty, `method` non-empty, `node.has_signal(signal_name)`, `node.has_method(method)`. (Parameter named `signal_name` because `signal` is a reserved GDScript keyword.)
- `func physics_raycast(x1: float, y1: float, x2: float, y2: float) -> Dictionary` — guards: `_world` valid and is `Node2D` with `direct_space_state`, coords finite; returns `{hit: bool, position: Vector2, normal: Vector2, collider: Node}` or `{hit: false}` on miss.

### Guards contract (applied to all API impl methods)

Every method in `apprentice_api.gd`, `journeyman_api.gd`, `master_api.gd` must:
1. Open with `if not is_instance_valid(_world): push_error("…"); return <default>` (and same for `_player` where applicable).
2. On invalid input return the signature's default value: `null`, `false`, `0`, `0.0`, `Vector2.ZERO`, `""`, `{}` as appropriate.
3. Never throw unhandled errors or crash the engine; all failures surface via `push_error` / returned default.

## Sequential Implementation Steps

### Phase 1.5 — COMPLETED ✓

All 20 steps executed and reviewed. See Session History above.

### Phase 2: Connected World Stage — COMPLETED ✓ (see Session History)

All 15 steps executed and verified via headless smoke test (26/26 checks).

**Group A: World scene structure**
1. Create `Scripts/World/world_stage.gd` — extends `Node2D`, class_name `WorldStage`. Manages a single persistent world with multiple puzzle zones. Contains references to player, camera, code editor, sandbox, progression. Does NOT extend `LevelBase` (which is designed for single-puzzle levels); instead provides world-level orchestration: zone detection, zone state tracking, tier gating per zone.
2. Create `Scenes/World/world_stage.tscn` — single connected `Node2D` scene with: player spawn, camera, CodeEditorUI instance, connected terrain spanning multiple vertical/horizontal areas, multiple puzzle zones (each with trigger areas, goals, gated passages), ambient lighting/atmosphere.

**Group B: Puzzle zones within the world**
3. Design 3-4 puzzle zones in `world_stage.tscn`:
   - Zone 1 (Apprentice): "The Awakening" — current level_01 puzzle, ported into world. Player spawns platforms to cross a gap. Teaches function calls + coordinates.
   - Zone 2 (Apprentice): "Floating Isles" — conditional platforms. Player uses `if` + `get_player_position()` / `is_player_near()` to bridge staggered floating platforms. Teaches conditionals + boolean logic.
   - Zone 3 (Journeyman, gated): "The Pattern Forge" — loop-generated platform patterns. Player unlocks Journeyman tier after completing 2 Apprentice zones; uses `for` loops to create repeating structures. Teaches iteration.
   - Zone 4 (Master, gated): "The Arcanum" — full sandbox puzzle using `instantiate_scene` / `connect_signal` / `physics_raycast`. Master tier gated behind completing 3 Journeyman zones.
4. Each zone is a child `Node2D` group within `world_stage.tscn` with exported metadata: `zone_id: String`, `required_tier: String`, `is_completed: bool`.

**Group C: World progression & gating**
5. Add `ProgressionManager` tracking: `completed_zones: Array[String]`, `unlocked_zones: Array[String]`, `zone_states: Dictionary`. Extend save/load to persist zone state in the single world save.
6. WorldStage detects player zone via `Area2D` triggers; on entering a gated zone, check `ProgressionManager.is_tier_unlocked(required_tier)` before allowing puzzle interaction. Locked zones show a message like "Complete [prerequisite] to unlock this area."
7. On completing a puzzle zone, `ProgressionManager` marks zone complete, checks tier unlock rules (2 Apprentice → Journeyman, 3 Journeyman → Master), saves progress, and removes the zone's gate.

**Group D: Code editor integration**
8. `WorldStage` wires `CodeEditorUI.set_api_reference()` to the API tier required by the current zone. Player can only use functions in the current zone's tier.
9. `WorldStage` wires `CodeSandbox.set_world_context()` and `execute()` with the world node + zone-specific context dictionary.
10. On `execution_completed`, `WorldStage` evaluates zone-specific win conditions (e.g., "reach goal", "spawn 5 platforms", "use a for loop").

**Group E: Cleanup & verification**
11. Delete test artifacts: `_freeze_test.gd`, `_freeze_test.gd.uid`, `_freeze_test.tscn`, `_sec_test.gd`, `_sec_test.gd.uid`, `_sec_test.tscn`.
12. Update `project.godot` main scene from `res://Scenes/Levels/level_01.tscn` to `res://Scenes/World/world_stage.tscn`.
13. Keep `level_01.tscn` as reference or delete it once ported into world_zone_01.
14. Test full flow: player starts in world, enters Zone 1, writes code, completes puzzle, traverses to Zone 2, completes conditional puzzle, Journeyman tier unlocks, enters Zone 3, uses loops, completes puzzle, Zone 4 unlocks, uses Master functions, completes final puzzle.
15. Test tier gating: try entering Journeyman zone before completing 2 Apprentice zones → should show locked message.

## Edge Cases & Logic Traps

- Sandbox compiles a fresh `GDScript` on every `execute()` call (no compiled-script caching); repeated execution incurs compile overhead.
- Statement-count estimate in `_validate_code` counts non-empty non-comment lines, so multi-line `if`/`for` blocks count as multiple statements against `max_statements`.
- `wait()` is a print-only stub; async is not supported — `create_timer` is deferred until async is real.
- `_validate_function_calls` skips method calls (preceded by `.`) and built-ins; arbitrary node method calls are not whitelisted except via the API layer.
- `FORBIDDEN_PATTERNS` uses substring matching; kept narrow to avoid false positives on innocent words like "before"/"reward".
- Child iteration + `queue_free` mid-loop (`remove_platform`, `clear_all_platforms`): must `break` immediately after freeing and check `is_instance_valid` on subsequent iterations to avoid reading freed nodes.
- `level_base.gd` compile-time note: bare `ProgressionManager` / `CodeSandbox` identifiers are not resolvable at script parse time (autoloads register after the global-class scan); must resolve via `/root/ProgressionManager` and `/root/CodeSandbox` at runtime.
- `get_node` in Journeyman tier rejects path traversal (`/root/`, `..`) to prevent sandbox escape to the scene tree root.
- Master tier `connect_signal` / `physics_raycast` increase attack surface; approved for Master ("full power with limits") but still guarded.
- `connect_signal` parameter named `signal_name` not `signal` (reserved GDScript keyword).
- No LICENSE file exists despite README referencing one.
- README line 40 references `SETUP_GUIDE.md` which does not exist; only `SETUPINSTRUCTIONS.md` exists.
- `Resources/levels/` is empty — by design, no `.tres` level data files.
- `block_palette.tscn`, `hud.tscn`, `wizard_player.tscn` do not exist yet (Phase 2+).
- Godot editor may rename scene nodes after `class_name`; node lookup must not rely on hardcoded names (use `is` type checks + fallback logic).
- `WorldStage` must NOT extend `LevelBase` — `LevelBase` is designed for single-puzzle levels with a single `level_id` and `goal_path`. A connected world needs zone-based orchestration, not level-based. Design `WorldStage` as a fresh `Node2D` with its own zone management.
- `ProgressionManager.completed_levels` tracks level IDs; for world zones, either reuse this with `zone_id` values or add a separate `completed_zones` array. Reusing `completed_levels` keeps save format consistent.
- Zone transitions: when player moves between zones, `CodeEditorUI` must update its API reference to the new zone's tier. Avoid stale API references — always call `set_api_reference()` on zone entry.
- Zone gates: use `Area2D` with `body_entered` signal to detect player entering a zone; check tier unlock before enabling puzzle interaction. Do not block physical movement — gate puzzle interaction, not traversal (Metroidvania backtracking).
- `world_stage.tscn` will be large; use `TileMap` or `Polygon2D` for terrain, not individual `Sprite2D` nodes. Camera limits must span the full world bounds.
- Player spawn point: single spawn at world start. No respawn checkpoints in Phase 2 MVP (add in Phase 3 if needed).
- If world scene is too large for single `.tscn`, consider splitting into zone sub-scenes instanced by `world_stage.tscn`. Keep all zones in one `.tscn` for Phase 2 MVP.
- `FileAccess.get_var()` returns untyped Arrays (and missing keys fall back to untyped literals) — typed `Array[String]` restores in `load_progress` must use `.assign()`, never direct assignment.
- `_build_wrapped_script` normalizes player indentation to tabs (`_indent_levels`); GDScript rejects tab/space mixtures within a block, and beginners/hints indent with spaces.
- Goal-based zones are gated by GEOMETRY (gaps wider than max jump ~257px), not by requiring a successful run — the win check simply never fires unless the player physically crosses.
- Zone trigger bounds must generously cover build airspace (spawned platforms live above ground); Zone 3's counting bounds are y ∈ [-200, 800] so forged platforms at y=520 count.
- `bind()` on signals appends bound args AFTER signal args: `body_entered(body)` + `bind(zone)` → handler signature `(body, zone)`.
