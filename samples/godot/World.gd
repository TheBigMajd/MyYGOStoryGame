extends Node2D

@onready var area_container: Node2D = $AreaContainer
@onready var player: CharacterBody2D = $Player

@export_file("*.tscn") var starting_area_scene: String = ""
@export var starting_spawn_name: String = "PlayerSpawn"

var is_loading_area: bool = false
var current_area_scene_path: String = ""
var current_area_id: String = ""
var current_spawn_name: String = ""


func _ready() -> void:
	var saved_area_scene := ""
	var saved_spawn_name := ""
	var saved_player_position := Vector2.ZERO

	if SaveManager != null:
		if SaveManager.has_method("get_current_area_scene"):
			saved_area_scene = str(SaveManager.get_current_area_scene()).strip_edges()

		if SaveManager.has_method("get_current_spawn_id"):
			saved_spawn_name = str(SaveManager.get_current_spawn_id()).strip_edges()

		if SaveManager.has_method("get_player_position"):
			saved_player_position = SaveManager.get_player_position()

	saved_area_scene = _resolve_scene_path(saved_area_scene)

	if saved_area_scene != "" and ResourceLoader.exists(saved_area_scene):
		if saved_spawn_name != "":
			load_area(saved_area_scene, saved_spawn_name)
		else:
			load_area_at_position(saved_area_scene, saved_player_position)
	else:
		load_area(starting_area_scene, starting_spawn_name)


func load_area(area_scene_path: String, spawn_name: String) -> void:
	if is_loading_area:
		return

	is_loading_area = true

	call_deferred(
		"_load_area_deferred",
		area_scene_path,
		spawn_name,
		false,
		Vector2.ZERO
	)


func load_area_at_position(area_scene_path: String, player_position: Vector2) -> void:
	if is_loading_area:
		return

	is_loading_area = true

	call_deferred(
		"_load_area_deferred",
		area_scene_path,
		"",
		true,
		player_position
	)


func _load_area_deferred(
	area_scene_path: String,
	spawn_name: String,
	use_saved_position: bool = false,
	saved_position: Vector2 = Vector2.ZERO
) -> void:
	area_scene_path = _resolve_scene_path(area_scene_path)

	if player == null or not is_instance_valid(player):
		push_error("Player is missing or was freed before loading area.")
		is_loading_area = false
		return

	if player.get_parent() != self:
		player.reparent(self)
		print("Player temporarily reparented to World before clearing old area.")

	for child: Node in area_container.get_children():
		child.queue_free()

	await get_tree().process_frame

	if player == null or not is_instance_valid(player):
		push_error("Player was freed while clearing old area.")
		is_loading_area = false
		return

	var packed_scene: PackedScene = load(area_scene_path) as PackedScene

	if packed_scene == null:
		is_loading_area = false
		push_error("Could not load area: " + area_scene_path)
		return

	var area: Node = packed_scene.instantiate()
	area_container.add_child(area)

	var music_manager := get_node_or_null("/root/MusicManager")
	if music_manager != null and music_manager.has_method("play_area_scene"):
		music_manager.play_area_scene(area_scene_path)

	var ysort_objects: Node = area.get_node_or_null("YSortObjects")

	if ysort_objects != null:
		player.reparent(ysort_objects)
		print("Player reparented to YSortObjects.")
	else:
		push_warning("YSortObjects node not found in loaded area. Player stays under World.")

	if use_saved_position:
		player.global_position = saved_position
		print("Loaded player at saved position: ", saved_position)
	else:
		var spawn: Node = area.get_node_or_null("SpawnPoints/" + spawn_name)

		if spawn != null and spawn is Node2D:
			player.global_position = spawn.global_position
			print("Spawned player at: " + spawn_name)
		else:
			push_error("Spawn not found: " + spawn_name)

	current_area_scene_path = area_scene_path
	current_area_id = _get_area_id_from_loaded_area(area, area_scene_path)
	current_spawn_name = spawn_name

	_update_save_manager_world_state(false)

	is_loading_area = false


func save_current_world_state(autosave_enabled := false) -> void:
	_update_save_manager_world_state(autosave_enabled)


func _update_save_manager_world_state(autosave_enabled := false) -> void:
	if SaveManager == null:
		return

	if not SaveManager.has_method("set_current_world_state"):
		return

	if player == null or not is_instance_valid(player):
		return

	if current_area_scene_path.strip_edges() == "":
		return

	if current_area_id.strip_edges() == "":
		current_area_id = _get_area_id_from_scene_path(current_area_scene_path)

	SaveManager.set_current_world_state(
		current_area_scene_path,
		current_area_id,
		current_spawn_name,
		player.global_position,
		autosave_enabled
	)


func get_current_area_scene_path() -> String:
	return current_area_scene_path


func get_current_area_id() -> String:
	return current_area_id


func get_current_spawn_name() -> String:
	return current_spawn_name


func _get_area_id_from_loaded_area(area: Node, area_scene_path: String) -> String:
	if area != null:
		if _node_has_property(area, "area_id"):
			var raw_area_id = area.get("area_id")
			var area_id := str(raw_area_id).strip_edges()

			if area_id != "":
				return area_id

		if area.name.strip_edges() != "":
			return str(area.name).strip_edges()

	return _get_area_id_from_scene_path(area_scene_path)


func _get_area_id_from_scene_path(area_scene_path: String) -> String:
	var resolved_path := _resolve_scene_path(area_scene_path)
	var file_name := resolved_path.get_file().get_basename().strip_edges()

	if file_name != "":
		return file_name

	return "UnknownArea"


func _node_has_property(node: Object, property_name: String) -> bool:
	for property in node.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true

	return false


func _resolve_scene_path(path: String) -> String:
	path = path.strip_edges()

	if path == "":
		return ""

	if path.begins_with("uid://"):
		var uid := ResourceUID.text_to_id(path)
		var resolved := ResourceUID.get_id_path(uid)

		if resolved != "":
			return resolved

	return path
