@tool
extends AnimatedSprite2D

@export var palette_noise: NoiseTexture2D:
	set(value):
		if palette_noise and palette_noise.changed.is_connected(_apply_palette):
			palette_noise.changed.disconnect(_apply_palette)
		palette_noise = value
		if palette_noise:
			palette_noise.changed.connect(_apply_palette)
		_apply_palette()

@onready var earthbound = $SubViewport/Sprite2D.material as ShaderMaterial

func _ready() -> void:
	_apply_palette()

func _apply_palette() -> void:
	if not is_node_ready() or earthbound == null:
		return
	earthbound.set_shader_parameter("palette", palette_noise)
