extends Area2D

@export_file("*.tscn") var target_area_scene: String = ""
@export var target_spawn_name: String = "PlayerSpawn"

var can_trigger: bool = true

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if not can_trigger:
		return

	if not body is CharacterBody2D:
		return

	can_trigger = false

	var world := get_tree().current_scene

	if world != null and world.has_method("load_area"):
		world.load_area(target_area_scene, target_spawn_name)
	else:
		push_error("AreaDoor could not find World.load_area()")
