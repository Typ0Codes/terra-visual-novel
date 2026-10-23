extends Node2D

@onready var sprite: Sprite2D = $SubViewportContainer/SubViewport/Sprite2D
@onready var talk_sprite = $TalkSprite
@onready var dialogue_manager = $DialogueManager

func _ready() -> void:
	Globals.misgendered_triggered.connect(_flash_effect)
	dialogue_manager.speaker_changed.connect(_on_speaker_changed)
	dialogue_manager.refresh_speaker()

func _on_speaker_changed(character: DialogueCharacter) -> void:
	print("root got speaker: ", character.character_name, " noise: ", character.palette_noise)
	if character.palette_noise:
		talk_sprite.palette_noise = character.palette_noise

func _flash_effect() -> void:
	var mat := sprite.material as ShaderMaterial
	mat.set_shader_parameter("effect_enabled", true)
	await get_tree().create_timer(0.2).timeout
	mat.set_shader_parameter("effect_enabled", false)
