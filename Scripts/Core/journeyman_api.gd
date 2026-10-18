extends ApprenticeAPI
class_name JourneymanAPI

## JourneymanAPI - Extends ApprenticeAPI with tweening and safe node lookup
## Unlockable via the Journeyman tier (journeyman_api.tres)

## Tween a Node2D property to a target value over a duration (seconds).
## The duration is clamped to [0, 30] so a spell can never freeze the game
## with an absurdly long tween.
func tween_property(target: Node2D, property: String, to: Variant, duration: float) -> void:
	if not is_instance_valid(_world):
		push_error("JourneymanAPI.tween_property: no valid world reference")
		return
	if not is_instance_valid(target):
		push_error("JourneymanAPI.tween_property: target is not a valid node")
		return
	if property.is_empty():
		push_error("JourneymanAPI.tween_property: property must not be empty")
		return
	if not is_finite(duration):
		push_error("JourneymanAPI.tween_property: duration must be a finite number")
		return

	# Support indexed paths like "position:x" by validating the base property.
	var base_property := property.split(":")[0]
	if not (base_property in target):
		push_error("JourneymanAPI.tween_property: node has no property '%s'" % base_property)
		return

	var safe_duration := clampf(duration, 0.0, 30.0)
	var tween := _world.create_tween()
	tween.tween_property(target, property, to, safe_duration)


## Look up a node relative to the level (world). Rejects path traversal so a
## spell cannot escape the sandbox up to the scene tree root.
func get_node(path: String) -> Node:
	if not is_instance_valid(_world):
		push_error("JourneymanAPI.get_node: no valid world reference")
		return null
	if path.begins_with("/root/") or path.contains(".."):
		push_error("JourneymanAPI.get_node: path traversal is not allowed")
		return null
	return _world.get_node_or_null(path)
