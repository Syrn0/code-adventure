extends Node2D
class_name WorldStage

## WorldStage - Orchestration for the single connected world (Phase 2).
##
## Deliberately does NOT extend LevelBase: that class models one puzzle per
## level with a single goal and a single API tier. The connected world is
## zone-based - each PuzzleZone child carries its own tier, hints and win
## condition - so this node provides world-level orchestration instead:
## zone detection, zone state tracking, tier gating per zone, editor wiring
## and zone completion.
##
## Autoloads (ProgressionManager / CodeSandbox) are resolved at runtime via
## /root - see the note in level_base.gd for why bare identifiers fail to
## compile (autoloads register after the global-class scan).

signal zone_entered(zone: PuzzleZone)
signal zone_left(zone: PuzzleZone)
signal zone_finished(zone: PuzzleZone)
signal code_executed(result: Dictionary)

@export_group("World")
@export var gravity: float = 980.0
## Camera limits spanning the full world bounds.
@export var camera_limits: Rect2 = Rect2(-400, -400, 9200, 1600)
## Where the player starts (and where they return if they fall off the world).
@export var player_spawn: Vector2 = Vector2(150, 500)
## Falling below this Y is recovered by teleporting back to the zone entrance.
## (Not a checkpoint system - there is still only one real spawn point.)
@export var fall_limit_y: float = 1100.0

## References (resolved in _ready)
var player: CharacterBody2D = null
var camera: GameCamera = null
var code_editor: CodeEditorUI = null
var progression: Node = null
var sandbox: Node = null

## Zones (PuzzleZone children, sorted left-to-right)
var zones: Array[PuzzleZone] = []
var current_zone: PuzzleZone = null
var _zones_inside: Array[PuzzleZone] = []

## HUD (resolved in _ready)
var _zone_label: Label = null
var _message_label: Label = null


func _ready() -> void:
	# Resolve autoloads at runtime (see note above)
	progression = get_node_or_null("/root/ProgressionManager")
	sandbox = get_node_or_null("/root/CodeSandbox")
	if progression == null or sandbox == null:
		push_error("WorldStage: required autoloads are missing (ProgressionManager / CodeSandbox)")
		return

	player = _find_player()
	camera = _find_camera()
	code_editor = _find_code_editor()
	_zone_label = get_node_or_null("HUD/ZoneLabel")
	_message_label = get_node_or_null("HUD/MessageLabel")

	_collect_zones()

	# Register every zone with ProgressionManager and restore completed state
	# BEFORE wiring triggers, so the first zone entry sees consistent data.
	for zone in zones:
		progression.register_zone(zone.zone_id, zone.required_tier)
		zone.is_completed = progression.is_zone_completed(zone.zone_id)
	_sync_zone_locks()
	_connect_zone_triggers()

	if camera and player:
		camera.set_target(player)
		camera.set_limits(camera_limits)

	if code_editor:
		code_editor.run_requested.connect(_on_run_requested)

	if sandbox:
		sandbox.set_world_context(self)
		sandbox.execution_completed.connect(_on_execution_completed)
		sandbox.execution_error.connect(_on_execution_error)

	if progression:
		progression.tier_unlocked.connect(_on_tier_unlocked)

	_update_hud()
	print("World stage started: %d zones" % zones.size())


func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		return

	# Recover from falls (no checkpoints in Phase 2 - always zone entrance)
	if player.global_position.y > fall_limit_y:
		_respawn_player()

	# Goal-based zone win (zones completed by traversal, not by the run itself)
	if current_zone == null or current_zone.is_completed or current_zone.is_locked:
		return
	var goal := current_zone.goal
	if is_instance_valid(goal) and player.global_position.distance_to(goal.global_position) < 40.0:
		_complete_zone(current_zone, "You reached the goal!")


# ---------------------------------------------------------------------------
# Zone detection & state
# ---------------------------------------------------------------------------

func _collect_zones() -> void:
	zones.clear()
	for child in get_children():
		if child is PuzzleZone:
			zones.append(child)
	# Stable left-to-right ordering (first zone = spawn zone)
	zones.sort_custom(func(a: PuzzleZone, b: PuzzleZone) -> bool:
		return a.zone_bounds.position.x < b.zone_bounds.position.x)


func _connect_zone_triggers() -> void:
	for zone in zones:
		var trigger := zone.get_trigger()
		if trigger == null:
			continue
		# Signal args come first, bound args last: body_entered(body) + zone
		trigger.body_entered.connect(_on_zone_body_entered.bind(zone))
		trigger.body_exited.connect(_on_zone_body_exited.bind(zone))


func _on_zone_body_entered(body: Node2D, zone: PuzzleZone) -> void:
	if body != player:
		return
	if zone not in _zones_inside:
		_zones_inside.append(zone)
	_refresh_current_zone()


func _on_zone_body_exited(body: Node2D, zone: PuzzleZone) -> void:
	if body != player:
		return
	_zones_inside.erase(zone)
	_refresh_current_zone()


func _refresh_current_zone() -> void:
	var next: PuzzleZone = null
	if not _zones_inside.is_empty():
		next = _zones_inside[_zones_inside.size() - 1]
	if next == current_zone:
		return

	var previous := current_zone
	current_zone = next
	if previous != null:
		zone_left.emit(previous)
	if current_zone != null:
		_activate_zone(current_zone)
		zone_entered.emit(current_zone)


## Activate a zone: refresh the sandbox/editor for the zone's tier and report
## whether the area is sealed. Always called on entry - never leave a stale
## API reference behind when moving between zones.
func _activate_zone(zone: PuzzleZone) -> void:
	if not is_instance_valid(progression) or not is_instance_valid(sandbox):
		return

	var locked: bool = not progression.is_tier_unlocked(zone.required_tier)
	zone.is_locked = locked

	# Player may only use the functions of the CURRENT ZONE's tier
	var api: WizardAPI = null
	var api_path: String = progression.get_api_path_for_tier(zone.required_tier)
	if ResourceLoader.exists(api_path):
		api = load(api_path)
	sandbox.set_api(api)
	sandbox.set_world_context(self)

	if code_editor:
		code_editor.set_api_reference(api)
		code_editor.set_level_info(zone.zone_title, zone.zone_description, zone.hints)
		# Restore the player's previous solution for this zone
		code_editor.set_code(progression.get_solution(zone.zone_id))

	_update_hud()
	if locked:
		_show_zone_message("This area is sealed. " + _locked_message(zone), 6.0)


# ---------------------------------------------------------------------------
# Zone gating (plan step 6: gate puzzle INTERACTION, never traversal)
# ---------------------------------------------------------------------------

func _sync_zone_locks() -> void:
	if not is_instance_valid(progression):
		return
	for zone in zones:
		var unlocked: bool = progression.is_tier_unlocked(zone.required_tier)
		zone.is_locked = not unlocked
		if unlocked:
			progression.unlock_zone(zone.zone_id)


func _locked_message(zone: PuzzleZone) -> String:
	return "Complete %s to unlock this area." % _tier_prerequisite_text(zone.required_tier)


func _tier_prerequisite_text(tier_name: String) -> String:
	match tier_name:
		"Journeyman":
			return "the Apprentice trials - 2 zones (The Awakening and Floating Isles)"
		"Master":
			return "the Journeyman trial (The Pattern Forge)"
		_:
			return "more puzzles"


func _on_tier_unlocked(tier_name: String) -> void:
	_sync_zone_locks()

	var icon := ""
	if is_instance_valid(progression):
		var info: Dictionary = progression.get_tier_display_info(tier_name)
		icon = str(info.get("icon", ""))

	_show_zone_message("%s %s tier unlocked! New areas are open." % [icon, tier_name], 8.0)
	_update_hud()

	if is_instance_valid(player):
		_spawn_sparkles(player.global_position, 40)


# ---------------------------------------------------------------------------
# Code execution (plan steps 8-10)
# ---------------------------------------------------------------------------

func _on_run_requested(code: String) -> void:
	# Guard against missing/freed core systems before doing anything else
	if not is_instance_valid(sandbox) or not is_instance_valid(progression):
		push_error("WorldStage: sandbox or progression manager is unavailable")
		if code_editor:
			code_editor.show_result(false, "The spellbook is unavailable right now - please restart the game.", [])
		return

	var zone := current_zone
	if zone == null:
		code_editor.show_result(false, "Stand inside a puzzle area before casting spells.", [])
		return
	if zone.is_locked:
		code_editor.show_result(false, _locked_message(zone), [])
		return
	if zone.required_function != "" and zone.required_function not in code:
		code_editor.show_result(false, "This trial demands the %s() spell." % zone.required_function, [])
		return

	# Execute in the sandbox (synchronous); world context = this node
	var result = sandbox.execute(code, {
		"level": self,
		"player": player,
		"goal": zone.goal,
	})
	if result == null:
		code_editor.show_result(false, "The spell fizzled unexpectedly.", [])
		return

	# Only persist code that actually worked, so a broken draft isn't restored
	if result.success:
		progression.save_solution(zone.zone_id, code)

	var output: Array = []
	if result.print_output:
		output = result.print_output

	# Zone-specific win conditions. Goal-based zones resolve during traversal
	# (see _process); run-based zones (e.g. "forge 5 platforms") resolve here.
	var completed_now := false
	if result.success:
		completed_now = _evaluate_zone_win(zone)

	if not completed_now:
		code_editor.show_result(result.success, result.error_message, output)

	code_executed.emit({
		"success": result.success,
		"error": result.error_message,
		"return_value": result.return_value,
		"execution_time": result.execution_time_ms,
		"print_output": output,
	})


## Evaluate zone win conditions that depend on a successful spell run.
## Returns true if this run completed the zone.
func _evaluate_zone_win(zone: PuzzleZone) -> bool:
	if zone == null or zone.is_completed:
		return false
	if zone.min_spawned_platforms > 0:
		var built := _count_platforms_in_zone(zone)
		if built >= zone.min_spawned_platforms:
			_complete_zone(zone, "You forged %d platforms (the trial demanded %d)." % [
				built, zone.min_spawned_platforms
			])
			return true
	return false


func _count_platforms_in_zone(zone: PuzzleZone) -> int:
	var count := 0
	var bounds := zone.get_global_bounds()
	for child in get_children():
		if not is_instance_valid(child):
			continue
		if child is StaticBody2D and child.has_meta("spawned_by_code"):
			if bounds.has_point(child.global_position):
				count += 1
	return count


# ---------------------------------------------------------------------------
# Zone completion (plan step 7)
# ---------------------------------------------------------------------------

func _complete_zone(zone: PuzzleZone, detail: String) -> void:
	if zone == null or zone.is_completed:
		return
	zone.is_completed = true

	if is_instance_valid(progression):
		progression.complete_zone(zone.zone_id, zone.required_tier)
	else:
		push_warning("WorldStage: progression manager unavailable - completion not recorded")

	# Tier unlocks may have opened other zones just now
	_sync_zone_locks()

	if camera:
		camera.shake(8.0)
	_spawn_zone_effects(zone)

	if code_editor:
		code_editor.show_result(true, "%s complete! %s" % [zone.zone_title, detail], [])

	_show_zone_message("★ %s complete! %s" % [zone.zone_title, detail], 6.0)
	_update_hud()
	zone_finished.emit(zone)
	print("Zone completed: ", zone.zone_id)


# ---------------------------------------------------------------------------
# Effects & HUD
# ---------------------------------------------------------------------------

func _spawn_zone_effects(zone: PuzzleZone) -> void:
	var center := zone.get_global_bounds().get_center()
	if is_instance_valid(zone.goal):
		center = zone.goal.global_position
	_spawn_sparkles(center, 60)


func _spawn_sparkles(at: Vector2, amount: int) -> void:
	var particles := CPUParticles2D.new()
	particles.amount = clampi(amount, 1, 200)
	particles.one_shot = true
	particles.emitting = true
	particles.color = Color.GOLD
	particles.lifetime = 2.0
	add_child(particles)
	particles.global_position = at

	var timer := get_tree().create_timer(2.5)
	timer.timeout.connect(particles.queue_free)


func _update_hud() -> void:
	if not is_instance_valid(_zone_label):
		return
	if current_zone == null:
		_zone_label.text = "The Wizard's Path"
		return

	var text := current_zone.zone_title
	if current_zone.is_completed:
		text += "   [COMPLETE]"
	elif current_zone.is_locked:
		text += "   [SEALED - requires %s tier]" % current_zone.required_tier
	else:
		text += "   (%s tier)" % current_zone.required_tier
	_zone_label.text = text


func _show_zone_message(text: String, duration: float = 5.0) -> void:
	if not is_instance_valid(_message_label):
		return
	_message_label.text = text
	_message_label.visible = true
	var timer := get_tree().create_timer(duration)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(_message_label) and _message_label.text == text:
			_message_label.visible = false)


# ---------------------------------------------------------------------------
# Player recovery & world gravity
# ---------------------------------------------------------------------------

func _respawn_player() -> void:
	var safe := player_spawn
	if current_zone != null:
		var bounds := current_zone.get_global_bounds()
		safe = Vector2(bounds.position.x + 120.0, 500.0)

	if player is WizardController:
		(player as WizardController).teleport(safe)
	else:
		player.global_position = safe

	if camera:
		camera.snap_to_target()


func get_gravity() -> float:
	return gravity


func set_gravity(value: float) -> void:
	gravity = value
	if is_instance_valid(player):
		var g = player.get("current_gravity")
		if g != null:
			player.set("current_gravity", value)


# ---------------------------------------------------------------------------
# Sandbox callbacks (logging only - results are handled in _on_run_requested)
# ---------------------------------------------------------------------------

func _on_execution_completed(result) -> void:
	if result.success:
		print("WorldStage: spell cast successfully in ", result.execution_time_ms, "ms")
	else:
		print("WorldStage: spell failed: ", result.error_message)


func _on_execution_error(error: String) -> void:
	print("WorldStage sandbox error: ", error)


# ---------------------------------------------------------------------------
# Node finders (robust: never rely on hardcoded names after class_name renames)
# ---------------------------------------------------------------------------

func _find_player() -> CharacterBody2D:
	var named := get_node_or_null("Player")
	if named is WizardController:
		return named
	for child in get_children():
		if child is WizardController:
			return child
		if child is CharacterBody2D:
			return child
	return null


func _find_camera() -> GameCamera:
	var named := get_node_or_null("Camera")
	if named is GameCamera:
		return named
	var fallback: Camera2D = null
	for child in get_children():
		if child is GameCamera:
			return child
		if child is Camera2D and fallback == null:
			fallback = child
	return fallback as GameCamera


func _find_code_editor() -> CodeEditorUI:
	var named := get_node_or_null("CodeEditor")
	if named is CodeEditorUI:
		return named
	for child in get_children():
		if child is CodeEditorUI:
			return child
	return null
