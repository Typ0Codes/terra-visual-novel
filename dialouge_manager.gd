extends Node2D

signal speaker_changed(character: DialogueCharacter)
signal dialogue_finished

@export_file("*.dlg") var dialogue_path: String
@export var start_node := ""
@export var Speaker: RichTextLabel
@export var Characters: Array[DialogueCharacter] = []
@export var Backgrounds: Array[Background] = []

@export var Background_Node: Sprite2D

@export var portrait_node: AnimatedSprite2D

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
var bg_lookup := {}
var portrait_cache := {}
var bg_cache := {}
var current_speaker: DialogueCharacter = null
var current_background: Background = null


var tag_handlers := {}
var triggers: Array[Dictionary] = []
var tag_regex := RegEx.new()

var substitutions := {}


func _ready() -> void:
	tag_regex.compile("\\[(/?)([A-Za-z_]\\w*)(?:=([^\\]]*))?\\]")
	TextBox.bbcode_enabled = true
	_build_characters()
	_build_Bgs()              
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
	
	_register_default_tags()
	_register_default_substitutions()




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
			
				
		if s.begins_with("[if "):
			var close := s.find("]")
			var arrow := s.find("=>", close)
			if close == -1 or arrow == -1:
				push_warning("Bad if on line %d (needs '[if var value] => target')" % line_no)
				continue
			var cond := _parse_condition(s.substr(4, close - 4).strip_edges())
			if cond.is_empty():
				push_warning("Bad condition on line %d" % line_no)
				continue
			nodes[current]["lines"].append({
				"cond": cond,
				"target": s.substr(arrow + 2).strip_edges(),
			})
			last_line = {}   
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
	register_tag("loadscene", _tag_load_scene)
	register_tag("bg",        _tag_bg, Callable(), true)
	register_tag("portrait",  _tag_portrait, Callable(), true)
	register_tag("telltale",  _tag_telltale_they_will_remember_that, Callable(), true)
	register_tag("titlecard", _tag_titlecard)


func _tag_speaker(arg: String, _ctx: Dictionary) -> void:
	var key := arg.strip_edges().to_lower()
	if not character_lookup.has(key):
		push_warning("Unknown speaker: " + key)
		return
	_set_speaker(character_lookup[key], key)

func _tag_load_scene(arg: String, _ctx: Dictionary) -> void:
	var scene_path := arg.strip_edges()
	get_tree().change_scene_to_file(scene_path)
	
func _tag_titlecard(arg: String, _ctx: Dictionary) -> void:
	var text := arg.strip_edges()
	$Titlecard.text = text
	$Titlecard.visible = true
	await get_tree().create_timer(1).timeout
	$Titlecard.visible = false  
	
func _tag_telltale_they_will_remember_that(arg: String, _ctx: Dictionary) -> void:
	var parts := arg.split(",", true, 1)
	if parts.size() < 2:
		push_warning("set tag needs 'variable,value': " + arg)
		return

	var variable := parts[0].strip_edges()   
	var raw_value := parts[1].strip_edges()

	if not variable in Globals:
		push_warning("Globals has no variable: " + variable)
		return

	Globals.set(variable, _parse_value(raw_value))

func _parse_value(raw: String) -> Variant:
	var v = str_to_var(raw)   
	if v == null and raw != "null":
		return raw
	return v
	
func _tag_portrait(arg: String, _ctx: Dictionary) -> void:
	var portraitname := arg.strip_edges().to_lower()
	portrait_node.animation = portraitname
	
func _tag_bg(arg: String, _ctx: Dictionary) -> void:
	var key := arg.strip_edges().to_lower()
	if not bg_lookup.has(key):
		push_warning("Unknown background: " + key)
		return
	_set_bg(bg_lookup[key], key)
	

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
		
		if substitutions.has(tag):
			if not is_close:
				var value: String = substitutions[tag].call(arg)
				out += value.replace("[", "[lb]")   
				visible += value.length()
			continue

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
	_enter_line()          

func _advance() -> void:
	var node: Dictionary = nodes[current_node]
	if line_idx + 1 < node["lines"].size():
		line_idx += 1
		_enter_line()     
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

	var remaining := target
	for m in tag_regex.search_all(target):
		var tag := m.get_string(2).to_lower()
		if tag_handlers.has(tag):
			var arg := m.get_string(3)
			var ctx := {"name": tag, "arg": arg, "text_start": 0, "text_end": -1}
			tag_handlers[tag]["on_open"].call(arg, ctx)
		remaining = remaining.replace(m.get_string(), "")
	remaining = remaining.strip_edges()

	if remaining == "":
		_advance()          
	else:
		_go_to(remaining)



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
			portrait_cache[key] = _make_portrait(c.portrait, key)
			
func _build_Bgs() -> void:
	for c in Backgrounds:
		if c == null:
			continue
		var key := c.background_name.to_lower()   
		bg_lookup[key] = c
		if c.background_path:
			bg_cache[key] = _make_background(c.background_path, key)

func _make_portrait(tex: Texture2D, who := "") -> Texture2D:
	var img := tex.get_image()
	if img == null:
		push_warning("Can't read portrait image for '%s' (%s), using it unresized" % [who, tex])
		return tex
	if img.is_compressed():
		img.decompress()
	img.resize(PORTRAIT_SIZE, PORTRAIT_SIZE, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)

func _make_background(tex: Texture2D, who := "") -> Texture2D:
	var img := tex.get_image()
	if img == null:
		push_warning("Can't read background image for '%s' (%s), using it unresized" % [who, tex])
		return tex
	if img.is_compressed():
		img.decompress()
	img.resize(1152, 648, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)

func _set_speaker(c: DialogueCharacter, key: String) -> void:
	current_speaker = c
	if Speaker:
		Speaker.text = c.character_name
		if c.talk_sound:
			AudioPlayer.stream = c.talk_sound
	Portrait.texture = portrait_cache.get(key, null)
	speaker_changed.emit(c)
	
func _set_bg(c: Background, key: String) -> void:
	current_background = c
	if Background_Node:
		Background_Node.texture = bg_cache.get(key, null)  

func refresh_speaker() -> void:
	if current_speaker:
		speaker_changed.emit(current_speaker)
		
const CONDITION_OPS := ["==", "!=", "<=", ">=", "<", ">"]

func _parse_condition(s: String) -> Dictionary:
	var parts := s.split(" ", false)
	if parts.is_empty():
		return {}
	var cond := {"var": parts[0], "op": "truthy", "value": null}
	if parts.size() == 1:
		return cond                   

	var op := "=="
	var value_parts := parts.slice(1)
	if value_parts[0] in CONDITION_OPS:
		op = value_parts[0]
		value_parts = value_parts.slice(1)
	if value_parts.is_empty():
		return {}
	cond["op"] = op
	cond["value"] = _parse_value(" ".join(value_parts))
	return cond

func _eval_condition(cond: Dictionary) -> bool:
	var var_name: String = cond["var"]
	if not var_name in Globals:
		push_warning("Globals has no variable: " + var_name)
		return false
	var current = Globals.get(var_name)
	var expected = cond["value"]
	match cond["op"]:
		"truthy": return bool(current)
		"==": return current == expected
		"!=": return current != expected
		"<":  return current < expected
		">":  return current > expected
		"<=": return current <= expected
		">=": return current >= expected
	return false


func _enter_line() -> void:
	while true:
		var node: Dictionary = nodes[current_node]
		if line_idx >= node["lines"].size():
			
			if node["goto"] != "":
				_go_to(node["goto"])
			else:
				dialogue_finished.emit()
			return
		var entry: Dictionary = node["lines"][line_idx]
		if not entry.has("cond"):
			_show_line()
			return
		if _eval_condition(entry["cond"]):
			_go_to(entry["target"])
			return
		line_idx += 1

func register_substitution(tag_name: String, getter: Callable) -> void:
	substitutions[tag_name.to_lower()] = getter

func _register_default_substitutions() -> void:
	register_substitution("playername", _sub_player_name)
	register_substitution("var", _sub_global)

func _sub_player_name(_arg: String) -> String:
	return _global_as_string("player_name")   

func _sub_global(arg: String) -> String:
	return _global_as_string(arg.strip_edges())

func _global_as_string(variable: String) -> String:
	if not variable in Globals:
		push_warning("Globals has no variable: " + variable)
		return ""
	return str(Globals.get(variable))
