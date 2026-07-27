extends Panel

const DEV_PYTHON_EXE := "C:/Users/Majde/anaconda3/python.exe"

const ROOM_HOST := "127.0.0.1"
const ROOM_PORT := 7911
const ROOM_WAIT_SECONDS := 180
const ROOM_CHECK_INTERVAL := 1.0

@onready var prompt_label: Label = $ContentMargin/VBox/PromptLabel
@onready var status_label: Label = $ContentMargin/VBox/StatusLabel
@onready var yes_button: Button = $ContentMargin/VBox/ButtonRow/YesButton
@onready var no_button: Button = $ContentMargin/VBox/ButtonRow/NoButton

var launcher_root := ""
var possible_game_roots: Array[String] = []
var edopro_pid := -1
var windbot_launched := false
var session_active := false
var duel_session_id: String = ""


func setup_duel(new_duel_session_id: String) -> void:
	duel_session_id = new_duel_session_id.strip_edges()

	if prompt_label != null:
		prompt_label.text = "Start Duel: " + duel_session_id + "?"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	if MusicManager != null:
		MusicManager.pause_music()

	launcher_root = get_launcher_root()
	possible_game_roots = [
		launcher_root,
		launcher_root.get_base_dir(),
		launcher_root.get_base_dir().get_base_dir()
	]

	if duel_session_id == "":
		prompt_label.text = "Start Duel?"
	else:
		prompt_label.text = "Start Duel: " + duel_session_id + "?"

	status_label.text = "Waiting..."

	yes_button.pressed.connect(_on_yes_pressed)
	no_button.pressed.connect(_on_no_pressed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		restore_windbot_safely()
		get_tree().paused = false
		get_tree().quit()


func get_launcher_root() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://").trim_suffix("/")
	return OS.get_executable_path().get_base_dir()


func find_sibling_folder(folder_name: String) -> String:
	for root in possible_game_roots:
		var candidate := root.path_join(folder_name)
		if DirAccess.dir_exists_absolute(candidate):
			return candidate
	return ""


func _on_yes_pressed() -> void:
	if duel_session_id == "":
		status_label.text = "Missing duel_session_id. NPC must pass a duel session ID."
		yes_button.disabled = false
		return
	
	yes_button.visible = false
	yes_button.disabled = true
	no_button.disabled = false

	edopro_pid = -1
	windbot_launched = false
	session_active = false

	status_label.text = "Preparing WindBot duel session: " + duel_session_id + "..."

	if not run_python_tool_with_args("prepare_windbot_session.py", [duel_session_id]):
		restore_windbot_safely()
		yes_button.disabled = false
		return

	session_active = true
	SaveManager.block_saving("duel_active")

	status_label.text = "Running pre-duel validation..."

	if not run_pre_duel_validator():
		restore_windbot_safely()
		yes_button.disabled = false
		return

	var validation_result := load_validation_result()

	if not validation_result["loaded"]:
		restore_windbot_safely()
		status_label.text = validation_result["message"]
		yes_button.disabled = false
		return

	if not validation_result["valid"]:
		restore_windbot_safely()
		status_label.text = format_validation_error(validation_result)
		yes_button.disabled = false
		return

	status_label.text = validation_result["message"] + "\nLaunching EDOPro..."

	if not launch_edopro():
		restore_windbot_safely()
		yes_button.disabled = false
		return

	monitor_edopro_close()
	wait_for_room_then_launch_windbot()


func _on_no_pressed() -> void:
	restore_windbot_safely()

	if MusicManager != null:
		MusicManager.resume_current_zone()

	get_tree().paused = false
	queue_free()


func restore_windbot_safely() -> void:
	if not session_active:
		run_python_tool("restore_windbot_session.py")

		if SaveManager.is_saving_blocked():
			SaveManager.unblock_saving()

		return

	run_python_tool("restore_windbot_session.py")
	session_active = false
	windbot_launched = false

	if SaveManager.is_saving_blocked():
		SaveManager.unblock_saving()


func wait_for_room_then_launch_windbot() -> void:
	status_label.text = "EDOPro launched.\nIn EDOPro: LAN + AI → Host → OK.\nWaiting for room on port " + str(ROOM_PORT) + "..."

	var elapsed := 0.0

	while elapsed < ROOM_WAIT_SECONDS:
		if edopro_pid != -1 and not OS.is_process_running(edopro_pid):
			restore_windbot_safely()
			status_label.text = "EDOPro closed before room was detected.\nWindBot files restored."
			yes_button.disabled = false
			return

		if await is_port_open(ROOM_HOST, ROOM_PORT):
			status_label.text = "Room detected.\nLaunching WindBot through Python..."
			await get_tree().create_timer(2.0).timeout
			launch_windbot_from_session()
			return

		await get_tree().create_timer(ROOM_CHECK_INTERVAL).timeout
		elapsed += ROOM_CHECK_INTERVAL

	restore_windbot_safely()
	status_label.text = "Timed out waiting for LAN + AI room.\nWindBot files restored."
	yes_button.disabled = false


func is_port_open(host: String, port: int) -> bool:
	var tcp := StreamPeerTCP.new()
	var err := tcp.connect_to_host(host, port)

	if err != OK:
		return false

	var start := Time.get_ticks_msec()

	while Time.get_ticks_msec() - start < 350:
		tcp.poll()

		if tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			tcp.disconnect_from_host()
			return true

		if tcp.get_status() == StreamPeerTCP.STATUS_ERROR:
			tcp.disconnect_from_host()
			return false

		await get_tree().create_timer(0.05).timeout

	tcp.disconnect_from_host()
	return false


func monitor_edopro_close() -> void:
	while edopro_pid != -1 and OS.is_process_running(edopro_pid):
		await get_tree().create_timer(2.0).timeout

	if session_active:
		status_label.text = "EDOPro closed.\nRunning post-duel validation..."

		var post_valid := run_post_duel_validator()
		var post_result := load_post_duel_validation_result()
		var rewards_applied := false

		if post_valid:
			if post_result.get("allow_reward", false):
				rewards_applied = run_apply_duel_rewards()

		restore_windbot_safely()

		if rewards_applied:
			SaveManager.reload_game()

		if post_valid:
			if post_result.get("allow_reward", false):
				var reward_data = post_result.get("reward", {})
				if rewards_applied:
					status_label.text = "Post-duel validation passed.\nReward applied: " + str(reward_data)
				else:
					status_label.text = "Post-duel validation passed.\nReward application failed."
			else:
				status_label.text = "Post-duel validation passed.\nNo reward for this outcome."
		else:
			status_label.text = "Post-duel validation failed.\nReward blocked.\n" + str(post_result.get("message", "Unknown post-duel validation error."))

	get_tree().paused = false
	yes_button.disabled = false


func run_apply_duel_rewards() -> bool:
	return run_python_tool("apply_duel_rewards.py")


func get_python_path() -> String:
	var python_folder := find_sibling_folder("Python")

	if python_folder != "":
		var portable_python := python_folder.path_join("python.exe")
		if FileAccess.file_exists(portable_python):
			return portable_python

	return DEV_PYTHON_EXE


func run_python_tool(script_name: String) -> bool:
	return run_python_tool_with_args(script_name, [])


func run_python_tool_with_args(script_name: String, args: Array[String]) -> bool:
	var python_exe := get_python_path()
	var script_path := launcher_root.path_join("Tools").path_join(script_name)

	if not FileAccess.file_exists(python_exe):
		status_label.text = "Python not found:\n" + python_exe
		return false

	if not FileAccess.file_exists(script_path):
		status_label.text = "Python tool not found:\n" + script_path
		return false

	var final_args: Array[String] = [script_path]
	final_args.append_array(args)

	var output: Array = []
	var exit_code := OS.execute(python_exe, final_args, output, true)

	if exit_code != 0:
		status_label.text = script_name + " failed.\nExit code: " + str(exit_code) + "\n\n" + "\n".join(output)
		return false

	return true


func run_pre_duel_validator() -> bool:
	return run_python_tool("pre_duel_validate.py")


func run_post_duel_validator() -> bool:
	return run_python_tool("post_duel_validate.py")


func load_post_duel_validation_result() -> Dictionary:
	var result_path := launcher_root.path_join("GameData/runtime/post_duel_validation_result.json")

	if not FileAccess.file_exists(result_path):
		return {
			"loaded": false,
			"valid": false,
			"allow_reward": false,
			"message": "post_duel_validation_result.json not found."
		}

	var file := FileAccess.open(result_path, FileAccess.READ)

	if file == null:
		return {
			"loaded": false,
			"valid": false,
			"allow_reward": false,
			"message": "Could not open post_duel_validation_result.json."
		}

	var parsed = JSON.parse_string(file.get_as_text())
	file.close()

	if typeof(parsed) != TYPE_DICTIONARY:
		return {
			"loaded": false,
			"valid": false,
			"allow_reward": false,
			"message": "post_duel_validation_result.json invalid."
		}

	parsed["loaded"] = true
	return parsed


func load_validation_result() -> Dictionary:
	var result_path := launcher_root.path_join("GameData/runtime/validation_result.json")

	if not FileAccess.file_exists(result_path):
		return {
			"loaded": false,
			"valid": false,
			"message": "validation_result.json not found."
		}

	var file := FileAccess.open(result_path, FileAccess.READ)

	if file == null:
		return {
			"loaded": false,
			"valid": false,
			"message": "Could not open validation_result.json."
		}

	var parsed = JSON.parse_string(file.get_as_text())
	file.close()

	if typeof(parsed) != TYPE_DICTIONARY:
		return {
			"loaded": false,
			"valid": false,
			"message": "validation_result.json invalid."
		}

	parsed["loaded"] = true
	return parsed


func format_validation_error(result: Dictionary) -> String:
	var lines: Array[String] = []

	lines.append(str(result.get("message", "Validation failed.")))
	lines.append("")

	var illegal_decks = result.get("illegal_decks", {})

	if typeof(illegal_decks) != TYPE_DICTIONARY:
		return "\n".join(lines)

	for deck_name in illegal_decks.keys():
		lines.append("Deck: " + str(deck_name))

		var deck_data = illegal_decks[deck_name]

		if deck_data.has("locked_cards"):
			var locked_cards = deck_data["locked_cards"]
			if locked_cards.size() > 0:
				lines.append("Locked cards:")
				for card in locked_cards:
					lines.append("- " + str(card["id"]) + " / " + str(card["name"]))

		if deck_data.has("missing_from_cdb"):
			var missing_cards = deck_data["missing_from_cdb"]
			if missing_cards.size() > 0:
				lines.append("Missing from CDB:")
				for card in missing_cards:
					lines.append("- " + str(card["id"]) + " / " + str(card["name"]))

		lines.append("")

	return "\n".join(lines)


func launch_edopro() -> bool:
	var edopro_folder := find_sibling_folder("EDOPro")

	if edopro_folder == "":
		status_label.text = "EDOPro folder not found."
		return false

	var edopro_path := edopro_folder.path_join("EDOPro.exe")

	if not FileAccess.file_exists(edopro_path):
		status_label.text = "EDOPro.exe not found:\n" + edopro_path
		return false

	edopro_pid = OS.create_process(edopro_path, [])

	if edopro_pid == -1:
		status_label.text = "Failed to launch EDOPro."
		return false

	return true


func load_current_duel_session() -> Dictionary:
	var session_path := launcher_root.path_join("GameData/runtime/current_duel_session.json")

	if not FileAccess.file_exists(session_path):
		return {}

	var file := FileAccess.open(session_path, FileAccess.READ)

	if file == null:
		return {}

	var parsed = JSON.parse_string(file.get_as_text())
	file.close()

	if typeof(parsed) != TYPE_DICTIONARY:
		return {}

	return parsed


func launch_windbot_from_session() -> void:
	if windbot_launched:
		return

	if not run_python_tool("launch_windbot_from_session.py"):
		restore_windbot_safely()
		status_label.text = "Failed to launch WindBot through Python."
		yes_button.disabled = false
		return

	windbot_launched = true
	status_label.text = "WindBot launched through Python.\nDuel can begin.\nWindBot files will restore when EDOPro closes."


func build_dbpaths(edopro_folder: String) -> String:
	var dbs: Array[String] = []

	var candidate_paths := [
		"expansions/cards-rush.cdb",
		"expansions/cards-skills-unofficial.cdb",
		"expansions/cards-skills.cdb",
		"expansions/cards-unofficial-new.cdb",
		"expansions/cards-unofficial.cdb",
		"expansions/cards.cdb",
		"expansions/custom.cdb",
		"expansions/goat-entries.cdb",
		"repositories/delta-bagooska/cards-rush.delta.cdb",
		"repositories/delta-bagooska/cards-skills.delta.cdb",
		"repositories/delta-bagooska/cards-unofficial.delta.cdb",
		"repositories/delta-bagooska/cards.delta.cdb",
		"repositories/delta-bagooska/goat-entries.delta.cdb",
		"repositories/delta-bagooska/prerelease-betb.cdb",
		"repositories/delta-bagooska/prerelease-blzd-en.cdb",
		"repositories/delta-bagooska/prerelease-cards-rush.cdb",
		"repositories/delta-bagooska/prerelease-cori.cdb",
		"repositories/delta-bagooska/prerelease-others.cdb",
		"repositories/delta-bagooska/prerelease-rv01.cdb",
		"repositories/delta-bagooska/release-blzd.cdb"
	]

	for relative_path in candidate_paths:
		var full_path := edopro_folder.path_join(relative_path)

		if FileAccess.file_exists(full_path):
			dbs.append(full_path.replace("\\", "/"))

	var json_text := JSON.stringify(dbs)
	return Marshalls.raw_to_base64(json_text.to_utf8_buffer())
