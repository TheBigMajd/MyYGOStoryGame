extends Node

const ACTIVE_SLOT_PATH := "res://GameData/runtime/active_save_slot.json"
const SAVE_TEMPLATE_PATH := "res://GameData/save_templates/default_new_game/player_save.json"
const UNLOCKED_CARDS_TEMPLATE_PATH := "res://GameData/save_templates/default_new_game/unlocked_cards.json"
const SAVES_FOLDER := "res://GameData/saves"

const BACKUP_COUNT := 3

var save_data: Dictionary = {}
var active_slot: String = "slot_1"
var active_save_path: String = ""

var saving_blocked: bool = false
var save_block_reason: String = ""


func _ready() -> void:
	load_active_slot()
	load_game()


func load_active_slot() -> void:
	if not FileAccess.file_exists(ACTIVE_SLOT_PATH):
		active_slot = "slot_1"
		save_json_direct(ACTIVE_SLOT_PATH, {"active_slot": active_slot})
		return

	var data = load_json_direct(ACTIVE_SLOT_PATH)

	if typeof(data) == TYPE_DICTIONARY:
		active_slot = str(data.get("active_slot", "slot_1"))
	else:
		active_slot = "slot_1"


func set_active_slot(slot_name: String) -> void:
	if slot_name.strip_edges() == "":
		return

	active_slot = slot_name
	save_json_direct(ACTIVE_SLOT_PATH, {"active_slot": active_slot})
	load_game()


func get_active_save_path() -> String:
	return SAVES_FOLDER.path_join(active_slot).path_join("player_save.json")


func get_active_save_folder() -> String:
	return SAVES_FOLDER.path_join(active_slot)


func load_game() -> void:
	active_save_path = get_active_save_path()

	if not FileAccess.file_exists(active_save_path):
		create_new_save_from_template()

	var loaded = load_json_direct(active_save_path)

	if typeof(loaded) == TYPE_DICTIONARY and not loaded.is_empty():
		save_data = loaded
	else:
		var recovered = recover_from_backup()

		if typeof(recovered) == TYPE_DICTIONARY and not recovered.is_empty():
			save_data = recovered
			save_game("recovered")
		else:
			save_data = get_default_save()
			save_game("created_after_corruption")

	ensure_save_defaults()
	save_game("load_repair")


func create_new_save_from_template() -> void:
	if FileAccess.file_exists(SAVE_TEMPLATE_PATH):
		var template = load_json_direct(SAVE_TEMPLATE_PATH)

		if typeof(template) == TYPE_DICTIONARY and not template.is_empty():
			save_json_direct(active_save_path, template)
			return

	save_json_direct(active_save_path, get_default_save())


func create_new_game_in_slot(
	slot_name: String,
	player_name: String,
	first_area_scene: String = "res://Scenes/Areas/PlayerHouse.tscn",
	first_area_id: String = "PlayerHouse",
	first_spawn_id: String = "NewGameStart"
) -> bool:
	if not is_valid_save_slot(slot_name):
		push_error("SaveManager.create_new_game_in_slot failed. Invalid slot: " + slot_name)
		return false

	player_name = player_name.strip_edges()

	if player_name == "":
		push_error("SaveManager.create_new_game_in_slot failed. Player name is empty.")
		return false

	if not FileAccess.file_exists(SAVE_TEMPLATE_PATH):
		push_error("Missing default player_save template: " + SAVE_TEMPLATE_PATH)
		return false

	if not FileAccess.file_exists(UNLOCKED_CARDS_TEMPLATE_PATH):
		push_error("Missing default unlocked_cards template: " + UNLOCKED_CARDS_TEMPLATE_PATH)
		return false

	var slot_folder: String = SAVES_FOLDER.path_join(slot_name)
	var target_player_save: String = slot_folder.path_join("player_save.json")
	var target_unlocked_cards: String = slot_folder.path_join("unlocked_cards.json")

	if not _copy_file_text(SAVE_TEMPLATE_PATH, target_player_save):
		push_error("Failed to copy template player_save.json into: " + target_player_save)
		return false

	if not _copy_file_text(UNLOCKED_CARDS_TEMPLATE_PATH, target_unlocked_cards):
		push_error("Failed to copy template unlocked_cards.json into: " + target_unlocked_cards)
		return false

	active_slot = slot_name
	active_save_path = target_player_save
	save_json_direct(ACTIVE_SLOT_PATH, {"active_slot": active_slot})

	var loaded = load_json_direct(active_save_path)

	if typeof(loaded) == TYPE_DICTIONARY and not loaded.is_empty():
		save_data = loaded
	else:
		save_data = get_default_save()

	ensure_save_defaults()

	save_data["player_name"] = player_name
	save_data["current_area_scene"] = first_area_scene
	save_data["current_area_id"] = first_area_id
	save_data["current_spawn_id"] = first_spawn_id
	save_data["player_position"] = {
		"x": 0.0,
		"y": 0.0
	}

	if typeof(save_data.get("calendar")) != TYPE_DICTIONARY:
		save_data["calendar"] = {}

	save_data["calendar"]["day"] = 1
	save_data["calendar"]["hour"] = 8
	save_data["calendar"]["minute"] = 0
	save_data["calendar"]["season"] = ""
	save_data["calendar"]["time_of_day"] = "morning"

	return save_game("new_game_created")


func _copy_file_text(source_path: String, target_path: String) -> bool:
	if not FileAccess.file_exists(source_path):
		return false

	var text: String = read_text(source_path)

	if text.strip_edges() == "":
		return false

	return write_text(target_path, text)


func recover_from_backup() -> Dictionary:
	for index in range(1, BACKUP_COUNT + 1):
		var backup_path := get_backup_path(index)

		if not FileAccess.file_exists(backup_path):
			continue

		var backup_data = load_json_direct(backup_path)

		if typeof(backup_data) == TYPE_DICTIONARY and not backup_data.is_empty():
			print("SaveManager recovered save from backup: ", backup_path)
			return backup_data

	return {}


func reload_game() -> void:
	load_game()


func save_game(save_type := "autosave") -> bool:
	if saving_blocked:
		push_warning("SaveManager blocked save. Reason: " + save_block_reason)
		return false

	ensure_save_defaults()

	if save_type != "cutscene_finished":
		capture_current_world_state(false)

	update_metadata(save_type)

	var temp_path := active_save_path + ".tmp"

	var temp_ok := save_json_direct(temp_path, save_data)

	if not temp_ok:
		push_error("SaveManager failed to write temp save.")
		return false

	if not is_valid_json_file(temp_path):
		push_error("SaveManager temp save validation failed.")
		return false

	rotate_backups()

	var main_text := read_text(temp_path)
	var main_ok := write_text(active_save_path, main_text)

	if not main_ok:
		push_error("SaveManager failed to replace main save.")
		return false

	if FileAccess.file_exists(temp_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))

	return true


func manual_save() -> bool:
	return save_game("manual")


func autosave() -> bool:
	return save_game("autosave")


func block_saving(reason := "") -> void:
	saving_blocked = true
	save_block_reason = reason


func unblock_saving() -> void:
	saving_blocked = false
	save_block_reason = ""


func is_saving_blocked() -> bool:
	return saving_blocked


func rotate_backups() -> void:
	if not FileAccess.file_exists(active_save_path):
		return

	for index in range(BACKUP_COUNT, 1, -1):
		var older := get_backup_path(index - 1)
		var newer := get_backup_path(index)

		if FileAccess.file_exists(older):
			var older_text := read_text(older)
			write_text(newer, older_text)

	var current_text := read_text(active_save_path)
	write_text(get_backup_path(1), current_text)


func get_backup_path(index: int) -> String:
	return active_save_path + ".bak" + str(index)


func update_metadata(save_type: String) -> void:
	if not save_data.has("save_metadata") or typeof(save_data["save_metadata"]) != TYPE_DICTIONARY:
		save_data["save_metadata"] = {}

	save_data["save_metadata"]["last_saved_unix"] = Time.get_unix_time_from_system()
	save_data["save_metadata"]["last_save_type"] = save_type
	save_data["save_metadata"]["active_slot"] = active_slot
	save_data["save_metadata"]["current_area_id"] = str(save_data.get("current_area_id", ""))
	save_data["save_metadata"]["current_area_scene"] = str(save_data.get("current_area_scene", ""))
	save_data["save_metadata"]["current_spawn_id"] = str(save_data.get("current_spawn_id", ""))


func is_valid_json_file(path: String) -> bool:
	var data = load_json_direct(path)
	return typeof(data) == TYPE_DICTIONARY and not data.is_empty()


func get_default_save() -> Dictionary:
	return {
		"save_version": 1,
		"player_name": "",
		"currency": 0,

		"save_metadata": {
			"last_saved_unix": 0,
			"last_save_type": "",
			"active_slot": active_slot,
			"current_area_id": "",
			"current_area_scene": "",
			"current_spawn_id": ""
		},

		"current_area_id": "",
		"current_area_scene": "",
		"current_spawn_id": "",
		"player_position": {
			"x": 0,
			"y": 0
		},

		"opened_packs": {},
		"story_flags": {},
		"npc_locations": {},
		"daily_spawn_rolls": {},
		"unlocked_packs": {},
		"inventory": {},
		"unlocked_cards": {},

		"active_quests": {},
		"completed_quests": {},
		"quest_steps_completed": {},

		"unlocked_dialogues": {},
		"completed_dialogues": {},
		"triggered_events": {},

		"relationships": {},

		"rank_points": 0,
		"player_rank": "",
		"ranks": {},
		"faction_reputation": {},
		"storyline_progress": {},

		"unlocked_areas": {},
		"unlocked_npcs": {},
		"unlocked_shops": {},

		"followers": {},
		"current_follower_id": "",

		"calendar": {
			"day": 1,
			"season": "",
			"time_of_day": "day",
			"hour": 8,
			"minute": 0
		},

		"reward_history": []
	}


func ensure_save_defaults() -> void:
	var defaults := get_default_save()

	for key in defaults.keys():
		if not save_data.has(key):
			save_data[key] = defaults[key]

	var dict_keys := [
		"save_metadata",
		"player_position",
		"opened_packs",
		"story_flags",
		"npc_locations",
		"daily_spawn_rolls",
		"unlocked_packs",
		"inventory",
		"unlocked_cards",
		"active_quests",
		"completed_quests",
		"quest_steps_completed",
		"unlocked_dialogues",
		"completed_dialogues",
		"triggered_events",
		"relationships",
		"ranks",
		"faction_reputation",
		"storyline_progress",
		"unlocked_areas",
		"unlocked_npcs",
		"unlocked_shops",
		"followers",
		"calendar"
	]

	for key in dict_keys:
		if typeof(save_data.get(key)) != TYPE_DICTIONARY:
			save_data[key] = defaults[key]

	if typeof(save_data.get("reward_history")) != TYPE_ARRAY:
		save_data["reward_history"] = []


func load_json_direct(path: String):
	if not FileAccess.file_exists(path):
		return {}

	var file := FileAccess.open(path, FileAccess.READ)

	if file == null:
		return {}

	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)

	if parsed == null:
		return {}

	return parsed


func save_json_direct(path: String, data) -> bool:
	var dir_path := path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))

	var file := FileAccess.open(path, FileAccess.WRITE)

	if file == null:
		push_error("SaveManager failed to write: " + path)
		return false

	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return true


func read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)

	if file == null:
		return ""

	var text := file.get_as_text()
	file.close()
	return text


func write_text(path: String, text: String) -> bool:
	var dir_path := path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))

	var file := FileAccess.open(path, FileAccess.WRITE)

	if file == null:
		return false

	file.store_string(text)
	file.close()
	return true


func get_save_data() -> Dictionary:
	return save_data


func get_value(key: String, fallback = null):
	return save_data.get(key, fallback)


func set_value(key: String, value, autosave_enabled := true) -> void:
	save_data[key] = value

	if autosave_enabled:
		save_game("autosave")


func get_currency() -> int:
	return int(save_data.get("currency", 0))


func set_currency(amount: int, autosave_enabled := true) -> void:
	save_data["currency"] = max(amount, 0)

	if autosave_enabled:
		save_game("autosave")


func add_currency(amount: int, autosave_enabled := true) -> void:
	save_data["currency"] = get_currency() + amount

	if autosave_enabled:
		save_game("autosave")


func has_flag(flag_id: String) -> bool:
	return bool(save_data["story_flags"].get(flag_id, false))


func set_flag(flag_id: String, value := true, autosave_enabled := true) -> void:
	flag_id = flag_id.strip_edges()

	if flag_id == "":
		return

	var old_value := bool(save_data["story_flags"].get(flag_id, false))
	save_data["story_flags"][flag_id] = value

	if old_value != bool(value):
		var spawn_manager := get_node_or_null("/root/NpcSpawnManager")
		if spawn_manager != null and spawn_manager.has_method("reroll_npc_locations_for_changed_flag"):
			spawn_manager.reroll_npc_locations_for_changed_flag(flag_id, false)

		_refresh_spawn_controlled_npcs()

	if autosave_enabled:
		save_game("autosave")


func remove_flag(flag_id: String, autosave_enabled := true) -> void:
	flag_id = flag_id.strip_edges()

	if flag_id == "":
		return

	var existed := bool(save_data["story_flags"].get(flag_id, false))
	save_data["story_flags"].erase(flag_id)

	if existed:
		var spawn_manager := get_node_or_null("/root/NpcSpawnManager")
		if spawn_manager != null and spawn_manager.has_method("reroll_npc_locations_for_changed_flag"):
			spawn_manager.reroll_npc_locations_for_changed_flag(flag_id, false)

		_refresh_spawn_controlled_npcs()

	if autosave_enabled:
		save_game("autosave")


func get_npc_location(npc_id: String) -> String:
	return str(get_npc_location_entry(npc_id).get("area_id", ""))


func get_npc_location_entry(npc_id: String) -> Dictionary:
	if typeof(save_data.get("npc_locations")) != TYPE_DICTIONARY:
		save_data["npc_locations"] = {}

	var raw_entry = save_data["npc_locations"].get(npc_id, "")

	if typeof(raw_entry) == TYPE_DICTIONARY:
		return raw_entry

	var area_id := str(raw_entry)

	if area_id == "":
		return {}

	# Backward compatibility with old saves:
	# old format was "npc_locations": { "axelscorch": "test_town" }
	return {
		"area_id": area_id,
		"location_id": "",
		"position": {"x": 0.0, "y": 0.0},
		"facing": "down",
		"no_spawn": false
	}


func set_npc_location(npc_id: String, area_id: String, autosave_enabled := true) -> void:
	set_npc_location_entry(npc_id, {
		"area_id": area_id,
		"location_id": "",
		"position": {"x": 0.0, "y": 0.0},
		"facing": "down",
		"no_spawn": false
	}, autosave_enabled)


func set_npc_location_entry(npc_id: String, location_entry: Dictionary, autosave_enabled := true) -> void:
	npc_id = npc_id.strip_edges()

	if npc_id == "":
		return

	if typeof(save_data.get("npc_locations")) != TYPE_DICTIONARY:
		save_data["npc_locations"] = {}

	save_data["npc_locations"][npc_id] = location_entry

	if autosave_enabled:
		save_game("npc_location_set")


func clear_npc_location(npc_id: String, autosave_enabled := true) -> void:
	npc_id = npc_id.strip_edges()

	if npc_id == "":
		return

	if typeof(save_data.get("npc_locations")) != TYPE_DICTIONARY:
		save_data["npc_locations"] = {}

	save_data["npc_locations"].erase(npc_id)

	if autosave_enabled:
		save_game("npc_location_cleared")


func get_daily_spawn_roll(npc_id: String) -> Dictionary:
	if typeof(save_data.get("daily_spawn_rolls")) != TYPE_DICTIONARY:
		save_data["daily_spawn_rolls"] = {}

	var entry = save_data["daily_spawn_rolls"].get(npc_id, {})

	if typeof(entry) != TYPE_DICTIONARY:
		return {}

	return entry


func set_daily_spawn_roll(npc_id: String, roll_entry: Dictionary, autosave_enabled := true) -> void:
	npc_id = npc_id.strip_edges()

	if npc_id == "":
		return

	if typeof(save_data.get("daily_spawn_rolls")) != TYPE_DICTIONARY:
		save_data["daily_spawn_rolls"] = {}

	save_data["daily_spawn_rolls"][npc_id] = roll_entry

	if autosave_enabled:
		save_game("daily_spawn_roll_set")


func clear_daily_spawn_rolls(autosave_enabled := true) -> void:
	save_data["daily_spawn_rolls"] = {}

	if autosave_enabled:
		save_game("daily_spawn_rolls_cleared")


func get_calendar_day() -> int:
	var calendar: Dictionary = save_data.get("calendar", {})
	return int(calendar.get("day", 1))


func _refresh_spawn_controlled_npcs() -> void:
	var tree := get_tree()

	if tree == null:
		return

	tree.call_group("spawn_controlled_npcs", "refresh_spawn_visibility")
	tree.call_group("area_npc_spawners", "refresh_area_spawns")


func has_item(item_id: String, amount := 1) -> bool:
	if item_id.strip_edges() == "":
		return false

	if typeof(save_data.get("inventory")) != TYPE_DICTIONARY:
		save_data["inventory"] = {}

	return int(save_data["inventory"].get(item_id, 0)) >= amount


func add_item(item_id: String, amount := 1, autosave_enabled := true) -> void:
	if item_id.strip_edges() == "":
		return

	if amount <= 0:
		return

	if typeof(save_data.get("inventory")) != TYPE_DICTIONARY:
		save_data["inventory"] = {}

	save_data["inventory"][item_id] = int(save_data["inventory"].get(item_id, 0)) + amount

	if autosave_enabled:
		save_game("autosave")


func remove_item(item_id: String, amount := 1, autosave_enabled := true) -> bool:
	if item_id.strip_edges() == "":
		return false

	if amount <= 0:
		return false

	if typeof(save_data.get("inventory")) != TYPE_DICTIONARY:
		save_data["inventory"] = {}

	if not has_item(item_id, amount):
		return false

	save_data["inventory"][item_id] = int(save_data["inventory"].get(item_id, 0)) - amount

	if int(save_data["inventory"][item_id]) <= 0:
		save_data["inventory"].erase(item_id)

	if autosave_enabled:
		save_game("autosave")

	return true

func get_item_count(item_id: String) -> int:
	if item_id.strip_edges() == "":
		return 0

	if typeof(save_data.get("inventory")) != TYPE_DICTIONARY:
		save_data["inventory"] = {}

	return int(save_data["inventory"].get(item_id, 0))

func unlock_pack(pack_id: String, autosave_enabled := true) -> void:
	if pack_id.strip_edges() == "":
		return

	save_data["unlocked_packs"][pack_id] = true

	if autosave_enabled:
		save_game("autosave")


func is_pack_unlocked(pack_id: String) -> bool:
	return bool(save_data["unlocked_packs"].get(pack_id, false))


func unlock_card(card_id: String, card_name := "Unknown Card", autosave_enabled := true) -> void:
	if card_id.strip_edges() == "":
		return

	save_data["unlocked_cards"][card_id] = card_name

	if autosave_enabled:
		save_game("autosave")


func is_card_unlocked(card_id: String) -> bool:
	return save_data["unlocked_cards"].has(card_id)


func start_quest(quest_id: String, autosave_enabled := true) -> void:
	if quest_id.strip_edges() == "":
		return

	if save_data["completed_quests"].has(quest_id):
		return

	save_data["active_quests"][quest_id] = {
		"status": "active",
		"started_at_unix": Time.get_unix_time_from_system()
	}

	if autosave_enabled:
		save_game("autosave")


func complete_quest(quest_id: String, autosave_enabled := true) -> void:
	if quest_id.strip_edges() == "":
		return

	save_data["completed_quests"][quest_id] = {
		"status": "completed",
		"completed_at_unix": Time.get_unix_time_from_system()
	}

	save_data["active_quests"].erase(quest_id)

	if autosave_enabled:
		save_game("autosave")


func is_quest_active(quest_id: String) -> bool:
	return save_data["active_quests"].has(quest_id)


func is_quest_completed(quest_id: String) -> bool:
	return save_data["completed_quests"].has(quest_id)


func complete_quest_step(step_key: String, autosave_enabled := true) -> void:
	if step_key.strip_edges() == "":
		return

	save_data["quest_steps_completed"][step_key] = true

	if autosave_enabled:
		save_game("autosave")


func is_quest_step_completed(step_key: String) -> bool:
	return bool(save_data["quest_steps_completed"].get(step_key, false))


func unlock_dialogue(dialogue_id: String, autosave_enabled := true) -> void:
	if dialogue_id.strip_edges() == "":
		return

	save_data["unlocked_dialogues"][dialogue_id] = true

	if autosave_enabled:
		save_game("autosave")


func is_dialogue_unlocked(dialogue_id: String) -> bool:
	return bool(save_data["unlocked_dialogues"].get(dialogue_id, false))


func complete_dialogue(dialogue_id: String, autosave_enabled := true) -> void:
	if dialogue_id.strip_edges() == "":
		return

	save_data["completed_dialogues"][dialogue_id] = true

	if autosave_enabled:
		save_game("autosave")


func is_dialogue_completed(dialogue_id: String) -> bool:
	return bool(save_data["completed_dialogues"].get(dialogue_id, false))


func trigger_event(event_id: String, autosave_enabled := true) -> void:
	if event_id.strip_edges() == "":
		return

	save_data["triggered_events"][event_id] = {
		"triggered": true,
		"triggered_at_unix": Time.get_unix_time_from_system()
	}

	if autosave_enabled:
		save_game("autosave")


func is_event_triggered(event_id: String) -> bool:
	return save_data["triggered_events"].has(event_id)


func add_relationship_points(npc_id: String, points: int, autosave_enabled := true) -> void:
	if npc_id.strip_edges() == "":
		return

	if not save_data["relationships"].has(npc_id):
		save_data["relationships"][npc_id] = {
			"points": 0,
			"level": 0
		}

	save_data["relationships"][npc_id]["points"] = int(save_data["relationships"][npc_id].get("points", 0)) + points

	if autosave_enabled:
		save_game("autosave")


func set_relationship_level(npc_id: String, level: int, autosave_enabled := true) -> void:
	if npc_id.strip_edges() == "":
		return

	if not save_data["relationships"].has(npc_id):
		save_data["relationships"][npc_id] = {
			"points": 0,
			"level": 0
		}

	save_data["relationships"][npc_id]["level"] = level

	if autosave_enabled:
		save_game("autosave")


func get_relationship_level(npc_id: String) -> int:
	if not save_data["relationships"].has(npc_id):
		return 0

	return int(save_data["relationships"][npc_id].get("level", 0))


func set_rank(rank_group: String, rank_id: String, autosave_enabled := true) -> void:
	if rank_group.strip_edges() == "":
		return

	save_data["ranks"][rank_group] = rank_id

	if autosave_enabled:
		save_game("autosave")


func get_rank(rank_group: String) -> String:
	return str(save_data["ranks"].get(rank_group, ""))


func add_faction_reputation(faction_id: String, amount: int, autosave_enabled := true) -> void:
	if faction_id.strip_edges() == "":
		return

	save_data["faction_reputation"][faction_id] = int(save_data["faction_reputation"].get(faction_id, 0)) + amount

	if autosave_enabled:
		save_game("autosave")


func get_faction_reputation(faction_id: String) -> int:
	return int(save_data["faction_reputation"].get(faction_id, 0))


func set_storyline_progress(storyline_id: String, value, autosave_enabled := true) -> void:
	if storyline_id.strip_edges() == "":
		return

	save_data["storyline_progress"][storyline_id] = value

	if autosave_enabled:
		save_game("autosave")


func get_storyline_progress(storyline_id):
	return save_data["storyline_progress"].get(storyline_id, null)


func unlock_area(area_id: String, autosave_enabled := true) -> void:
	if area_id.strip_edges() == "":
		return

	save_data["unlocked_areas"][area_id] = true

	if autosave_enabled:
		save_game("autosave")


func is_area_unlocked(area_id: String) -> bool:
	return bool(save_data["unlocked_areas"].get(area_id, false))


func unlock_npc(npc_id: String, autosave_enabled := true) -> void:
	if npc_id.strip_edges() == "":
		return

	save_data["unlocked_npcs"][npc_id] = true

	if autosave_enabled:
		save_game("autosave")


func is_npc_unlocked(npc_id: String) -> bool:
	return bool(save_data["unlocked_npcs"].get(npc_id, false))


func unlock_shop(shop_id: String, autosave_enabled := true) -> void:
	if shop_id.strip_edges() == "":
		return

	save_data["unlocked_shops"][shop_id] = true

	if autosave_enabled:
		save_game("autosave")


func is_shop_unlocked(shop_id: String) -> bool:
	return bool(save_data["unlocked_shops"].get(shop_id, false))



func capture_current_world_state(autosave_enabled := false) -> void:
	var current_scene := get_tree().current_scene

	if current_scene == null:
		return

	if current_scene.has_method("save_current_world_state"):
		current_scene.save_current_world_state(autosave_enabled)


func set_current_world_state(
	area_scene_path: String,
	area_id: String,
	spawn_id: String,
	player_global_position: Vector2,
	autosave_enabled := true
) -> void:
	save_data["current_area_scene"] = area_scene_path

	if area_id.strip_edges() != "":
		save_data["current_area_id"] = area_id

	save_data["current_spawn_id"] = spawn_id
	save_data["player_position"] = {
		"x": player_global_position.x,
		"y": player_global_position.y
	}

	if autosave_enabled:
		save_game("world_state_saved")


func set_current_area_scene(area_scene_path: String, autosave_enabled := true) -> void:
	save_data["current_area_scene"] = area_scene_path

	if autosave_enabled:
		save_game("current_area_scene_set")


func get_current_area_scene() -> String:
	return str(save_data.get("current_area_scene", ""))


func get_player_position() -> Vector2:
	var raw_position = save_data.get("player_position", {})

	if typeof(raw_position) != TYPE_DICTIONARY:
		return Vector2.ZERO

	return Vector2(
		float(raw_position.get("x", 0.0)),
		float(raw_position.get("y", 0.0))
	)


func set_current_location(area_id: String, spawn_id: String, autosave_enabled := true) -> void:
	save_data["current_area_id"] = area_id
	save_data["current_spawn_id"] = spawn_id

	if autosave_enabled:
		save_game("autosave")


func get_current_area_id() -> String:
	return str(save_data.get("current_area_id", ""))


func get_current_spawn_id() -> String:
	return str(save_data.get("current_spawn_id", ""))


func set_calendar_value(key: String, value, autosave_enabled := true) -> void:
	save_data["calendar"][key] = value

	if autosave_enabled:
		save_game("autosave")


func get_calendar_value(key: String, fallback = null):
	return save_data["calendar"].get(key, fallback)


func set_follower_unlocked(npc_id: String, value := true, autosave_enabled := true) -> void:
	if npc_id.strip_edges() == "":
		return

	if not save_data["followers"].has(npc_id):
		save_data["followers"][npc_id] = {}

	save_data["followers"][npc_id]["unlocked"] = value

	if autosave_enabled:
		save_game("autosave")


func is_follower_unlocked(npc_id: String) -> bool:
	if not save_data["followers"].has(npc_id):
		return false

	return bool(save_data["followers"][npc_id].get("unlocked", false))


func set_current_follower(npc_id: String, autosave_enabled := true) -> void:
	save_data["current_follower_id"] = npc_id

	if autosave_enabled:
		save_game("autosave")


func get_current_follower() -> String:
	return str(save_data.get("current_follower_id", ""))


func apply_effects(effects: Dictionary, autosave_enabled := true) -> void:
	for flag_id in effects.get("set_flags", []):
		set_flag(str(flag_id), true, false)

	for flag_id in effects.get("remove_flags", []):
		remove_flag(str(flag_id), false)

	for quest_id in effects.get("start_quests", []):
		start_quest(str(quest_id), false)

	for quest_id in effects.get("complete_quests", []):
		complete_quest(str(quest_id), false)

	for step_key in effects.get("complete_quest_steps", []):
		complete_quest_step(str(step_key), false)

	for dialogue_id in effects.get("unlock_dialogue_ids", []):
		unlock_dialogue(str(dialogue_id), false)

	for event_id in effects.get("trigger_event_ids", []):
		trigger_event(str(event_id), false)

	var rewards = effects.get("give_rewards", {})

	if typeof(rewards) == TYPE_DICTIONARY:
		add_currency(int(rewards.get("currency", 0)), false)

		for item in rewards.get("items", []):
			if typeof(item) == TYPE_DICTIONARY:
				add_item(str(item.get("item_id", "")), int(item.get("amount", 1)), false)
			else:
				add_item(str(item), 1, false)

		for pack_id in rewards.get("unlock_packs", []):
			unlock_pack(str(pack_id), false)

		for card in rewards.get("cards", []):
			if typeof(card) == TYPE_DICTIONARY:
				unlock_card(
					str(card.get("card_id", card.get("id", ""))),
					str(card.get("name", "Unknown Card")),
					false
				)
			else:
				unlock_card(str(card), "Unknown Card", false)

		var relationship_points = rewards.get("relationship_points", {})
		if typeof(relationship_points) == TYPE_DICTIONARY:
			for npc_id in relationship_points.keys():
				add_relationship_points(str(npc_id), int(relationship_points[npc_id]), false)

		var faction_reputation = rewards.get("faction_reputation", {})
		if typeof(faction_reputation) == TYPE_DICTIONARY:
			for faction_id in faction_reputation.keys():
				add_faction_reputation(str(faction_id), int(faction_reputation[faction_id]), false)

		var set_ranks = rewards.get("set_ranks", {})
		if typeof(set_ranks) == TYPE_DICTIONARY:
			for rank_group in set_ranks.keys():
				set_rank(str(rank_group), str(set_ranks[rank_group]), false)

	if autosave_enabled:
		save_game("autosave")


func is_valid_save_slot(slot_name: String) -> bool:
	return slot_name in ["slot_1", "slot_2", "slot_3"]


func get_save_path_for_slot(slot_name: String) -> String:
	return SAVES_FOLDER.path_join(slot_name).path_join("player_save.json")


func save_slot_exists(slot_name: String) -> bool:
	if not is_valid_save_slot(slot_name):
		return false

	var path := get_save_path_for_slot(slot_name)

	if not FileAccess.file_exists(path):
		return false

	var data = load_json_direct(path)
	return typeof(data) == TYPE_DICTIONARY and not data.is_empty()


func get_save_slot_summary(slot_name: String) -> Dictionary:
	if not is_valid_save_slot(slot_name):
		return {
			"exists": false,
			"slot_name": slot_name
		}

	var path := get_save_path_for_slot(slot_name)

	if not FileAccess.file_exists(path):
		return {
			"exists": false,
			"slot_name": slot_name
		}

	var data = load_json_direct(path)

	if typeof(data) != TYPE_DICTIONARY or data.is_empty():
		return {
			"exists": false,
			"slot_name": slot_name
		}

	var metadata: Dictionary = data.get("save_metadata", {})
	var calendar: Dictionary = data.get("calendar", {})

	var last_saved_unix := float(metadata.get("last_saved_unix", 0.0))
	var area_id := str(data.get("current_area_id", metadata.get("current_area_id", "")))
	var area_scene := str(data.get("current_area_scene", metadata.get("current_area_scene", "")))

	return {
		"exists": true,
		"slot_name": slot_name,
		"path": path,
		"location": _get_save_location_label(area_id, area_scene),
		"time_text": _get_calendar_display_text(calendar),
		"saved_at_unix": last_saved_unix,
		"saved_at_text": _format_unix_time(last_saved_unix)
	}


func get_most_recent_save_slot() -> String:
	var newest_slot := ""
	var newest_time := -1.0

	for slot_name in ["slot_1", "slot_2", "slot_3"]:
		var summary := get_save_slot_summary(slot_name)

		if summary.is_empty():
			continue

		if not bool(summary.get("exists", false)):
			continue

		var saved_time := float(summary.get("saved_at_unix", 0.0))

		if saved_time > newest_time:
			newest_time = saved_time
			newest_slot = slot_name

	return newest_slot


func manual_save_to_slot(slot_name: String) -> bool:
	return save_current_game_to_slot(slot_name)


func save_current_game_to_slot(slot_name: String) -> bool:
	if not is_valid_save_slot(slot_name):
		push_error("Invalid save slot: " + slot_name)
		return false

	capture_current_world_state(false)
	ensure_save_defaults()

	active_slot = slot_name
	active_save_path = get_save_path_for_slot(active_slot)
	save_json_direct(ACTIVE_SLOT_PATH, {"active_slot": active_slot})

	return save_game("manual_slot_save")


func _get_save_location_label(area_id: String, area_scene: String) -> String:
	if area_id.strip_edges() != "":
		return area_id.replace("_", " ").capitalize()

	if area_scene.strip_edges() != "":
		var file_name := area_scene.get_file().get_basename()
		return file_name.replace("_", " ").capitalize()

	return "Unknown Location"


func _get_calendar_display_text(calendar: Dictionary) -> String:
	var day := int(calendar.get("day", 1))
	var hour := int(calendar.get("hour", 8))
	var minute := int(calendar.get("minute", 0))
	var time_of_day := str(calendar.get("time_of_day", ""))

	var clock := str(hour).pad_zeros(2) + ":" + str(minute).pad_zeros(2)

	if time_of_day.strip_edges() != "":
		return "Day " + str(day) + " " + clock + " (" + time_of_day + ")"

	return "Day " + str(day) + " " + clock


func _format_unix_time(unix_time: float) -> String:
	if unix_time <= 0.0:
		return "Unknown Date"

	var date := Time.get_datetime_dict_from_unix_time(int(unix_time))

	var year := str(int(date.get("year", 0))).pad_zeros(4)
	var month := str(int(date.get("month", 0))).pad_zeros(2)
	var day := str(int(date.get("day", 0))).pad_zeros(2)
	var hour := str(int(date.get("hour", 0))).pad_zeros(2)
	var minute := str(int(date.get("minute", 0))).pad_zeros(2)

	return year + "-" + month + "-" + day + " " + hour + ":" + minute
