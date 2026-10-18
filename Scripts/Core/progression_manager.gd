extends Node
## ProgressionManager - Tracks unlocked API tiers and level completion
## Autoload singleton - persists across scene changes
## Registered as autoload singleton (do NOT add class_name here)

signal tier_unlocked(tier_name: String)
signal level_completed(level_id: String)
signal zone_completed(zone_id: String)
signal progress_saved

## Save file path (in user:// for write access)
const SAVE_PATH := "user://progress.dat"

## Available API tiers in order
const TIERS: Array[String] = ["Apprentice", "Journeyman", "Master"]

## Current progression state
var current_tier: String = "Apprentice"
var completed_levels: Array[String] = []
var unlocked_tiers: Array[String] = ["Apprentice"]

## Player code solutions (level_id -> code)
var player_solutions: Dictionary = {}

## Current level being played
var current_level: String = ""

## World-zone state (Phase 2 connected world)
var completed_zones: Array[String] = []
var unlocked_zones: Array[String] = []
## zone_id -> { "tier": String, "completed": bool }
var zone_states: Dictionary = {}


func _ready() -> void:
	# Load saved progress on startup
	load_progress()
	print("ProgressionManager loaded. Current tier: ", current_tier)


## Check if a specific tier is unlocked
func is_tier_unlocked(tier_name: String) -> bool:
	return tier_name in unlocked_tiers


## Get the current tier index (for ordering)
func get_tier_index(tier_name: String) -> int:
	return TIERS.find(tier_name)


## Unlock a tier (if not already unlocked)
func unlock_tier(tier_name: String) -> bool:
	if not is_tier_unlocked(tier_name) and tier_name in TIERS:
		unlocked_tiers.append(tier_name)
		tier_unlocked.emit(tier_name)
		save_progress()
		return true
	return false


## Set the current active tier
func set_current_tier(tier_name: String) -> bool:
	if is_tier_unlocked(tier_name):
		current_tier = tier_name
		save_progress()
		return true
	return false


## Mark a level as completed
func complete_level(level_id: String) -> void:
	if level_id not in completed_levels:
		completed_levels.append(level_id)

		# Auto-unlock tiers based on level completion
		_check_tier_unlocks()

		level_completed.emit(level_id)
		save_progress()


## Check if a level is completed
func is_level_completed(level_id: String) -> bool:
	return level_id in completed_levels


## Get all completed levels
func get_completed_levels() -> Array[String]:
	return completed_levels.duplicate()


## ---------------------------------------------------------------------------
## World zones (Phase 2 connected world)
## ---------------------------------------------------------------------------

## Register a world zone so tier-unlock rules can count it. Called by
## WorldStage at startup for every zone, before any completion is processed.
func register_zone(zone_id: String, tier: String = "Apprentice") -> void:
	var state: Dictionary = zone_states.get(zone_id, {})
	state["tier"] = tier
	if not state.has("completed"):
		state["completed"] = zone_id in completed_zones
	zone_states[zone_id] = state


## Mark a world zone as completed (records its tier, checks tier unlocks, saves)
func complete_zone(zone_id: String, tier: String = "") -> void:
	if zone_id in completed_zones:
		return
	completed_zones.append(zone_id)

	var state: Dictionary = zone_states.get(zone_id, {})
	if tier != "":
		state["tier"] = tier
	state["completed"] = true
	zone_states[zone_id] = state

	_check_tier_unlocks()

	zone_completed.emit(zone_id)
	save_progress()


## Check if a world zone is completed
func is_zone_completed(zone_id: String) -> bool:
	return zone_id in completed_zones


## Get all completed world zones
func get_completed_zones() -> Array[String]:
	return completed_zones.duplicate()


## Unlock a zone (called by the world when its required tier becomes available)
func unlock_zone(zone_id: String) -> bool:
	if zone_id not in unlocked_zones:
		unlocked_zones.append(zone_id)
		save_progress()
		return true
	return false


## Check if a world zone is unlocked
func is_zone_unlocked(zone_id: String) -> bool:
	return zone_id in unlocked_zones


## Count completed zones belonging to a tier
func count_completed_zones_for_tier(tier_name: String) -> int:
	var count := 0
	for zone_id in completed_zones:
		if zone_states.get(zone_id, {}).get("tier", "") == tier_name:
			count += 1
	return count


## Count every registered zone (completed or not) belonging to a tier
func count_zones_for_tier(tier_name: String) -> int:
	var count := 0
	for zone_id in zone_states.keys():
		if zone_states[zone_id].get("tier", "") == tier_name:
			count += 1
	return count


## Save player's solution for a level
func save_solution(level_id: String, code: String) -> void:
	player_solutions[level_id] = code
	save_progress()


## Load player's solution for a level
func get_solution(level_id: String) -> String:
	if player_solutions.has(level_id):
		return player_solutions[level_id]
	return ""


## Set current level (for context)
func set_current_level(level_id: String) -> void:
	current_level = level_id


## Check and unlock tiers based on completed WORLD ZONES.
## Rules (Phase 2):
##   Journeyman <- 2 Apprentice zones completed
##   Master      <- ALL Journeyman-tier zones completed
##     (The plan's "3 Journeyman zones" rule becomes literal once three
##     Journeyman zones exist; Phase 2 MVP ships one - The Pattern Forge.)
func _check_tier_unlocks() -> void:
	if count_completed_zones_for_tier("Apprentice") >= 2 and not is_tier_unlocked("Journeyman"):
		unlock_tier("Journeyman")

	var journeyman_total := count_zones_for_tier("Journeyman")
	if journeyman_total > 0 \
			and count_completed_zones_for_tier("Journeyman") >= journeyman_total \
			and not is_tier_unlocked("Master"):
		unlock_tier("Master")


## Save progress to disk
func save_progress() -> void:
	var save_data := {
		"current_tier": current_tier,
		"completed_levels": completed_levels,
		"unlocked_tiers": unlocked_tiers,
		"player_solutions": player_solutions,
		"completed_zones": completed_zones,
		"unlocked_zones": unlocked_zones,
		"zone_states": zone_states,
		"version": 1,
	}

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_var(save_data)
		file.close()
		progress_saved.emit()
	else:
		push_error("Failed to save progress to: " + SAVE_PATH)


## Load progress from disk
func load_progress() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		print("No save file found, starting fresh")
		return

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file:
		var save_data: Dictionary = file.get_var()
		file.close()

		# Validate save data structure
		if save_data.has("version") and save_data["version"] == 1:
			current_tier = save_data.get("current_tier", "Apprentice")
			# NOTE: use assign() - file.get_var() returns untyped Arrays (and
			# missing keys fall back to untyped literals), which cannot be
			# assigned directly to a typed Array[String] variable.
			completed_levels.assign(save_data.get("completed_levels", []))
			unlocked_tiers.assign(save_data.get("unlocked_tiers", ["Apprentice"]))
			player_solutions = save_data.get("player_solutions", {})

			# World-zone state (Phase 2). Older saves simply lack these keys.
			completed_zones.assign(save_data.get("completed_zones", []))
			unlocked_zones.assign(save_data.get("unlocked_zones", []))
			zone_states = save_data.get("zone_states", {})

			# Ensure Apprentice is always unlocked
			if "Apprentice" not in unlocked_tiers:
				unlocked_tiers.append("Apprentice")

			print("Progress loaded: ", completed_levels.size(), " levels completed")
		else:
			push_warning("Save file has invalid version or structure")


## Clear all progress (for testing/debugging)
func reset_progress() -> void:
	current_tier = "Apprentice"
	completed_levels = []
	unlocked_tiers = ["Apprentice"]
	player_solutions = {}
	completed_zones = []
	unlocked_zones = []
	zone_states = {}

	# Delete save file
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)

	print("Progress reset")


## Get API resource path for a tier
func get_api_path_for_tier(tier_name: String) -> String:
	match tier_name:
		"Apprentice":
			return WizardAPI.TIER_APPRENTICE
		"Journeyman":
			return WizardAPI.TIER_JOURNEYMAN
		"Master":
			return WizardAPI.TIER_MASTER
		_:
			return WizardAPI.TIER_APPRENTICE


## Load API resource for current tier
func load_current_api() -> WizardAPI:
	var api_path := get_api_path_for_tier(current_tier)
	if ResourceLoader.exists(api_path):
		return load(api_path)
	return null


## Get tier display name with icon (for UI)
func get_tier_display_info(tier_name: String) -> Dictionary:
	match tier_name:
		"Apprentice":
			return {"name": "Apprentice", "icon": "🪄", "description": "Learn the basics with guided blocks"}
		"Journeyman":
			return {"name": "Journeyman", "icon": "📜", "description": "Write your own code with loops and conditions"}
		"Master":
			return {"name": "Master", "icon": "🧙", "description": "Full power! Create anything you can imagine"}
		_:
			return {"name": tier_name, "icon": "❓", "description": ""}
