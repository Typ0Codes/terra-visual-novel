extends Node2D

@export_multiline var Dialouge: Array[String] = []
@export var Speaker: RichTextLabel
@onready var TextBox: RichTextLabel = $PanelContainer/GridContainer/VBoxContainer/Dialouge
@onready var AudioPlayer = $AudioStreamPlayer

const LINE_START_DELAY := 0.1
const ADVANCE_DELAY := 0.25
const FLASH_TIME := 0.2

var Proceeds := 0
var total_chars := 0
var typing_speed := 40.0
var progress := 0.0
var is_typing := false
var input_cooldown := 0.0

var misgender_index := -1
var misgender_fired := false
var flashing := false

func _ready() -> void:
	TextBox.bbcode_enabled = true
	_show_line()

func _show_line() -> void:
	var raw: String = Dialouge[Proceeds]
	TextBox.text = raw
	total_chars = TextBox.get_total_character_count()
	TextBox.visible_characters = 0
	progress = 0.0
	is_typing = true
	input_cooldown = LINE_START_DELAY
	flashing = false

	misgender_index = _find_tag_index(raw, "[misgender]")
	misgender_fired = false

# Counts visible characters before the tag, ignoring all other BBCode
func _find_tag_index(raw: String, tag: String) -> int:
	var tag_pos := raw.find(tag)
	if tag_pos == -1:
		return -1
	var before := raw.substr(0, tag_pos)
	var regex := RegEx.new()
	regex.compile("\\[[^\\]]*\\]")
	before = regex.sub(before, "", true)
	return before.length()

func _check_misgender() -> void:
	if misgender_index == -1 or misgender_fired:
		return
	if TextBox.visible_characters == -1 or TextBox.visible_characters > misgender_index:
		misgender_fired = true
		Globals.misgender()
		_flash_text()

func _finish_typing() -> void:
	is_typing = false
	TextBox.visible_characters = -1
	input_cooldown = ADVANCE_DELAY
	_check_misgender()

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
		_check_misgender()

	if new_count >= total_chars:
		_finish_typing()

func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("Proceed") or event.is_echo():
		return
	if input_cooldown > 0.0:
		return
	if is_typing:
		_finish_typing()
		return
	if Proceeds + 1 < Dialouge.size():
		Proceeds += 1
		_show_line()

func _flash_text() -> void:
	if flashing:
		return
	flashing = true

	var raw: String = Dialouge[Proceeds]
	var line_at_start := Proceeds
	var shown: int = TextBox.visible_characters

	# Only the [misgender] words become uppercase + red
	TextBox.text = _make_flash_text(raw)
	TextBox.visible_characters = shown

	await get_tree().create_timer(FLASH_TIME).timeout

	# Player moved to another line during the flash: leave the new line alone
	if Proceeds != line_at_start:
		return

	# Restore the original text, keeping current typing progress
	var now: int = TextBox.visible_characters
	TextBox.text = raw
	TextBox.visible_characters = now
	flashing = false

# Builds the flash version of the line: only text inside
# [misgender]...[/misgender] becomes uppercase + red.
func _make_flash_text(raw: String) -> String:
	var regex := RegEx.new()
	regex.compile("\\[misgender\\](.*?)\\[/misgender\\]")
	var out := ""
	var last := 0
	for m in regex.search_all(raw):
		out += raw.substr(last, m.get_start() - last)
		out += "[color=red]" + _upper_outside_tags(m.get_string(1)) + "[/color]"
		last = m.get_end()
	out += raw.substr(last)
	return out

# Uppercases text but leaves [tags] (and their parameters) alone
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
