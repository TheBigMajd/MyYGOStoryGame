extends Node

const DIALOGUE_ROOT := "res://GameData/configs/dialogue"

func load_dialogue_profile(profile_id: String) -> Dictionary:
	var path := ProjectSettings.globalize_path(DIALOGUE_ROOT.path_join(profile_id + ".json"))

	if not FileAccess.file_exists(path):
		push_error("Dialogue profile not found: " + path)
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Could not open dialogue profile: " + path)
		return {}

	var parsed = JSON.parse_string(file.get_as_text())
	file.close()

	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Invalid dialogue profile JSON: " + path)
		return {}

	return parsed


func get_profile_id_from_npc_config(npc_config: Dictionary) -> String:
	var base_profile: Dictionary = npc_config.get("base_profile", {})
	return str(base_profile.get("dialogue_profile_id", ""))


func get_greeting(dialogue_profile: Dictionary) -> Dictionary:
	var greetings: Array = dialogue_profile.get("greetings", [])
	var valid_greetings: Array = []

	for greeting in greetings:
		if typeof(greeting) != TYPE_DICTIONARY:
			continue

		var conditions: Dictionary = greeting.get("conditions", {})

		if ConditionManager.conditions_met(conditions):
			valid_greetings.append(greeting)

	if valid_greetings.is_empty():
		return {
			"speaker_name": dialogue_profile.get("display_name", "NPC"),
			"emotion": "neutral",
			"text": "Hello."
		}

	valid_greetings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("priority", 0)) > int(b.get("priority", 0))
	)

	var highest_priority: int = int(valid_greetings[0].get("priority", 0))
	var top_greetings: Array = []

	for greeting in valid_greetings:
		if int(greeting.get("priority", 0)) == highest_priority:
			top_greetings.append(greeting)

	if top_greetings.size() == 1:
		return top_greetings[0]

	return top_greetings[randi() % top_greetings.size()]


func get_talk_options(dialogue_profile: Dictionary) -> Array:
	var talk_menu: Dictionary = dialogue_profile.get("talk_menu", {})
	var options: Array = talk_menu.get("options", [])
	var valid_options: Array = []

	for option in options:
		if typeof(option) != TYPE_DICTIONARY:
			continue

		var conditions: Dictionary = option.get("conditions", {})

		if ConditionManager.conditions_met(conditions):
			valid_options.append(option)

	return valid_options


func get_dialogue_node(dialogue_profile: Dictionary, node_id: String) -> Dictionary:
	var nodes: Dictionary = dialogue_profile.get("nodes", {})
	var node = nodes.get(node_id, {})

	if typeof(node) != TYPE_DICTIONARY:
		return {}

	return node


func get_valid_choices(node: Dictionary) -> Array:
	var choices: Array = node.get("choices", [])
	var valid_choices: Array = []

	for choice in choices:
		if typeof(choice) != TYPE_DICTIONARY:
			continue

		var conditions: Dictionary = choice.get("conditions", {})

		if ConditionManager.conditions_met(conditions):
			valid_choices.append(choice)

	return valid_choices


func apply_effects(effects: Dictionary) -> void:
	if effects.is_empty():
		return

	_apply_set_flags(effects.get("set_flags", []))
	_apply_remove_flags(effects.get("remove_flags", []))
	_apply_add_items(effects.get("add_items", []))
	_apply_remove_items(effects.get("remove_items", []))
	_apply_start_quests(effects.get("start_quests", []))
	_apply_complete_quests(effects.get("complete_quests", []))
	_apply_complete_quest_steps(effects.get("complete_quest_steps", []))
	_apply_unlock_dialogues(effects.get("unlock_dialogue_ids", []))
	_apply_trigger_events(effects.get("trigger_event_ids", []))


func apply_on_shown(entry: Dictionary) -> void:
	var effects: Dictionary = entry.get("on_shown", {})
	apply_effects(effects)


func apply_on_enter(node: Dictionary) -> void:
	var effects: Dictionary = node.get("on_enter", {})
	apply_effects(effects)


func apply_on_selected(choice: Dictionary) -> void:
	var effects: Dictionary = choice.get("on_selected", {})
	apply_effects(effects)


func _load_player_save() -> Dictionary:
	var path := SaveManager.get_active_save_folder().path_join("player_save.json")

	if not FileAccess.file_exists(path):
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}

	var parsed = JSON.parse_string(file.get_as_text())
	file.close()

	if typeof(parsed) != TYPE_DICTIONARY:
		return {}

	return parsed


func _save_player_save(save_data: Dictionary) -> void:
	var path := SaveManager.get_active_save_folder().path_join("player_save.json")
	var file := FileAccess.open(path, FileAccess.WRITE)

	if file == null:
		push_error("DialogueManager could not save player_save.json")
		return

	file.store_string(JSON.stringify(save_data, "\t"))
	file.close()

	if SaveManager.has_method("reload_game"):
		SaveManager.reload_game()


func _ensure_dict(data: Dictionary, key: String) -> Dictionary:
	if not data.has(key) or typeof(data[key]) != TYPE_DICTIONARY:
		data[key] = {}

	return data[key]


func _apply_set_flags(flags: Array) -> void:
	if flags.is_empty():
		return

	var save_data := _load_player_save()
	var story_flags := _ensure_dict(save_data, "story_flags")

	for flag in flags:
		var id := str(flag).strip_edges()
		if id != "":
			story_flags[id] = true

	_save_player_save(save_data)


func _apply_remove_flags(flags: Array) -> void:
	if flags.is_empty():
		return

	var save_data := _load_player_save()
	var story_flags := _ensure_dict(save_data, "story_flags")

	for flag in flags:
		var id := str(flag).strip_edges()
		if id != "" and story_flags.has(id):
			story_flags.erase(id)

	_save_player_save(save_data)


func _apply_add_items(items: Array) -> void:
	if items.is_empty():
		return

	var save_data: Dictionary = _load_player_save()
	var inventory: Dictionary = _ensure_dict(save_data, "inventory")

	for item in items:
		var item_id: String = ""
		var amount: int = 1

		if typeof(item) == TYPE_DICTIONARY:
			var item_data: Dictionary = item
			item_id = str(item_data.get("item_id", "")).strip_edges()
			amount = int(item_data.get("amount", 1))
		else:
			item_id = str(item).strip_edges()

		if item_id == "" or amount <= 0:
			continue

		var current_amount: int = int(inventory.get(item_id, 0))
		inventory[item_id] = current_amount + amount
		var popup = get_node_or_null("/root/MessagePopup")

		if popup != null:
			popup.show_item_added(item_id, amount)
	_save_player_save(save_data)


func _apply_remove_items(items: Array) -> void:
	if items.is_empty():
		return

	var save_data: Dictionary = _load_player_save()
	var inventory: Dictionary = _ensure_dict(save_data, "inventory")

	for item in items:
		var item_id: String = ""
		var amount: int = 1

		if typeof(item) == TYPE_DICTIONARY:
			var item_data: Dictionary = item
			item_id = str(item_data.get("item_id", "")).strip_edges()
			amount = int(item_data.get("amount", 1))
		else:
			item_id = str(item).strip_edges()

		if item_id == "" or amount <= 0:
			continue

		var current_amount: int = int(inventory.get(item_id, 0))
		var new_amount: int = current_amount - amount

		if new_amount <= 0:
			inventory.erase(item_id)
		else:
			inventory[item_id] = new_amount
		var popup = get_node_or_null("/root/MessagePopup")

		if popup != null:
			popup.show_item_removed(item_id, amount)

	_save_player_save(save_data)


func _apply_start_quests(quest_ids: Array) -> void:
	if quest_ids.is_empty():
		return

	var save_data := _load_player_save()
	var active_quests := _ensure_dict(save_data, "active_quests")

	for quest_id in quest_ids:
		var id := str(quest_id).strip_edges()
		if id != "":
			active_quests[id] = {
				"status": "active",
				"started_from": "dialogue"
			}

	_save_player_save(save_data)


func _apply_complete_quests(quest_ids: Array) -> void:
	if quest_ids.is_empty():
		return

	var save_data := _load_player_save()
	var active_quests := _ensure_dict(save_data, "active_quests")
	var completed_quests := _ensure_dict(save_data, "completed_quests")

	for quest_id in quest_ids:
		var id := str(quest_id).strip_edges()
		if id != "":
			completed_quests[id] = {
				"status": "completed",
				"completed_from": "dialogue"
			}
			if active_quests.has(id):
				active_quests.erase(id)

	_save_player_save(save_data)


func _apply_complete_quest_steps(steps: Array) -> void:
	if steps.is_empty():
		return

	var save_data := _load_player_save()
	var completed_steps := _ensure_dict(save_data, "quest_steps_completed")

	for step in steps:
		var id := str(step).strip_edges()
		if id != "":
			completed_steps[id] = true

	_save_player_save(save_data)


func _apply_unlock_dialogues(dialogue_ids: Array) -> void:
	if dialogue_ids.is_empty():
		return

	var save_data := _load_player_save()
	var unlocked := _ensure_dict(save_data, "unlocked_dialogues")

	for dialogue_id in dialogue_ids:
		var id := str(dialogue_id).strip_edges()
		if id != "":
			unlocked[id] = true

	_save_player_save(save_data)


func _apply_trigger_events(event_ids: Array) -> void:
	if event_ids.is_empty():
		return

	var save_data := _load_player_save()
	var events := _ensure_dict(save_data, "triggered_events")

	for event_id in event_ids:
		var id := str(event_id).strip_edges()
		if id != "":
			events[id] = {
				"triggered": true,
				"triggered_from": "dialogue"
			}

	_save_player_save(save_data)
