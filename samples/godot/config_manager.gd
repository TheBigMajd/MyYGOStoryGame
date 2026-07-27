extends Node

const CONFIG_ROOT := "res://GameData/configs"

const AREAS_PATH := CONFIG_ROOT + "/areas"
const DIALOGUE_PATH := CONFIG_ROOT + "/dialogue"
const DUEL_SESSIONS_PATH := CONFIG_ROOT + "/duel_sessions"
const INTERIORS_PATH := CONFIG_ROOT + "/interiors"
const MAPS_PATH := CONFIG_ROOT + "/maps"
const NPCS_PATH := CONFIG_ROOT + "/npcs"
const PACK_CONFIGS_PATH := CONFIG_ROOT + "/pack_configs"
const QUESTS_PATH := CONFIG_ROOT + "/quests"
const REGIONS_PATH := CONFIG_ROOT + "/regions"
const SHOP_CONFIGS_PATH := CONFIG_ROOT + "/shop_configs"

var _cache: Dictionary = {}

func load_json_file(path: String, use_cache: bool = true) -> Dictionary:
	if use_cache and _cache.has(path):
		return _cache[path].duplicate(true)

	if not FileAccess.file_exists(path):
		push_warning("ConfigManager: Missing config file: " + path)
		return {}

	var file := FileAccess.open(path, FileAccess.READ)

	if file == null:
		push_warning("ConfigManager: Could not open config file: " + path)
		return {}

	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)

	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("ConfigManager: Invalid JSON dictionary: " + path)
		return {}

	if use_cache:
		_cache[path] = parsed.duplicate(true)

	return parsed


func load_all_json_from_folder(folder_path: String, use_cache: bool = true) -> Array:
	var results := []

	var dir := DirAccess.open(folder_path)

	if dir == null:
		push_warning("ConfigManager: Missing config folder: " + folder_path)
		return results

	dir.list_dir_begin()

	while true:
		var file_name := dir.get_next()

		if file_name == "":
			break

		if dir.current_is_dir():
			continue

		if not file_name.ends_with(".json"):
			continue

		var full_path := folder_path.path_join(file_name)
		var data := load_json_file(full_path, use_cache)

		if not data.is_empty():
			results.append(data)

	dir.list_dir_end()

	return results


func get_config_by_id(folder_path: String, id_key: String, config_id: String) -> Dictionary:
	var direct_path := folder_path.path_join(config_id + ".json")

	if FileAccess.file_exists(direct_path):
		return load_json_file(direct_path)

	var configs := load_all_json_from_folder(folder_path)

	for config in configs:
		if str(config.get(id_key, "")) == config_id:
			return config

	return {}


func get_area(area_id: String) -> Dictionary:
	return get_config_by_id(AREAS_PATH, "area_id", area_id)


func get_dialogue(dialogue_id: String) -> Dictionary:
	return get_config_by_id(DIALOGUE_PATH, "dialogue_id", dialogue_id)


func get_duel_session(duel_session_id: String) -> Dictionary:
	return get_config_by_id(DUEL_SESSIONS_PATH, "session_id", duel_session_id)


func get_interior(interior_id: String) -> Dictionary:
	return get_config_by_id(INTERIORS_PATH, "interior_id", interior_id)


func get_map(map_id: String) -> Dictionary:
	return get_config_by_id(MAPS_PATH, "map_id", map_id)


func get_npc(npc_id: String) -> Dictionary:
	return get_config_by_id(NPCS_PATH, "npc_id", npc_id)


func get_pack_config(pack_id: String) -> Dictionary:
	return get_config_by_id(PACK_CONFIGS_PATH, "pack_id", pack_id)


func get_quest(quest_id: String) -> Dictionary:
	return get_config_by_id(QUESTS_PATH, "quest_id", quest_id)


func get_region(region_id: String) -> Dictionary:
	return get_config_by_id(REGIONS_PATH, "region_id", region_id)


func get_shop(shop_id: String) -> Dictionary:
	return get_config_by_id(SHOP_CONFIGS_PATH, "shop_id", shop_id)


func get_all_areas() -> Array:
	return load_all_json_from_folder(AREAS_PATH)


func get_all_dialogues() -> Array:
	return load_all_json_from_folder(DIALOGUE_PATH)


func get_all_duel_sessions() -> Array:
	return load_all_json_from_folder(DUEL_SESSIONS_PATH)


func get_all_interiors() -> Array:
	return load_all_json_from_folder(INTERIORS_PATH)


func get_all_npcs() -> Array:
	return load_all_json_from_folder(NPCS_PATH)


func get_all_quests() -> Array:
	return load_all_json_from_folder(QUESTS_PATH)


func get_all_regions() -> Array:
	return load_all_json_from_folder(REGIONS_PATH)


func get_all_shops() -> Array:
	return load_all_json_from_folder(SHOP_CONFIGS_PATH)


func clear_cache() -> void:
	_cache.clear()
