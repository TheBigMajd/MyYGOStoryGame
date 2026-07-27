extends CharacterBody2D

@export var npc_config_id: String = "card_seller"
@export var duel_prompt_scene_path: String = "res://Scenes/duel_prompt_prototype.tscn"

var npc_config: Dictionary = {}

var npc_id: String = ""
var npc_display_name: String = "NPC"
var greeting_text: String = "Hello."
var shop_scene_path: String = ""
var duel_session_id: String = ""

var player_near: bool = false
var menu_open: bool = false

@onready var interaction_area: Area2D = $InteractionArea
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	npc_config = load_npc_config(npc_config_id)
	_apply_npc_config()

	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)

	_update_idle_animation()


func load_npc_config(config_id: String) -> Dictionary:
	var path := ProjectSettings.globalize_path("res://GameData/configs/npcs/" + config_id + ".json")

	if not FileAccess.file_exists(path):
		push_error("NPC config not found: " + path)
		return {}

	var file := FileAccess.open(path, FileAccess.READ)

	if file == null:
		push_error("Could not open NPC config: " + path)
		return {}

	var parsed = JSON.parse_string(file.get_as_text())
	file.close()

	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Invalid NPC config JSON: " + path)
		return {}

	return parsed


func _apply_npc_config() -> void:
	if npc_config.is_empty():
		return

	npc_id = str(npc_config.get("npc_id", npc_config_id))
	npc_display_name = str(npc_config.get("display_name", "NPC"))

	var default_greeting: Dictionary = npc_config.get("default_greeting", {})
	greeting_text = str(default_greeting.get("text", "Hello."))

	duel_session_id = get_available_duel_session_id()

	var interaction_options: Array = npc_config.get("interaction_options", [])
	for option in interaction_options:
		if typeof(option) != TYPE_DICTIONARY:
			continue

		if str(option.get("type", "")) == "shop":
			shop_scene_path = str(option.get("shop_scene_path", ""))


func has_available_duel() -> bool:
	return get_available_duel_session_id() != ""


func _process(_delta: float) -> void:
	if player_near and not menu_open and Input.is_action_just_pressed("interact"):
		open_menu()


func _update_idle_animation() -> void:
	if animated_sprite == null:
		return

	animated_sprite.play("idle_down")


func _on_body_entered(body: Node) -> void:
	if body.name == "Player":
		player_near = true


func _on_body_exited(body: Node) -> void:
	if body.name == "Player":
		player_near = false


func open_menu() -> void:
	menu_open = true
	duel_session_id = get_available_duel_session_id()

	var menu_scene := load("res://Scenes/UI/NPCInteractionMenu.tscn") as PackedScene

	if menu_scene == null:
		menu_open = false
		push_error("NPCInteractionMenu.tscn failed to load.")
		return

	var menu := menu_scene.instantiate()

	var ui_root := get_tree().current_scene.get_node_or_null("UIRoot")
	if ui_root == null:
		menu_open = false
		push_error("UIRoot not found in World.tscn.")
		return

	ui_root.call_deferred("add_child", menu)
	menu.call_deferred("setup", self)


func get_greeting_text() -> String:
	return greeting_text


func get_portrait_path(emotion: String) -> String:
	var base_profile: Dictionary = npc_config.get("base_profile", {})
	var portraits: Dictionary = base_profile.get("portrait_paths", {})

	var path := str(portraits.get(emotion, ""))

	if path == "":
		path = str(portraits.get("neutral", ""))

	return path


func get_available_duel_session_id() -> String:
	var duel_rules: Array = npc_config.get("duel_rules", [])

	var valid_rules: Array = []

	for rule in duel_rules:
		if typeof(rule) != TYPE_DICTIONARY:
			continue

		var conditions: Dictionary = rule.get("conditions", {})

		if _conditions_met(conditions):
			valid_rules.append(rule)

	if valid_rules.is_empty():
		return ""

	valid_rules.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("priority", 0)) > int(b.get("priority", 0))
	)

	return str(valid_rules[0].get("duel_session_id", ""))


func _conditions_met(conditions: Dictionary) -> bool:
	var condition_manager := get_node_or_null("/root/ConditionManager")

	if condition_manager != null and condition_manager.has_method("conditions_met"):
		return condition_manager.conditions_met(conditions)

	return _basic_conditions_met(conditions)


func _basic_conditions_met(conditions: Dictionary) -> bool:
	var save_data := {}

	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager != null and save_manager.has_method("get_player_save"):
		save_data = save_manager.get_player_save()

	var story_flags: Dictionary = save_data.get("story_flags", {})
	print("STORY FLAGS: ", story_flags)
	print("CONDITIONS: ", conditions)

	for flag in conditions.get("required_flags", []):
		if not bool(story_flags.get(str(flag), false)):
			return false

	for flag in conditions.get("blocked_flags", []):
		if bool(story_flags.get(str(flag), false)):
			return false

	return true


func talk() -> void:
	print(npc_display_name + ": Talk selected.")


func trade() -> void:
	if shop_scene_path == "":
		print("Trade unavailable for " + npc_display_name)
		return

	var shop_scene := load(shop_scene_path) as PackedScene

	if shop_scene == null:
		push_error("Shop scene failed to load. Check path: " + shop_scene_path)
		return

	var shop := shop_scene.instantiate()
	shop.process_mode = Node.PROCESS_MODE_ALWAYS

	var ui_root := get_tree().current_scene.get_node_or_null("UIRoot")
	if ui_root == null:
		push_error("UIRoot not found.")
		return

	ui_root.call_deferred("add_child", shop)
	get_tree().paused = true


func duel() -> void:
	duel_session_id = get_available_duel_session_id()

	if duel_session_id == "":
		print("No duel currently available for " + npc_display_name)
		return

	var duel_scene := load(duel_prompt_scene_path) as PackedScene

	if duel_scene == null:
		push_error("DuelPrompt scene failed to load: " + duel_prompt_scene_path)
		return

	var prompt := duel_scene.instantiate()
	prompt.process_mode = Node.PROCESS_MODE_ALWAYS

	var ui_root := get_tree().current_scene.get_node_or_null("UIRoot")
	if ui_root == null:
		push_error("UIRoot not found.")
		return

	ui_root.call_deferred("add_child", prompt)

	if prompt.has_method("setup_duel"):
		prompt.call_deferred("setup_duel", duel_session_id)

	get_tree().paused = true


func interaction_menu_closed() -> void:
	menu_open = false
