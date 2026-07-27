extends Node

const CUTSCENE_DIR := "res://GameData/configs/cutscenes/"
const PNG_CUTSCENE_PLAYER_SCENE := "res://Scenes/UI/PNGCutscenePlayer.tscn"
const VIDEO_CUTSCENE_PLAYER_SCENE := "res://Scenes/UI/VideoCutscenePlayer.tscn"
const INGAME_CUTSCENE_PLAYER_SCENE := "res://Scenes/UI/InGameCutscenePlayer.tscn"

var is_playing_cutscene: bool = false
var current_cutscene_id: String = ""


func play_cutscene(cutscene_id: String) -> void:
	cutscene_id = cutscene_id.strip_edges()

	if cutscene_id == "":
		return

	if is_playing_cutscene:
		push_warning("Cutscene already playing. Ignored: " + cutscene_id)
		return

	var cutscene_data := _load_cutscene(cutscene_id)

	if cutscene_data.is_empty():
		push_warning("Cutscene not found or invalid: " + cutscene_id)
		return

	var play_once_event := str(cutscene_data.get("play_once_event", "")).strip_edges()

	if play_once_event != "" and SaveManager.is_event_triggered(play_once_event):
		return

	var cutscene_type := str(cutscene_data.get("type", "png")).strip_edges().to_lower()

	match cutscene_type:
		"png", "slideshow", "slides":
			_play_ui_cutscene(cutscene_id, cutscene_data, PNG_CUTSCENE_PLAYER_SCENE, true)

		"video", "movie":
			_play_ui_cutscene(cutscene_id, cutscene_data, VIDEO_CUTSCENE_PLAYER_SCENE, true)

		"ingame", "in_game", "world":
			_play_ui_cutscene(cutscene_id, cutscene_data, INGAME_CUTSCENE_PLAYER_SCENE, false)

		_:
			push_warning("Unsupported cutscene type: " + cutscene_type)


func _play_ui_cutscene(cutscene_id: String, cutscene_data: Dictionary, scene_path: String, should_pause_tree: bool) -> void:
	var scene := load(scene_path) as PackedScene

	if scene == null:
		push_error("Could not load cutscene player scene: " + scene_path)
		return

	var ui_root := _get_ui_root()

	if ui_root == null:
		push_error("CutsceneManager could not find UIRoot.")
		return

	var player := scene.instantiate()

	if not player.has_method("start_cutscene"):
		push_error("Cutscene player scene does not have start_cutscene(): " + scene_path)
		player.queue_free()
		return

	is_playing_cutscene = true
	current_cutscene_id = cutscene_id

	if MusicManager != null:
		MusicManager.pause_music()

	if should_pause_tree:
		get_tree().paused = true

	ui_root.add_child(player)
	player.process_mode = Node.PROCESS_MODE_ALWAYS

	player.cutscene_finished.connect(_on_cutscene_finished.bind(cutscene_data, should_pause_tree))
	player.start_cutscene(cutscene_data)


func _on_cutscene_finished(cutscene_data: Dictionary, should_pause_tree: bool) -> void:
	var play_once_event := str(cutscene_data.get("play_once_event", "")).strip_edges()

	if play_once_event != "":
		SaveManager.trigger_event(play_once_event, false)

	var on_finished: Dictionary = cutscene_data.get("on_finished", {})

	if typeof(on_finished) == TYPE_DICTIONARY and not on_finished.is_empty():
		SaveManager.apply_effects(on_finished, false)

	SaveManager.save_game("cutscene_finished")

	if should_pause_tree:
		get_tree().paused = false

	if MusicManager != null:
		MusicManager.resume_current_zone()

	is_playing_cutscene = false
	current_cutscene_id = ""


func _load_cutscene(cutscene_id: String) -> Dictionary:
	var path := CUTSCENE_DIR.path_join(cutscene_id + ".json")

	if not FileAccess.file_exists(path):
		push_warning("Cutscene JSON missing: " + path)
		return {}

	var file := FileAccess.open(path, FileAccess.READ)

	if file == null:
		push_warning("Could not open cutscene JSON: " + path)
		return {}

	var parsed = JSON.parse_string(file.get_as_text())
	file.close()

	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Invalid cutscene JSON: " + path)
		return {}

	return parsed


func _get_ui_root() -> Node:
	var current_scene := get_tree().current_scene

	if current_scene == null:
		return null

	var ui_root := current_scene.get_node_or_null("UIRoot")

	if ui_root != null:
		return ui_root

	return current_scene.find_child("UIRoot", true, false)
