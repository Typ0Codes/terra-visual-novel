extends Node2D

@onready var sprite: Sprite2D = $SubViewportContainer/SubViewport/Sprite2D

func _ready() -> void:
	Globals.misgendered_triggered.connect(_flash_effect)

func _flash_effect() -> void:
	var mat := sprite.material as ShaderMaterial
	mat.set_shader_parameter("effect_enabled", true)
	await get_tree().create_timer(0.2).timeout
	mat.set_shader_parameter("effect_enabled", false)
