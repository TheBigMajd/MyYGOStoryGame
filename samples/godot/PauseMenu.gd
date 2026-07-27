extends Control

@export_file("*.tscn") var save_menu_scene_path: String = "res://Scenes/UI/SaveMenu.tscn"

@onready var dim_background: Control = $DimBackground
@onready var pause_panel: Control = $PausePanel
@onready var save_button: Button = find_child("Save", true, false) as Button
@onready var inventory_button: Button = find_child("Inventory", true, false) as Button

var is_open := false
var save_menu_instance: Control = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	is_open = false

	if save_button != null:
		save_button.pressed.connect(_on_save_pressed)

	if inventory_button != null:
		inventory_button.grab_focus()


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("inventory"):
		if save_menu_instance != null and is_instance_valid(save_menu_instance):
			if save_menu_instance.has_method("close_menu"):
				save_menu_instance.close_menu()
			else:
				_restore_after_save_menu_closed()
			return

		if is_open:
			close_menu()
		else:
			open_menu()


func _play_sfx(sfx_id: String) -> void:
	if SfxManager != null and SfxManager.has_method("play"):
		SfxManager.play(sfx_id)


func open_menu() -> void:
	_play_sfx("inventory_open")

	is_open = true
	visible = true
	get_tree().paused = true

	if inventory_button != null:
		inventory_button.grab_focus()


func close_menu() -> void:
	_play_sfx("inventory_close")

	if save_menu_instance != null and is_instance_valid(save_menu_instance):
		save_menu_instance.queue_free()
		save_menu_instance = null

	is_open = false
	visible = false
	get_tree().paused = false


func _on_save_pressed() -> void:
	_play_sfx("ui_confirm")

	if save_menu_instance != null and is_instance_valid(save_menu_instance):
		if save_menu_instance.has_method("close_menu"):
			save_menu_instance.close_menu()
		else:
			_restore_after_save_menu_closed()
		return

	var save_menu_scene := load(save_menu_scene_path) as PackedScene

	if save_menu_scene == null:
		push_error("SaveMenu scene failed to load: " + save_menu_scene_path)
		return

	save_menu_instance = save_menu_scene.instantiate() as Control

	if save_menu_instance == null:
		push_error("SaveMenu scene did not instantiate as Control.")
		return

	var ui_root := get_parent()

	if ui_root == null:
		push_error("PauseMenu has no parent UIRoot for SaveMenu.")
		save_menu_instance.queue_free()
		save_menu_instance = null
		return

	visible = false

	ui_root.add_child(save_menu_instance)
	save_menu_instance.process_mode = Node.PROCESS_MODE_ALWAYS

	if save_menu_instance.has_method("setup"):
		save_menu_instance.setup(self)

	if save_menu_instance.has_signal("save_menu_closed"):
		save_menu_instance.save_menu_closed.connect(_restore_after_save_menu_closed)


func _restore_after_save_menu_closed() -> void:
	if save_menu_instance != null and is_instance_valid(save_menu_instance):
		save_menu_instance.queue_free()

	save_menu_instance = null

	if is_open:
		visible = true

		if inventory_button != null:
			inventory_button.grab_focus()
