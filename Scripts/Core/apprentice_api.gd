extends RefCounted
class_name ApprenticeAPI

## ApprenticeAPI - Implementation of allowed functions for Apprentice tier
## These are static functions that the sandbox can call
##
## Crash-guard contract: every method opens with is_instance_valid() checks on
## _world / _player and returns the signature's default value on failure, so a
## spell can never crash the engine with a stale or missing reference.

## World bounds for clamping player-supplied coordinates (crash guard)
const WORLD_MIN: float = -5000.0
const WORLD_MAX: float = 5000.0

# References to game systems (injected at runtime)
var _world: Node = null
var _player: Node = null


## Initialize with world references
func setup(world: Node, player: Node = null) -> void:
	_world = world
	_player = player


## Set the world reference
func set_world(world: Node) -> void:
	_world = world


## Set the player reference
func set_player(player: Node) -> void:
	_player = player


# ==================== WORLD MANIPULATION ====================

## Spawn a platform at the given position
func spawn_platform(x: float, y: float, width: float = 64, height: float = 16) -> Node2D:
	if not is_instance_valid(_world):
		push_error("ApprenticeAPI.spawn_platform: no valid world reference")
		return null
	if not is_finite(x) or not is_finite(y) or not is_finite(width) or not is_finite(height):
		push_error("ApprenticeAPI.spawn_platform: arguments must be finite numbers")
		return null

	# Clamp inputs so a spell cannot build degenerate or universe-sized platforms
	var safe_x := clampf(x, WORLD_MIN, WORLD_MAX)
	var safe_y := clampf(y, WORLD_MIN, WORLD_MAX)
	var safe_width := clampf(width, 8.0, 512.0)
	var safe_height := clampf(height, 8.0, 512.0)

	# Create a new platform
	var platform := StaticBody2D.new()
	platform.position = Vector2(safe_x, safe_y)

	# Add collision shape
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(safe_width, safe_height)
	collision.shape = shape
	platform.add_child(collision)

	# Add visual (placeholder)
	var visual := ColorRect.new()
	visual.size = Vector2(safe_width, safe_height)
	visual.position = Vector2(-safe_width / 2, -safe_height / 2)
	visual.color = Color(0.6, 0.4, 0.2)  # Brown placeholder
	platform.add_child(visual)

	# Add to world
	_world.add_child(platform)

	# Add metadata for identification
	platform.set_meta("spawned_by_code", true)
	platform.set_meta("spawn_time", Time.get_ticks_msec())

	return platform


## Remove a spawned platform by position (approximate)
func remove_platform(x: float, y: float, tolerance: float = 32.0) -> bool:
	if not is_instance_valid(_world):
		push_error("ApprenticeAPI.remove_platform: no valid world reference")
		return false

	var target_pos := Vector2(x, y)
	var removed := false

	for child in _world.get_children():
		if not is_instance_valid(child):
			continue
		if child is StaticBody2D and child.has_meta("spawned_by_code"):
			if child.position.distance_to(target_pos) <= tolerance:
				child.queue_free()
				removed = true
				break  # Node is queued; stop touching the child list immediately.

	return removed


## Change the world's gravity (affects player)
func change_gravity(value: float) -> void:
	if not is_instance_valid(_world):
		push_error("ApprenticeAPI.change_gravity: no valid world reference")
		return
	if not is_finite(value):
		push_error("ApprenticeAPI.change_gravity: value must be a finite number")
		return

	var safe_value := clampf(value, -5000.0, 5000.0)

	# Find physics server or gravity area
	# This is a simplified version - actual implementation depends on your setup
	if _world.has_method("set_gravity"):
		_world.set_gravity(safe_value)
	else:
		# Try to find a gravity node
		var gravity_area = _world.get_node_or_null("GravityArea")
		if is_instance_valid(gravity_area):
			gravity_area.gravity = safe_value


## Teleport the player to a position
func teleport_player(x: float, y: float) -> void:
	if not is_instance_valid(_player):
		push_error("ApprenticeAPI.teleport_player: no valid player reference")
		return
	if not is_finite(x) or not is_finite(y):
		push_error("ApprenticeAPI.teleport_player: x/y must be finite numbers")
		return

	var safe_pos := Vector2(
		clampf(x, WORLD_MIN, WORLD_MAX),
		clampf(y, WORLD_MIN, WORLD_MAX)
	)

	if _player is CharacterBody2D:
		_player.global_position = safe_pos
		_player.velocity = Vector2.ZERO

	# Snap camera to new position so it doesn't lag behind
	var level = _player.get_parent()
	if is_instance_valid(level):
		for child in level.get_children():
			if not is_instance_valid(child):
				continue
			if child.has_method("snap_to_target"):
				child.snap_to_target()
				break


## Get player position
func get_player_position() -> Vector2:
	if not is_instance_valid(_player):
		push_error("ApprenticeAPI.get_player_position: no valid player reference")
		return Vector2.ZERO
	return _player.global_position


# ==================== VISUAL EFFECTS ====================

## Change the color of a spawned platform (by position)
func color_platform(x: float, y: float, color: Color, tolerance: float = 32.0) -> bool:
	if not is_instance_valid(_world):
		push_error("ApprenticeAPI.color_platform: no valid world reference")
		return false

	var target_pos := Vector2(x, y)

	for child in _world.get_children():
		if not is_instance_valid(child):
			continue
		if child is StaticBody2D and child.has_meta("spawned_by_code"):
			if child.position.distance_to(target_pos) <= tolerance:
				# Find ColorRect child
				for visual in child.get_children():
					if not is_instance_valid(visual):
						continue
					if visual is ColorRect:
						visual.color = color
						return true
	return false


## Spawn a particle effect at position
func spawn_particles(x: float, y: float, count: int = 10, color: Color = Color.WHITE) -> void:
	if not is_instance_valid(_world):
		push_error("ApprenticeAPI.spawn_particles: no valid world reference")
		return
	if not is_finite(x) or not is_finite(y):
		push_error("ApprenticeAPI.spawn_particles: x/y must be finite numbers")
		return

	var safe_count := clampi(count, 1, 200)
	# Fixed 1.0s baseline, kept inside the safe [0.1, 10] bounds.
	var safe_lifetime := clampf(1.0, 0.1, 10.0)

	var particles := CPUParticles2D.new()
	particles.position = Vector2(
		clampf(x, WORLD_MIN, WORLD_MAX),
		clampf(y, WORLD_MIN, WORLD_MAX)
	)
	particles.amount = safe_count
	particles.emitting = true
	particles.one_shot = true
	particles.color = color
	particles.lifetime = safe_lifetime

	_world.add_child(particles)

	# Auto-free after particles finish
	particles.finished.connect(particles.queue_free)


# ==================== UTILITY FUNCTIONS ====================

## Wait for a duration (in seconds) - blocks execution
func wait(seconds: float) -> void:
	# In sandbox, this would be problematic
	# For now, just print (real implementation would need async support)
	print("wait(", seconds, ") called - async not yet supported")


## Log a message to the console
func log_message(message: String) -> void:
	print("[Player Code]: ", message)


## Create a Vector2 (convenience function)
func vec2(x: float, y: float) -> Vector2:
	return Vector2(x, y)


## Get a random float between min and max
func random_range(min_val: float, max_val: float) -> float:
	return randf_range(min_val, max_val)


## Get a random integer between min and max (inclusive)
func random_int(min_val: int, max_val: int) -> int:
	return randi_range(min_val, max_val)


# ==================== PUZZLE-SPECIFIC ====================

## Check if player is near a position
func is_player_near(x: float, y: float, radius: float = 64.0) -> bool:
	if not is_instance_valid(_player):
		push_error("ApprenticeAPI.is_player_near: no valid player reference")
		return false

	var player_pos: Vector2 = _player.global_position
	return player_pos.distance_to(Vector2(x, y)) <= radius


## Check if a platform exists at position
func platform_exists_at(x: float, y: float, tolerance: float = 32.0) -> bool:
	if not is_instance_valid(_world):
		push_error("ApprenticeAPI.platform_exists_at: no valid world reference")
		return false

	var target_pos := Vector2(x, y)

	for child in _world.get_children():
		if not is_instance_valid(child):
			continue
		if child is StaticBody2D and child.has_meta("spawned_by_code"):
			if child.position.distance_to(target_pos) <= tolerance:
				return true
	return false


## Count spawned platforms
func count_spawned_platforms() -> int:
	if not is_instance_valid(_world):
		push_error("ApprenticeAPI.count_spawned_platforms: no valid world reference")
		return 0

	var count := 0
	for child in _world.get_children():
		if not is_instance_valid(child):
			continue
		if child is StaticBody2D and child.has_meta("spawned_by_code"):
			count += 1
	return count


## Clear all spawned platforms
func clear_all_platforms() -> void:
	if not is_instance_valid(_world):
		push_error("ApprenticeAPI.clear_all_platforms: no valid world reference")
		return

	for child in _world.get_children():
		if not is_instance_valid(child):
			continue
		if child is StaticBody2D and child.has_meta("spawned_by_code"):
			child.queue_free()
