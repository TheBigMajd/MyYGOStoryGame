extends Control

signal cutscene_finished(cutscene_id: String)

@export var dialogue_panel_path: NodePath = "DialogBox"
@export var portrait_texture_path: NodePath = "PortraitLayer/PortraitTextureRect"
@export var speaker_name_path: NodePath = "DialogBox/DialogContent/SpeakerName"
@export var dialogue_text_path: NodePath = "DialogBox/DialogContent/DialogText"
@export var continue_prompt_path: NodePath = "ContinuePrompt"
@export var music_player_path: NodePath = "MusicPlayer"
@export var sfx_player_path: NodePath = "SFXPlayer"

@export var interact_action: String = "interact"
@export var default_move_speed: float = 120.0
@export var hide_dialogue_between_lines: bool = false

var cutscene_id: String = ""
var cutscene_data: Dictionary = {}
var is_playing: bool = false

var _player_node: Node = null
var _previous_player_process: bool = true
var _previous_player_physics_process: bool = true

@onready var dialogue_panel: Control = get_node_or_null(dialogue_panel_path)
@onready var portrait_texture: TextureRect = get_node_or_null(portrait_texture_path)
@onready var speaker_name_label: Label = get_node_or_null(speaker_name_path)
@onready var dialogue_text_label: RichTextLabel = get_node_or_null(dialogue_text_path)
@onready var continue_prompt: Control = get_node_or_null(continue_prompt_path)
@onready var music_player: AudioStreamPlayer = get_node_or_null(music_player_path)
@onready var sfx_player: AudioStreamPlayer = get_node_or_null(sfx_player_path)


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hide_dialogue()


func start_cutscene(data: Dictionary) -> void:
	await play_cutscene(data)

	if is_inside_tree():
		queue_free()


func play_cutscene_from_file(cutscene_path: String) -> void:
	var loaded_data := _load_json(cutscene_path)

	if loaded_data.is_empty():
		push_error("In-game cutscene failed to load: " + cutscene_path)
		return

	await play_cutscene(loaded_data)


func play_cutscene(data: Dictionary) -> void:
	if is_playing:
		push_warning("In-game cutscene already playing.")
		return

	cutscene_data = data
	cutscene_id = str(cutscene_data.get("cutscene_id", ""))
	is_playing = true
	visible = true

	_freeze_player()
	await _run_steps(cutscene_data.get("steps", []))
	_unfreeze_player()

	_hide_dialogue()
	visible = false
	is_playing = false

	cutscene_finished.emit(cutscene_id)


func _run_steps(steps: Array) -> void:
	for step in steps:
		if typeof(step) != TYPE_DICTIONARY:
			continue

		var action := str(step.get("action", "")).strip_edges()

		match action:
			"dialogue":
				await _step_dialogue(step)
			"move_npc":
				await _step_move_npc(step)
			"teleport_npc":
				_step_teleport_npc(step)
			"face_npc":
				_step_face_npc(step)
			"show_npc":
				_step_show_npc(step)
			"hide_npc":
				_step_hide_npc(step)
			"despawn_npc":
				_step_despawn_npc(step)
			"wait":
				await _step_wait(step)
			"play_music":
				_step_play_music(step)
			"stop_music":
				_step_stop_music()
			"play_sfx":
				_step_play_sfx(step)
			"set_flags":
				_set_flags(step.get("flags", []))
			"remove_flags":
				_remove_flags(step.get("flags", []))
			"call_method":
				_step_call_method(step)
			_:
				push_warning("Unknown in-game cutscene action: " + action)


func _step_dialogue(step: Dictionary) -> void:
	var speaker := str(step.get("speaker_name", step.get("speaker", "")))
	var text := str(step.get("text", ""))
	var portrait_path := str(step.get("portrait", ""))

	if speaker_name_label != null:
		speaker_name_label.text = speaker

	if dialogue_text_label != null:
		dialogue_text_label.clear()
		dialogue_text_label.append_text(text)

	if portrait_texture != null:
		if portrait_path.strip_edges() != "":
			var texture := load(portrait_path)
			if texture is Texture2D:
				portrait_texture.texture = texture
				portrait_texture.visible = true
			else:
				portrait_texture.texture = null
				portrait_texture.visible = false
		else:
			portrait_texture.texture = null
			portrait_texture.visible = false

	_show_dialogue()
	await _wait_for_interact()

	if hide_dialogue_between_lines:
		_hide_dialogue()


func _step_move_npc(step: Dictionary) -> void:
	var npc := _find_npc(str(step.get("npc_id", "")))

	if npc == null:
		push_warning("move_npc failed. NPC not found: " + str(step.get("npc_id", "")))
		return

	var to_data: Dictionary = step.get("to", {})
	var target := Vector2(float(to_data.get("x", npc.global_position.x)), float(to_data.get("y", npc.global_position.y)))
	var speed := float(step.get("speed", default_move_speed))

	if speed <= 0.0:
		npc.global_position = target
		return

	_play_npc_move_animation(npc, target)

	while npc != null and is_instance_valid(npc) and npc.global_position.distance_to(target) > 2.0:
		var delta := get_process_delta_time()
		var direction := npc.global_position.direction_to(target)
		npc.global_position += direction * speed * delta

		if npc.global_position.distance_to(target) < speed * delta:
			npc.global_position = target

		await get_tree().process_frame

	if npc != null and is_instance_valid(npc):
		npc.global_position = target
		_play_npc_idle_animation(npc, step)


func _step_teleport_npc(step: Dictionary) -> void:
	var npc := _find_npc(str(step.get("npc_id", "")))
	if npc == null:
		return

	var to_data: Dictionary = step.get("to", {})
	npc.global_position = Vector2(float(to_data.get("x", npc.global_position.x)), float(to_data.get("y", npc.global_position.y)))

	if step.has("facing"):
		_set_npc_facing(npc, str(step.get("facing", "down")))


func _step_face_npc(step: Dictionary) -> void:
	var npc := _find_npc(str(step.get("npc_id", "")))
	if npc != null:
		_set_npc_facing(npc, str(step.get("facing", "down")))


func _step_show_npc(step: Dictionary) -> void:
	var npc := _find_npc(str(step.get("npc_id", "")))
	if npc == null:
		return

	npc.visible = true
	npc.set_process(true)
	npc.set_physics_process(true)


func _step_hide_npc(step: Dictionary) -> void:
	var npc := _find_npc(str(step.get("npc_id", "")))
	if npc == null:
		return

	npc.visible = false
	npc.set_process(false)
	npc.set_physics_process(false)


func _step_despawn_npc(step: Dictionary) -> void:
	var npc := _find_npc(str(step.get("npc_id", "")))
	if npc == null:
		return

	npc.visible = false
	npc.set_process(false)
	npc.set_physics_process(false)
	npc.queue_free()


func _step_wait(step: Dictionary) -> void:
	var seconds := float(step.get("seconds", 0.5))
	await get_tree().create_timer(max(seconds, 0.0)).timeout


func _step_play_music(step: Dictionary) -> void:
	if music_player == null:
		return

	var path := str(step.get("path", ""))
	if path == "":
		return

	var stream := load(path)
	if stream is AudioStream:
		music_player.stream = stream
		music_player.play()


func _step_stop_music() -> void:
	if music_player != null:
		music_player.stop()


func _step_play_sfx(step: Dictionary) -> void:
	if sfx_player == null:
		return

	var path := str(step.get("path", ""))
	if path == "":
		return

	var stream := load(path)
	if stream is AudioStream:
		sfx_player.stream = stream
		sfx_player.play()


func _step_call_method(step: Dictionary) -> void:
	var node_path := str(step.get("node_path", ""))
	var method_name := str(step.get("method", ""))

	if node_path == "" or method_name == "":
		return

	var target_node := get_tree().current_scene.get_node_or_null(node_path)
	if target_node == null:
		push_warning("call_method target not found: " + node_path)
		return

	if not target_node.has_method(method_name):
		push_warning("call_method missing method: " + method_name)
		return

	var args: Array = step.get("args", [])
	target_node.callv(method_name, args)


func _show_dialogue() -> void:
	if dialogue_panel != null:
		dialogue_panel.visible = true

	if continue_prompt != null:
		continue_prompt.visible = true


func _hide_dialogue() -> void:
	if dialogue_panel != null:
		dialogue_panel.visible = false

	if continue_prompt != null:
		continue_prompt.visible = false


func _wait_for_interact() -> void:
	while true:
		if Input.is_action_just_pressed(interact_action):
			await get_tree().process_frame
			return

		await get_tree().process_frame


func _freeze_player() -> void:
	_player_node = get_tree().get_first_node_in_group("player")

	if _player_node == null:
		_player_node = _find_node_by_name(get_tree().current_scene, "Player")

	if _player_node == null:
		return

	_previous_player_process = _player_node.is_processing()
	_previous_player_physics_process = _player_node.is_physics_processing()

	_player_node.set_process(false)
	_player_node.set_physics_process(false)

	if _player_node.has_method("set_input_enabled"):
		_player_node.call("set_input_enabled", false)

	if _object_has_property(_player_node, "input_enabled"):
		_player_node.set("input_enabled", false)


func _unfreeze_player() -> void:
	if _player_node == null:
		return

	_player_node.set_process(_previous_player_process)
	_player_node.set_physics_process(_previous_player_physics_process)

	if _player_node.has_method("set_input_enabled"):
		_player_node.call("set_input_enabled", true)

	if _object_has_property(_player_node, "input_enabled"):
		_player_node.set("input_enabled", true)

	_player_node = null


func _find_npc(npc_id: String) -> Node2D:
	if npc_id.strip_edges() == "":
		return null

	var candidates := get_tree().get_nodes_in_group("spawn_controlled_npcs")

	for candidate in candidates:
		if candidate == null:
			continue

		if _object_has_property(candidate, "npc_id") and str(candidate.get("npc_id")) == npc_id:
			if candidate is Node2D:
				return candidate

	var root := get_tree().current_scene
	return _find_npc_recursive(root, npc_id)


func _find_npc_recursive(node: Node, npc_id: String) -> Node2D:
	if node == null:
		return null

	if _object_has_property(node, "npc_id"):
		var value = node.get("npc_id")
		if str(value) == npc_id and node is Node2D:
			return node

	for child in node.get_children():
		var found := _find_npc_recursive(child, npc_id)
		if found != null:
			return found

	return null


func _find_node_by_name(node: Node, target_name: String) -> Node:
	if node == null:
		return null

	if node.name == target_name:
		return node

	for child in node.get_children():
		var found := _find_node_by_name(child, target_name)
		if found != null:
			return found

	return null


func _play_npc_move_animation(npc: Node2D, target: Vector2) -> void:
	var direction := target - npc.global_position
	var facing := _direction_to_facing(direction)
	var sprite := _get_npc_sprite(npc)

	if sprite == null:
		_set_npc_facing(npc, facing)
		return

	var walk_anim := "walk_" + facing
	var idle_anim := "idle_" + facing

	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation(walk_anim):
		sprite.play(walk_anim)
	elif sprite.sprite_frames != null and sprite.sprite_frames.has_animation(idle_anim):
		sprite.play(idle_anim)

	_set_npc_facing(npc, facing)


func _play_npc_idle_animation(npc: Node2D, step: Dictionary = {}) -> void:
	var facing := str(step.get("end_facing", ""))

	if facing == "" and _object_has_property(npc, "current_idle_direction"):
		facing = str(npc.get("current_idle_direction"))

	if facing == "":
		facing = "down"

	_set_npc_facing(npc, facing)

	var sprite := _get_npc_sprite(npc)
	if sprite == null:
		return

	var idle_anim := "idle_" + facing

	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation(idle_anim):
		sprite.play(idle_anim)


func _set_npc_facing(npc: Node, facing: String) -> void:
	if npc == null:
		return

	if npc.has_method("set_spawn_facing"):
		npc.call("set_spawn_facing", facing)
		return

	if npc.has_method("set_facing"):
		npc.call("set_facing", facing)
		return

	if _object_has_property(npc, "current_idle_direction"):
		npc.set("current_idle_direction", facing)

	var sprite := _get_npc_sprite(npc)
	if sprite != null:
		var idle_anim := "idle_" + facing

		if sprite.sprite_frames != null and sprite.sprite_frames.has_animation(idle_anim):
			sprite.play(idle_anim)


func _direction_to_facing(direction: Vector2) -> String:
	if abs(direction.x) > abs(direction.y):
		if direction.x >= 0:
			return "east"
		return "west"

	if direction.y >= 0:
		return "down"

	return "up"


func _get_npc_sprite(npc: Node) -> AnimatedSprite2D:
	if npc == null:
		return null

	var direct = npc.get_node_or_null("AnimatedSprite2D")
	if direct is AnimatedSprite2D:
		return direct

	for child in npc.get_children():
		if child is AnimatedSprite2D:
			return child

	return null


func _set_flags(flags: Array) -> void:
	if flags.is_empty():
		return

	var save_data := SaveManager.get_save_data()

	if typeof(save_data.get("story_flags")) != TYPE_DICTIONARY:
		save_data["story_flags"] = {}

	var story_flags: Dictionary = save_data["story_flags"]

	for flag in flags:
		var flag_string := str(flag).strip_edges()
		if flag_string != "":
			story_flags[flag_string] = true


func _remove_flags(flags: Array) -> void:
	if flags.is_empty():
		return

	var save_data := SaveManager.get_save_data()

	if typeof(save_data.get("story_flags")) != TYPE_DICTIONARY:
		return

	var story_flags: Dictionary = save_data["story_flags"]

	for flag in flags:
		var flag_string := str(flag).strip_edges()
		if story_flags.has(flag_string):
			story_flags.erase(flag_string)


func _object_has_property(object: Object, property_name: String) -> bool:
	if object == null:
		return false

	for property in object.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true

	return false


func _load_json(path: String) -> Dictionary:
	var global_path := ProjectSettings.globalize_path(path)

	if not FileAccess.file_exists(global_path):
		push_error("JSON file not found: " + global_path)
		return {}

	var file := FileAccess.open(global_path, FileAccess.READ)

	if file == null:
		push_error("Could not open JSON: " + global_path)
		return {}

	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)

	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Invalid JSON dictionary: " + global_path)
		return {}

	return parsed
