extends Node2D
class_name PuzzleZone

## PuzzleZone - Data + trigger for one gated puzzle area inside the world stage.
##
## Purely declarative: WorldStage owns all orchestration (zone detection, tier
## gating, code execution, completion). The trigger Area2D is built at runtime
## from zone_bounds so the scene stays free of per-zone shape boilerplate.
##
## Convention: zone nodes are placed at the world origin (0, 0), so the local
## zone_bounds double as world coordinates. Children (goal, labels, terrain)
## are authored in world coordinates too.

@export_group("Identity")
@export var zone_id: String = "zone_01"
@export var zone_title: String = "The Awakening"
@export var zone_description: String = "Learn to spawn platforms with code!"
@export var required_tier: String = "Apprentice"

@export_group("Trigger")
## Trigger area relative to this node. Large enough to cover the whole zone,
## including the air where the player builds with code.
@export var zone_bounds: Rect2 = Rect2(-60, 100, 1920, 750)

@export_group("Win Condition")
## Goal area - the zone completes when the player reaches it. Optional; a zone
## may define a goal, a minimum platform count, or both.
@export_node_path("Area2D") var goal_path: NodePath
## When > 0, the zone completes once this many code-spawned platforms exist
## inside zone_bounds after a successful spell.
@export var min_spawned_platforms: int = 0
## Optional substring the player's code must contain before a run is accepted
## (e.g. "physics_raycast" for the Master trial).
@export var required_function: String = ""

@export_group("Hints")
## Cycled through by the code editor's Hint button.
@export var hints: Array = []

## Runtime state (persisted through ProgressionManager)
var is_completed: bool = false
var is_locked: bool = false

## Resolved references
var goal: Area2D = null
var _trigger: Area2D = null


func _ready() -> void:
	goal = get_node_or_null(goal_path) if goal_path != NodePath("") else null
	_build_trigger()


## The runtime-built detection trigger (WorldStage connects to its signals)
func get_trigger() -> Area2D:
	return _trigger


## Zone bounds in world space
func get_global_bounds() -> Rect2:
	return Rect2(zone_bounds.position + global_position, zone_bounds.size)


## Is a world-space point inside this zone?
func contains_point(point: Vector2) -> bool:
	return get_global_bounds().has_point(point)


func _build_trigger() -> void:
	_trigger = Area2D.new()
	_trigger.name = "ZoneTrigger"
	_trigger.position = zone_bounds.get_center()

	var shape_node := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = zone_bounds.size
	shape_node.shape = shape
	_trigger.add_child(shape_node)

	add_child(_trigger)
