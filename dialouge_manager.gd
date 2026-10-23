extends Node2D

signal speaker_changed(character: DialogueCharacter)
signal dialogue_finished

@export_file("*.txt") var dialogue_path: String
@export var start_node := ""
@export var Speaker: RichTextLabel
@export var Characters: Array[DialogueCharacter] = []

@onready var TextBox: RichTextLabel = $PanelContainer/GridContainer/VBoxContainer/Dialouge
@onready var AudioPlayer = $AudioStreamPlayer
@onready var Portrait: TextureRect = $PanelContainer/GridContainer/TextureRect

const LINE_START_DELAY := 0.1
const ADVANCE_DELAY := 0.25
const FLASH_TIME := 0.2
const PORTRAIT_SIZE := 160


var nodes := {}          
var first_node := ""
var current_node := ""
var line_idx := 0


var Proceeds := 0        
var total_chars := 0
var typing_speed := 40.0
var progress := 0.0
var is_typing := false
var input_cooldown := 0.0
var flashing := false
var display_line := ""


var pending_choices: Array[Dictionary] = []
var choosing := false
var ChoiceBox: VBoxContainer


var character_lookup := {}
var portrait_cache := {}
var current_speaker: DialogueCharacter = null


var tag_handlers := {}
var triggers: Array[Dictionary] = []
var tag_regex := RegEx.new()


func _ready() -> void:
	tag_regex.compile("\\[(/?)([A-Za-z_]\\w*)(?:=([^\\]]*))?\\]")
	TextBox.bbcode_enabled = true
	_build_characters()
	_register_default_tags()

	ChoiceBox = VBoxContainer.new()
	ChoiceBox.visible = false
	ChoiceBox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ChoiceBox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	TextBox.get_parent().add_child(ChoiceBox)
	TextBox.get_parent().move_child(ChoiceBox, TextBox.get_index() + 1)

	load_script(dialogue_path)
	if first_node == "":
		push_warning("Dialogue file has no blocks: " + dialogue_path)
		return
	_go_to(start_node if start_node != "" else first_node)




func load_script(path: String) -> void:
	nodes.clear()
	first_node = ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Can't open dialogue file: " + path)
		return

	var current := ""
	var last_line := {}
	var line_no := 0

	while not file.eof_reached():
		var s := file.get_line().strip_edges()
		line_no += 1
		if s == "" or s.begins_with("#"):
			continue


		if s.begins_with("~"):
			current = s.substr(1).strip_edges()
			nodes[current] = {"lines": [], "goto": ""}
			if first_node == "":
				first_node = current
			last_line = {}
			continue

		if current == "":
			push_warning("Line %d is before any ~ block" % line_no)
			continue


		if s.begins_with("=>"):
			nodes[current]["goto"] = s.substr(2).strip_edges()
			continue


		if s.begins_with("-"):
			var parts := s.substr(1).rsplit("=>", true, 1)
			if last_line.is_empty() or parts.size() < 2:
				push_warning("Bad choice on line %d (needs a line above and 'text => target')" % line_no)
				continue
			last_line["choices"].append({
				"text": parts[0].strip_edges(),
				"target": parts[1].strip_edges(),
			})
			continue


		var text := s
		var colon := s.find(":")
		if colon > 0:
			var key := s.substr(0, colon).strip_edges().to_lower()
			if character_lookup.has(key):
				text = "[speaker=%s]%s" % [key, s.substr(colon + 1).strip_edges()]

		last_line = {"text": text, "choices": []}
		nodes[current]["lines"].append(last_line)




func register_tag(tag_name: String, on_open: Callable, on_close: Callable = Callable(), at_line_start := false) -> void:
	tag_handlers[tag_name.to_lower()] = {
		"on_open": on_open,
		"on_close": on_close,
		"at_line_start": at_line_start,
	}

func _register_default_tags() -> void:
	register_tag("speaker",   _tag_speaker, Callable(), true)
	register_tag("restore",   _tag_restore)
	register_tag("misgender", _tag_misgender)
	register_tag("example",   _tag_example)
	register_tag("loadscene",   _tag_load_scene)

func _tag_speaker(arg: String, _ctx: Dictionary) -> void:
	var key := arg.strip_edges().to_lower()
	if not character_lookup.has(key):
		push_warning("Unknown speaker: " + key)
		return
	_set_speaker(character_lookup[key], key)

func _tag_load_scene(arg: String, _ctx: Dictionary) -> void:
	var scene_path := arg.strip_edges()
	get_tree().change_scene_to_file(scene_path)

func _tag_restore(arg: String, _ctx: Dictionary) -> void:
	Globals.restore(arg.to_int() if arg != "" else 1)

func _tag_misgender(_arg: String, ctx: Dictionary) -> void:
	print("misgender fired on line ", Proceeds, " | spoons before: ", Globals.spoons)
	Globals.misgender()
	print("spoons after: ", Globals.spoons)
	_flash_range(ctx["text_start"], ctx["text_end"])

func _tag_example(_arg: String, _ctx: Dictionary) -> void:
	print("waow test code")


func _parse_line(raw: String) -> String:
	triggers.clear()
	var out := ""
	var visible := 0
	var last := 0
	var open_stack := {}

	for m in tag_regex.search_all(raw):
		var is_close := m.get_string(1) == "/"
		var tag := m.get_string(2).to_lower()
		var arg := m.get_string(3)

		var between := raw.substr(last, m.get_start() - last)
		out += between
		visible += between.length()
		last = m.get_end()

		if not tag_handlers.has(tag):
			out += m.get_string()
			continue

		var handler: Dictionary = tag_handlers[tag]

		if not is_close:
			var ctx := {
				"name": tag,
				"arg": arg,
				"index": visible,
				"text_start": out.length(),
				"text_end": -1,
			}
			if not open_stack.has(tag):
				open_stack[tag] = []
			open_stack[tag].append(ctx)
			triggers.append({
				"index": -1 if handler["at_line_start"] else visible,
				"callable": handler["on_open"],
				"ctx": ctx,
				"fired": false,
			})
		else:
			if open_stack.has(tag) and not open_stack[tag].is_empty():
				var ctx: Dictionary = open_stack[tag].pop_back()
				ctx["text_end"] = out.length()
				if handler["on_close"].is_valid():
					triggers.append({
						"index": visible,
						"callable": handler["on_close"],
						"ctx": ctx,
						"fired": false,
					})

	out += raw.substr(last)
	return out

func _check_triggers() -> void:
	var vc: int = TextBox.visible_characters
	for t in triggers:
		if t["fired"]:
			continue
		if vc == -1 or vc > t["index"]:
			t["fired"] = true
			var cb: Callable = t["callable"]
			if cb.is_valid():
				cb.call(t["ctx"]["arg"], t["ctx"])




func _show_line() -> void:
	Proceeds += 1
	var line: Dictionary = nodes[current_node]["lines"][line_idx]

	pending_choices.clear()
	for choice in line["choices"]:
		pending_choices.append(choice)

	display_line = _parse_line(line["text"])
	TextBox.text = display_line
	total_chars = TextBox.get_total_character_count()
	TextBox.visible_characters = 0
	progress = 0.0
	is_typing = true
	input_cooldown = LINE_START_DELAY
	flashing = false

	for t in triggers:
		if t["index"] == -1:
			t["fired"] = true
			var cb: Callable = t["callable"]
			if cb.is_valid():
				cb.call(t["ctx"]["arg"], t["ctx"])

func _go_to(target: String) -> void:
	if target == "end":
		dialogue_finished.emit()
		return
	if not nodes.has(target) or nodes[target]["lines"].is_empty():
		push_warning("Unknown or empty block: " + target)
		return
	current_node = target
	line_idx = 0
	_show_line()

func _advance() -> void:
	var node: Dictionary = nodes[current_node]
	if line_idx + 1 < node["lines"].size():
		line_idx += 1
		_show_line()
	elif node["goto"] != "":
		_go_to(node["goto"])
	else:
		dialogue_finished.emit()

func _finish_typing() -> void:
	is_typing = false
	TextBox.visible_characters = -1
	input_cooldown = ADVANCE_DELAY
	_check_triggers()

func _process(delta: float) -> void:
	if input_cooldown > 0.0:
		input_cooldown -= delta

	if not is_typing:
		return

	progress += typing_speed * delta
	var new_count := mini(int(progress), total_chars)

	if new_count > TextBox.visible_characters:
		TextBox.visible_characters = new_count
		AudioPlayer.play()
		_check_triggers()

	if new_count >= total_chars:
		_finish_typing()

func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("Proceed") or event.is_echo():
		return
	if choosing or input_cooldown > 0.0:
		return
	if is_typing:
		_finish_typing()
		return
	if not pending_choices.is_empty():
		_show_choices()
		get_viewport().set_input_as_handled()
		return
	_advance()



func _show_choices() -> void:
	choosing = true
	TextBox.visible = false
	
	for old in ChoiceBox.get_children():
		ChoiceBox.remove_child(old)
		old.queue_free()
	ChoiceBox.mouse_filter = Control.MOUSE_FILTER_PASS
	for choice in pending_choices:
		var b := Button.new()
		b.text = choice["text"]
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		b.custom_minimum_size = Vector2(0, 32)
		b.pressed.connect(_on_choice_picked.bind(choice["target"]))
		ChoiceBox.add_child(b)
	ChoiceBox.visible = true
	
	ChoiceBox.get_child(0).call_deferred("grab_focus")

func _on_choice_picked(target: String) -> void:
	choosing = false
	ChoiceBox.visible = false
	TextBox.visible = true
	input_cooldown = LINE_START_DELAY
	_go_to(target)



func _flash_range(text_start: int, text_end: int) -> void:
	if flashing or text_end == -1:
		return
	flashing = true

	var raw := display_line
	var line_at_start := Proceeds
	var shown: int = TextBox.visible_characters

	var flashed := raw.substr(0, text_start) \
		+ "[color=red]" + _upper_outside_tags(raw.substr(text_start, text_end - text_start)) + "[/color]" \
		+ raw.substr(text_end)
	TextBox.text = flashed
	TextBox.visible_characters = shown

	await get_tree().create_timer(FLASH_TIME).timeout

	if Proceeds != line_at_start:
		return

	var now: int = TextBox.visible_characters
	TextBox.text = raw
	TextBox.visible_characters = now
	flashing = false

func _upper_outside_tags(s: String) -> String:
	var out := ""
	var in_tag := false
	for c in s:
		if c == "[":
			in_tag = true
		if in_tag:
			out += c
		else:
			out += c.to_upper()
		if c == "]":
			in_tag = false
	return out



func _build_characters() -> void:
	for c in Characters:
		if c == null:
			continue
		var key := c.character_name.to_lower()
		character_lookup[key] = c
		if c.portrait:
			portrait_cache[key] = _make_portrait(c.portrait)

func _make_portrait(tex: Texture2D) -> ImageTexture:
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	img.resize(PORTRAIT_SIZE, PORTRAIT_SIZE, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)

func _set_speaker(c: DialogueCharacter, key: String) -> void:
	current_speaker = c
	if Speaker:
		Speaker.text = c.character_name
		if c.talk_sound:
			AudioPlayer.stream = c.talk_sound
	Portrait.texture = portrait_cache.get(key, null)
	speaker_changed.emit(c)

func refresh_speaker() -> void:
	if current_speaker:
		speaker_changed.emit(current_speaker)
