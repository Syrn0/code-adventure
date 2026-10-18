extends Node2D
class_name LevelBase

## LevelBase - Base class for all levels
## Handles level logic, win conditions, and player code execution

@export_group("Level Configuration")
@export var level_id: String = "level_01"
@export var level_title: String = "The Awakening"
@export var level_description: String = "Learn to spawn platforms with code!"
@export var required_api_tier: String = "Apprentice"

@export_group("Camera")
## Node path to the camera (if empty, auto-finds a Camera2D child)
@export_node_path("Camera2D") var camera_path: NodePath
## Optional manual camera limits. Leave as Rect2(0,0,0,0) for free-following.
@export var camera_limits: Rect2 = Rect2(0, 0, 0, 0)

@export_group("Physics")
## World gravity (px/s^2). Positive = down. Can be changed via change_gravity().
@export var gravity: float = 980.0

@export_group("Win Condition")
## Node path to the goal/goal area
@export_node_path("Node2D") var goal_path: NodePath
## Optional: minimum code length or required function
@export var required_function: String = ""
@export var min_code_length: int = 0

@export_group("Hints")
@export var first_hint: String = "Use spawn_platform(x, y) to create platforms"
@export var second_hint: String = "Try spawning platforms at regular intervals to cross the gap"
@export var solution_hint: String = "for i in range(5): spawn_platform(200 + i * 100, 300)"

## References to child nodes (auto-assigned in _ready)
var player: CharacterBody2D = null
var goal_area: Node2D = null
var code_editor: CodeEditorUI = null
var camera: GameCamera = null

## Autoload references.
## NOTE: These scripts have `class_name`, so the engine compiles them during the
## editor's global-class scan — BEFORE autoload singletons are registered. That
## means the bare `ProgressionManager` / `CodeSandbox` identifiers are not
## resolvable at compile time (they would error with "Identifier not found").
## Resolving them through the scene tree at runtime avoids that entirely.
var progression: Node = null
var sandbox: Node = null

## Level state
var level_completed: bool = false
var spawned_platform_count: int = 0

signal level_started
signal code_executed(result: Dictionary)
signal level_won


func _ready() -> void:
	# Resolve autoloads at runtime (see note above)
	progression = get_node_or_null("/root/ProgressionManager")
	sandbox = get_node_or_null("/root/CodeSandbox")

	if progression == null or sandbox == null:
		push_error("LevelBase: required autoloads are missing (ProgressionManager / CodeSandbox)")
		return

	# Set this level as current
	progression.set_current_level(level_id)

	# Load the API for this tier
	var api: WizardAPI = progression.load_current_api()
	if api:
		sandbox.set_api(api)

	# Get references to child nodes
	player = get_node_or_null("Player")
	goal_area = get_node_or_null(goal_path) if goal_path != NodePath("") else null
	code_editor = _find_code_editor()

	# Find and set up camera (robust: by path, by name, then by type)
	camera = _find_camera()

	if camera and player:
		camera.set_target(player)

		# Apply manual camera limits only if the level defines them.
		# (Auto-calculated limits proved unreliable on flat levels, where the
		# geometry is smaller than the viewport and the camera appears stuck.)
		if camera_limits.size.x > 0.0 and camera_limits.size.y > 0.0:
			camera.set_limits(camera_limits)

	# Wire up the code editor (if the level has one)
	if code_editor:
		code_editor.run_requested.connect(_on_run_requested)
		code_editor.set_level_info(
			level_title,
			level_description,
			[first_hint, second_hint, solution_hint]
		)
		if api:
			code_editor.set_api_reference(api)

		# Restore the player's previous solution for this level
		var saved_code: String = progression.get_solution(level_id)
		if saved_code != "":
			code_editor.set_code(saved_code)

	# Connect sandbox signals
	sandbox.execution_completed.connect(_on_execution_completed)
	sandbox.execution_error.connect(_on_execution_error)

	# Set up world context for API
	if player:
		sandbox.set_world_context(self)

	level_started.emit()
	print("Level started: ", level_title)


## Locate the level camera robustly.
## The Godot editor may rename the node after the script's class_name
## (e.g. "GameCamera"), so we don't rely on the node being called "Camera".
func _find_camera() -> GameCamera:
	# 1. Explicit path set in the inspector
	if camera_path != NodePath(""):
		var cam := get_node_or_null(camera_path)
		if cam is GameCamera:
			return cam

	# 2. A child literally named "Camera"
	var named := get_node_or_null("Camera")
	if named is GameCamera:
		return named

	# 3. First child of type GameCamera (or any Camera2D)
	var fallback: Camera2D = null
	for child in get_children():
		if child is GameCamera:
			return child
		if child is Camera2D and fallback == null:
			fallback = child

	return fallback as GameCamera


## Locate the code editor node (a CodeEditorUI anywhere among our children)
func _find_code_editor() -> CodeEditorUI:
	var named := get_node_or_null("CodeEditor")
	if named is CodeEditorUI:
		return named
	for child in get_children():
		if child is CodeEditorUI:
			return child
	return null


## World gravity accessors (used by WizardController and change_gravity())
func get_gravity() -> float:
	return gravity


func set_gravity(value: float) -> void:
	gravity = value
	if is_instance_valid(player):
		var g = player.get("current_gravity")
		if g != null:
			player.set("current_gravity", value)


func _process(_delta: float) -> void:
	# Check win condition (player reached goal)
	if level_completed:
		return
	if not is_instance_valid(player) or not is_instance_valid(goal_area):
		return
	if player.global_position.distance_to(goal_area.global_position) < 32.0:
		_win_level()


func _unhandled_input(event: InputEvent) -> void:
	# Debug: T key to test camera shake
	if event is InputEventKey and event.pressed and event.keycode == KEY_T:
		if camera:
			camera.shake(8.0)
			print("Camera shake triggered (debug)")


## Open the code editor (called by HUD/input or externally)
func open_code_editor() -> void:
	if code_editor:
		code_editor.open_editor()


## Called when the player casts their spell from the editor
func _on_run_requested(code: String) -> void:
	# Guard against missing/freed core systems before doing anything else
	if not is_instance_valid(sandbox):
		push_error("LevelBase: sandbox is unavailable")
		if code_editor:
			code_editor.show_result(false, "The spellbook is unavailable right now - please restart the level.", [])
		return
	if not is_instance_valid(progression):
		push_error("LevelBase: progression manager is unavailable")
		if code_editor:
			code_editor.show_result(false, "The spellbook is unavailable right now - please restart the level.", [])
		return

	# Validate min length
	if code.length() < min_code_length:
		if code_editor:
			code_editor.show_result(false, "Your spell is too short.", [])
		return

	# Validate required function
	if required_function != "" and required_function not in code:
		if code_editor:
			code_editor.show_result(false, "Missing required spell: %s" % required_function, [])
		return

	# Execute in the sandbox (synchronous)
	var result = sandbox.execute(code, {
		"level": self,
		"player": player,
		"goal": goal_area,
	})

	if result == null:
		if code_editor:
			code_editor.show_result(false, "The spell fizzled unexpectedly.", [])
		return

	# Only persist code that actually worked, so a broken draft isn't restored
	# and re-run the next time the level loads.
	if result.success:
		progression.save_solution(level_id, code)

	var output: Array = []
	if result.print_output:
		output = result.print_output

	if code_editor:
		code_editor.show_result(result.success, result.error_message, output)

	code_executed.emit({
		"success": result.success,
		"error": result.error_message,
		"return_value": result.return_value,
		"execution_time": result.execution_time_ms,
		"print_output": output,
	})


## Legacy entry point: run whatever code is currently in the editor
func execute_player_code() -> void:
	if code_editor == null:
		push_error("No code editor found")
		return
	_on_run_requested(code_editor.get_code())


## Win the level
func _win_level() -> void:
	if level_completed:
		return

	level_completed = true
	if is_instance_valid(progression):
		progression.complete_level(level_id)
	else:
		push_warning("LevelBase: progression manager unavailable - completion not recorded")

	# Camera shake for feedback
	if camera:
		camera.shake(8.0)

	# Trigger win effects (particles, sounds, etc.)
	_spawn_win_effects()

	level_won.emit()
	print("Level completed: ", level_title)


func _spawn_win_effects() -> void:
	if is_instance_valid(player):
		# Spawn celebration particles at player position
		var particles := CPUParticles2D.new()
		particles.position = player.global_position
		particles.amount = 50
		particles.one_shot = true
		particles.emitting = true
		particles.color = Color.GOLD
		particles.lifetime = 2.0
		add_child(particles)

		# Auto-free after particles finish
		var timer := get_tree().create_timer(2.5)
		timer.timeout.connect(particles.queue_free)


## Sandbox callbacks
func _on_execution_completed(result) -> void:
	if result.success:
		print("Code executed successfully in ", result.execution_time_ms, "ms")
		# Count platforms by scanning the scene tree for spawned platforms
		spawned_platform_count = _count_spawned_platforms()
	else:
		print("Code execution failed: ", result.error_message)


func _count_spawned_platforms() -> int:
	var count := 0
	for child in get_children():
		if child is StaticBody2D and child.has_meta("spawned_by_code"):
			count += 1
	return count


func _on_execution_error(error: String) -> void:
	print("Sandbox error: ", error)


## Get level progress info (for UI)
func get_progress_info() -> Dictionary:
	return {
		"level_id": level_id,
		"title": level_title,
		"completed": level_completed,
		"platforms_spawned": spawned_platform_count,
		"api_tier": required_api_tier,
	}


## Reload the level (reset state)
func reload_level() -> void:
	get_tree().reload_current_scene()
