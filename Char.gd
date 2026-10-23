@tool
extends AnimatedSprite2D

@export var source_sprite: Sprite2D:
	set(value):
		source_sprite = value
		if is_node_ready():
			_rebuild()

var _viewport: SubViewport
var _proxy: Sprite2D

func _ready() -> void:
	_rebuild()

func _rebuild() -> void:
	if _viewport:
		_viewport.queue_free()
		_viewport = null
		_proxy = null

	var mat := material as ShaderMaterial
	if mat == null:
		return
	if source_sprite == null or source_sprite.texture == null:
		mat.set_shader_parameter("image_texture", null)
		return

	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	_proxy = Sprite2D.new()
	_viewport.add_child(_proxy)

	mat.set_shader_parameter("image_texture", _viewport.get_texture())
	_sync_proxy()

func _process(_delta: float) -> void:
	if _proxy:
		_sync_proxy()

func _sync_proxy() -> void:
	var src := source_sprite
	if src == null or src.texture == null:
		return

	var size := src.texture.get_size() / Vector2(src.hframes, src.vframes)
	if src.region_enabled:
		size = src.region_rect.size
	if _viewport.size != Vector2i(size):
		_viewport.size = Vector2i(size)

	_proxy.texture = src.texture
	_proxy.material = src.material  
	_proxy.hframes = src.hframes
	_proxy.vframes = src.vframes
	_proxy.frame = src.frame
	_proxy.region_enabled = src.region_enabled
	_proxy.region_rect = src.region_rect
	_proxy.flip_h = src.flip_h
	_proxy.flip_v = src.flip_v
	_proxy.centered = src.centered
