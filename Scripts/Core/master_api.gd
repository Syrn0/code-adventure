extends JourneymanAPI
class_name MasterAPI

## MasterAPI - Extends JourneymanAPI with scene instantiation, signal wiring,
## and physics raycasts. Unlockable via the Master tier (master_api.tres).
## "Full power with limits" - every method is still guarded.
## (World bounds WORLD_MIN / WORLD_MAX are inherited from ApprenticeAPI.)


## Instantiate a PackedScene from the project and add it to the level at (x, y).
## The path must point to an existing PackedScene; coordinates are clamped.
func instantiate_scene(path: String, x: float, y: float) -> Node2D:
	if not is_instance_valid(_world):
		push_error("MasterAPI.instantiate_scene: no valid world reference")
		return null
	if path.is_empty():
		push_error("MasterAPI.instantiate_scene: path must not be empty")
		return null
	if not is_finite(x) or not is_finite(y):
		push_error("MasterAPI.instantiate_scene: x/y must be finite numbers")
		return null
	if not ResourceLoader.exists(path):
		push_error("MasterAPI.instantiate_scene: no resource at '%s'" % path)
		return null

	var resource := ResourceLoader.load(path)
	if not (resource is PackedScene):
		push_error("MasterAPI.instantiate_scene: '%s' is not a scene (PackedScene)" % path)
		return null

	var instance := (resource as PackedScene).instantiate()
	if instance == null:
		push_error("MasterAPI.instantiate_scene: failed to instantiate '%s'" % path)
		return null

	if instance is Node2D:
		var safe_x := clampf(x, WORLD_MIN, WORLD_MAX)
		var safe_y := clampf(y, WORLD_MIN, WORLD_MAX)
		(instance as Node2D).position = Vector2(safe_x, safe_y)

	_world.add_child(instance)
	# Tag it so platform-cleanup spells (clear_all_platforms) can find it.
	instance.set_meta("spawned_by_code", true)

	return instance if instance is Node2D else null


## Connect a signal on `node` to one of its own methods by name.
## NOTE: the tier metadata calls this parameter "signal", but `signal` is a
## reserved GDScript keyword, so the implementation names it `signal_name`.
func connect_signal(node: Node, signal_name: String, method: String) -> void:
	if not is_instance_valid(_world):
		push_error("MasterAPI.connect_signal: no valid world reference")
		return
	if not is_instance_valid(node):
		push_error("MasterAPI.connect_signal: node is not a valid instance")
		return
	if not node.has_signal(signal_name):
		push_error("MasterAPI.connect_signal: node has no signal '%s'" % signal_name)
		return
	if method.is_empty() or not node.has_method(method):
		push_error("MasterAPI.connect_signal: node has no method '%s'" % method)
		return

	var callable := Callable(node, method)
	if node.is_connected(signal_name, callable):
		return  # Already wired; connecting twice would raise an engine error.
	var err := node.connect(signal_name, callable)
	if err != OK:
		push_error("MasterAPI.connect_signal: failed to connect '%s' -> '%s' (error %d)" % [signal_name, method, err])


## Cast a 2D physics ray from (x1, y1) to (x2, y2).
## Returns the intersect_ray() Dictionary (empty {} when nothing was hit).
func physics_raycast(x1: float, y1: float, x2: float, y2: float) -> Dictionary:
	if not is_instance_valid(_world):
		push_error("MasterAPI.physics_raycast: no valid world reference")
		return {}
	if not (_world is Node2D):
		push_error("MasterAPI.physics_raycast: world is not a Node2D")
		return {}
	if not is_finite(x1) or not is_finite(y1) or not is_finite(x2) or not is_finite(y2):
		push_error("MasterAPI.physics_raycast: coordinates must be finite numbers")
		return {}

	var world_2d := (_world as Node2D).get_world_2d()
	if world_2d == null:
		push_error("MasterAPI.physics_raycast: no World2D available")
		return {}
	var space_state := world_2d.direct_space_state
	if space_state == null:
		push_error("MasterAPI.physics_raycast: no physics space state available")
		return {}

	var query := PhysicsRayQueryParameters2D.create(Vector2(x1, y1), Vector2(x2, y2))
	return space_state.intersect_ray(query)
